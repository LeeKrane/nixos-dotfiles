# Desktop notification for pending flake updates

The weekly `update` workflow (`.github/workflows/update.yml`) pushes
`ci/flake-update` and opens a pull request, but nothing on the hosts says so.
This spec adds a Home Manager timer that checks for that pull request and
raises a desktop notification once per new update.

## Goals

- Notify on every host when an update pull request is open, once per pushed
  head commit.
- Show whether the gate passed and which package versions changed.
- One click opens the pull request in the browser.

## Non-goals

- Detecting a running system that is behind `main` after a merge.
- Running `nix flake update` locally; CI already does it.
- Merging, checking out or switching from the notification.

## Approach

The repo is public, so the script calls the GitHub REST API with `curl`,
unauthenticated. `gh` is not logged in on every host, and one call a day is far
below the 60 requests/hour unauthenticated limit.

## Components

### `pkgs/flake-update-notify/`

A `writeShellApplication` (built and shellchecked on its own, like
`pkgs/proton-drive-mount`), exposed through `pkgs/default.nix`. Runtime inputs:
`curl`, `jq`, `libnotify`, `xdg-utils`, `coreutils`, `systemd`.

Environment, set by the module:

- `REPO`: `owner/name`, e.g. `LeeKrane/nixos-dotfiles`.
- `BRANCH`: head branch, `ci/flake-update`.

State: `${XDG_STATE_HOME:-$HOME/.local/state}/flake-update-notify/last-seen`,
two lines: `head.sha`, then a `sha256sum` of `number` + `title` + `body`.

Flow:

1. `GET https://api.github.com/repos/$REPO/pulls?head=<owner>:$BRANCH&state=open`.
   A curl or HTTP failure prints the error to stderr and exits 1. No
   notification, state untouched, so the next run retries.
2. Empty array: remove the state file and exit 0. A later pull request
   notifies again even if it reuses a head commit.
3. Take the first pull request's `head.sha`, `number`, `html_url`, `title`,
   `body`, and hash `number` + `title` + `body` with `sha256sum`. If both the
   SHA and the hash match the state file's two lines, exit 0. The update job
   force-pushes the run's commit to a staging branch first; the pr job builds
   the title and body, then moves `ci/flake-update` to that exact commit, and
   only then edits the open pull request in place (or opens one if none is
   open) — so the branch move and the pull request edit are adjacent steps,
   not simultaneous. If the edit step itself fails after the branch has
   already moved, `ci/flake-update` points at the new commit while the pull
   request still shows the previous title and body; the notifier sees the new
   SHA with a stale body, so it won't match a prior state file and notifies
   again once a later run succeeds in updating the body. Keying the hash on
   `number` + `title` + `body` as well as the SHA
   still matters: a new pull request notifies even when its SHA and body
   match the last-seen one (the previous one was merged or closed by hand).
4. Build the notification:
   - Summary: `Flake update ready (#<N>)`, using the pull request's `number`,
     or, when the title starts with `[gate failing]`,
     `Flake update ready (#<N>) (gate failing)` with `--urgency=critical`.
   - Body: one line per row of the body's `### Package versions` table,
     as `<package> <before> → <after>`, capped at the first 5 *packages*, not
     rows, with a trailing `...and <N> more` line when there are more. This
     is a guard, not a routine case: `scripts/update-versions.nix` tracks a
     fixed small set of packages, so the table is normally well under the
     cap, and it only bites a lockstep nixpkgs bump that happens to touch
     most of that set at once. A package split across hosts
     (`scripts/update-summary.sh`'s 4-column "Hosts" form) spans several
     consecutive rows sharing one package name; all of them count as one
     package against the cap. If that section is missing, the body is
     `<N> inputs updated`, counted from the `### Inputs` table rows. The body
     format comes from `scripts/update-summary.sh`. A security status line is
     then appended as the body's last line, when there is one:
     - When the body has a `### Security` section
       (`scripts/security-summary.sh`), its one-line summary sentence — one
       of `No CVE changes`, `<N> CVEs fixed, <M> new` (singular `CVE` when
       `<N>` or `<M>`, independently, is 1), `<N> CVEs fixed` or `<M> new
       CVEs` — is appended verbatim. Nothing is appended if the heading has
       no sentence before the next heading.
     - Otherwise, when the body has a headingless `Security scan failed
       ([run](...))` line (the security job itself failed,
       `.github/workflows/update.yml`), that line is appended with its
       `([run](...))` link stripped down to plain text: `Security scan
       failed`.

     CVEs never affect urgency or the summary: only the `[gate failing]`
     title does. security-summary.sh's own header says why: it reports CVEs
     "only, never gating the PR or its title", and a failed vulnix scan (as
     opposed to one that completes and finds nothing) reads as an empty
     list, so a "before" scan failure would otherwise show every current CVE
     as new and could flip urgency on a scan outage rather than an actual
     regression.
5. Probe the notification daemon (`busctl --user call
   org.freedesktop.Notifications /org/freedesktop/Notifications
   org.freedesktop.Notifications GetServerInformation`) before writing any
   state. A daemon that isn't up yet (racing the session at login) fails the
   probe: exit 1, state untouched, same retry path as a curl failure above —
   so a retry never re-shows a popup that was never shown in the first
   place.
6. Write the SHA and hash to the state file before notifying, so a
   dismissed or ignored notification does not repeat.
7. `notify-send -a Dotfiles --action=open="Open PR" --expire-time=0
   --hint=boolean:x-ii-expanded:true --wait ...` (expire time 0 keeps the
   popup on screen until dismissed; the `x-ii-expanded` hint is read by
   ii's `06-notifications` patch, which starts a flagged notification
   expanded so the "Open PR" button is visible without a right-click). If
   it prints `open`, run `xdg-open "$html_url"`. A `notify-send` failure here
   is timed (bash `$SECONDS`) rather than treated as one outcome: `--wait`
   blocks until the popup closes, so a real notification takes far longer
   than a failure before the daemon ever renders anything (the probe above
   already confirmed the daemon answers; this failure is something else). A
   failure within 2 seconds (`NOTIFY_FAIL_THRESHOLD`, overridable for tests)
   reads as no popup shown: state is removed, a warning goes to stderr, and
   the run exits 1 to retry, same as the probe above. A failure past that
   threshold reads as a popup already on screen: state is kept, a warning
   goes to stderr, and the run exits 0 instead, so a retry can't show that
   popup twice.

### `modules/home/flake-update-notify.nix`

Imported from `modules/home/default.nix`, so every host gets it.

- `systemd.user.services.flake-update-notify`: `Type=oneshot`,
  `ExecStart` the package, `Environment` `REPO` and `BRANCH`.
  `After`/`PartOf`/`Requisite` `graphical-session.target`, since `notify-send`
  and `xdg-open` need the session (`Requisite` fails the start outside one
  instead of pulling a session up). `Restart=on-failure`, `RestartSec=2min`:
  a start soon after login can race the network or the notification daemon
  coming up, so curl, or the script's own notification-daemon probe, failing
  there is retried instead of waiting for the next daily trigger. State is
  written only once that probe succeeds, so a retry never re-shows an
  already-displayed popup. Past that point, the script times `notify-send`
  itself (see Flow step 7 above): a quick failure (no popup ever rendered)
  removes state and exits 1, so this still retries it; a failure after a
  delay (a popup was likely shown) keeps state and exits 0 instead, so a
  retry can't show that popup twice. `StartLimitIntervalSec=30min` with
  `StartLimitBurst=5` caps those retries at 5 starts per 30 minutes, after
  which the unit waits for the next timer trigger.
- `systemd.user.timers.flake-update-notify`: `OnCalendar=daily`,
  `OnActiveSec=1min`, `Persistent=true`, `PartOf=graphical-session.target`,
  `WantedBy=graphical-session.target` (not `timers.target`): bound to the
  session like the service's `Requisite` above, so the timer stops at
  logout instead of lingering. `OnActiveSec` is relative to the timer's own
  activation, which `PartOf`/`WantedBy` on `graphical-session.target` ties
  to session start, so `OnActiveSec=1min` re-arms fresh at each login
  instead of counting from whatever instant `systemd --user` itself
  started. No `RandomizedDelaySec` layered on top, so `OnActiveSec=1min` is
  the real post-login delay.

`REPO` lives in one `let` binding in the module.

## Error handling

- Network down or API error: exit 1, visible in
  `journalctl --user -u flake-update-notify`, retried next run.
- Rate limit (403/429): same path as any HTTP error.
- No graphical session: `Requisite=graphical-session.target` fails the start
  cleanly instead of pulling a session up. The timer itself is
  `PartOf`/`WantedBy` `graphical-session.target`, so it stops at logout;
  there's no lingering, so no catch-up runs before the next login; recovery
  is `OnActiveSec=1min` after login, or the next daily trigger. `Restart`
  does not cover this case: the job fails, not the service.
- Notification daemon not reachable (probe fails): exit 1, state untouched,
  same retry path as a network error above.
- `notify-send` fails after the probe already passed: timed against
  `NOTIFY_FAIL_THRESHOLD` (default 2 seconds). A quick failure means no
  popup was shown: state removed, warning to stderr, exit 1, retried same
  as above. A failure past the threshold means a popup was likely shown:
  state kept, warning to stderr, exit 0, not retried, so it's never
  re-shown.

## Testing

- `nix build .#flake-update-notify` (shellcheck runs in the build).
- Eval checks for `taractias`, `tariognatha`, `tarmantria`.
- Manual: `systemctl --user start flake-update-notify` with no state file
  fires the notification; a second start stays silent; writing a wrong SHA
  to the state file fires it again. With no open pull request, the state
  file is removed.

## Related

The update pull request body is generated by `scripts/update-summary.sh`
(package version table, input table, raw log in a collapsed block) and,
when the security job succeeds, `scripts/security-summary.sh` (CVE diff and
local-build counts). This notifier depends on the former's `### Package
versions` and `### Inputs` headings, and on the latter's `### Security`
heading and its one-line summary sentence.
