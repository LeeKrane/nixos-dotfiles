# Automatic server upgrades with failure notifications

The weekly `update` workflow (`.github/workflows/update.yml`) bumps every flake input,
including the stable inputs the servers use (`nixos-raspberrypi`, which `nixpkgs-stable`
follows, `home-manager-stable`, `nixvim-stable`). Two gaps remain. The Raspberry Pis
(taronychus, tarritator, tarronax) never reach the update PR's CVE scan, local-build count or
version table, because `scripts/hosts.nix` keeps x86_64 hosts only. And nothing deploys a
merged change to any server: each one stays on its old generation until someone runs
`just switch <host>` on it.

This spec adds the Pis to the PR report and makes every server upgrade itself to each
gated `main` commit, with a health check, automatic rollback and a notification on failure.

## Goals

- The update PR's security summary and version table cover all four servers.
- Every server (taragarmr, taronychus, tarritator, tarronax) runs the latest `main` commit
  whose `check.yml` gate passed, within about an hour of the gate passing.
- A failed upgrade leaves the server on its previous, working generation.
- A failure reaches the owner within minutes: an ntfy push to the phone and desktops, plus
  exactly one GitHub issue per upgrade cycle, no matter how many servers fail.
- Kernel, initrd and firmware changes take effect the same night, one host at a time.

## Non-goals

- Automatic upgrades of the desktops. They keep `just switch` and `flake-update-notify`.
- Recovering a server whose new kernel does not boot at all. That still needs a manual
  pick in the bootloader.
- Building server closures in CI or on a build host. A derivation missing from the binary
  caches is built on the server itself.
- Logs in GitHub. The repo is public; logs go to ntfy only.

## Decisions

| Question | Decision |
|---|---|
| Push or pull | Pull. Each server polls hourly. GitHub holds no SSH or WireGuard keys, and an offline server catches up when it comes back. |
| Mechanism | Upstream `system.autoUpgrade`, plus small hooks. It already provides the timer, the stable per-host offset and the kernel-diff reboot window. |
| Gate | `check.yml` moves a `deploy` branch to each `main` commit that passed. Servers track `deploy`, never `main`. |
| Which commits | Every gated `main` commit, not only update-PR merges, so servers never drift from `main`. |
| On failure | Roll back if activation happened, mark the SHA failed, notify. No hourly retries of a failed SHA. |
| Reboots | Only inside a nightly one-hour window per host: tarronax 02–03, tarritator 03–04, taronychus 04–05, taragarmr 05–06. The Pis go first and the WireGuard hub last. |
| Notification | ntfy on taragarmr (WireGuard only) for every failure and recovery, plus a GitHub issue created only on failure, at most one per upgrade cycle (target SHA). |

Why `system.autoUpgrade` over a custom script: the custom script would reimplement the
timer and the booted-vs-new kernel comparison, which is the riskiest logic to get wrong.
The price is hook ordering (upstream reboots before `ExecStartPost` runs), which the
boot-time health unit below handles.

## Components

### 1. Pis in the update PR (`.github/workflows/update.yml`)

`scripts/hosts.nix` stays x86-only. It still drives `check.yml`'s per-host eval matrix,
and `checks.pi-eval` already evaluates the Pis there.

update.yml gets an all-hosts list, `builtins.attrNames hostMeta`
(`nix eval --json --impure '.#lib.hostMeta' --apply builtins.attrNames`). It feeds:

- the `update` job's `hosts` output, which the `security` job reads;
- `scripts/update-versions.nix`, which takes the host list as an argument instead of
  importing `hosts.nix`. The version table then has rows for the Pis. Desktop-only rows
  (Hyprland, Quickshell, zen-browser) are null on servers and render as `-`, as they do for
  taragarmr today. The "Linux kernel" row shows the rpi kernel for the Pis.

Security job, on the x86 runner:

- Evaluating aarch64 toplevels on x86 already works (`checks.pi-eval`). vulnix reads
  `.drv` closures, which do not depend on the platform, so the Pis get the same
  before/after CVE diff.
- `install-nix-action` gets `extra_nix_config` with the nixos-raspberrypi substituter and
  its public key, copied from `modules/nixos/common/nix-settings.nix`. Without them every
  Pi kernel counts as a local build.

Open risk: `nix build --dry-run` of an aarch64 `.drv` on x86 should only query the
substituters. A spike verifies this first. If it refuses, the Pis get a second matrix leg on
the free `ubuntu-24.04-arm` runner.

Cost: six more evaluations per weekly run (three Pis, before and after), about 5–10
minutes.

### 2. The `deploy` branch (`.github/workflows/check.yml`)

A final job, `promote`:

- runs only when `github.event_name == 'push'` and `github.ref == 'refs/heads/main'`, so
  never on pull requests or on update.yml's `workflow_call` (which checks the staging
  commit);
- `needs` every gate job and runs only if all of them succeeded;
- runs `git push origin "$GITHUB_SHA":refs/heads/deploy`, a fast-forward without
  `--force`. If `main` was rewritten, the push fails and the job reports it;
- is the only job with `contents: write`.

### 3. Revision stamp (`lib/mk-host.nix`)

`system.configurationRevision = self.rev or "dirty";`. A server reads the commit it runs with
`nixos-version --configuration-revision`, so the hooks need no "deployed SHA" state file.

### 4. `modules/nixos/server/auto-upgrade.nix`

Imported by `modules/nixos/server/default.nix`, so every `role = "server"` host gets it.

```nix
system.autoUpgrade = {
  enable = true;
  flake = "github:LeeKrane/nixos-dotfiles/deploy#${hostName}";
  flags = [ "--refresh" ];     # bypass the 1h tarball cache
  dates = "hourly";
  randomizedDelaySec = "10min";
  fixedRandomDelay = true;     # stable per-host offset
  persistent = true;
  allowReboot = true;
  rebootWindow = cfg.rebootWindow;
};
```

Options:

- `krane.autoUpgrade.rebootWindow` (`{ lower; upper; }`, no default, so a server without one
  fails evaluation). Set in each host's `default.nix`: tarronax `02:00`–`03:00`,
  tarritator `03:00`–`04:00`, taronychus `04:00`–`05:00`, taragarmr `05:00`–`06:00`. A
  one-hour window always contains exactly one hourly run.
- `krane.autoUpgrade.healthChecks` (list of shell commands, each must exit 0). Default: no
  failed units (`systemctl --failed --no-legend` prints nothing). The Pis add a ping of the
  hub's WireGuard address from `lib/wireguard.nix`. taragarmr adds a `curl` of its Caddy
  endpoints.

State lives in `/var/lib/server-upgrade/` (`StateDirectory`):

- `failed-sha`: the last `deploy` SHA that failed on this host.
- `pre-switch`: the `/run/current-system` store path before the current run.
- `pending-check`: the SHA whose health check has not run yet.
- `rolled-back`: set by the boot-time unit before its rollback reboot, so it reboots at most
  once.
- `outbox/`: undelivered notifications (component 6).

Hooks on `nixos-upgrade.service`:

- `ExecCondition`: resolve the `deploy` SHA with
  `git ls-remote https://github.com/LeeKrane/nixos-dotfiles refs/heads/deploy`, then skip
  the run if either holds:
  - the SHA equals `failed-sha`;
  - the SHA equals the deployed revision and no reboot is pending (the booted kernel,
    initrd and kernel modules match `/run/current-system`).

  The first rule stops a retry loop on a broken commit. The second skips the hourly
  evaluation when nothing changed, which matters on the Pi 4. A reboot pending from an
  earlier switch still lets the run through, so the reboot window works. The branch can
  move between this check and the build; at worst that wastes one run.
- `ExecStartPre`: write `pre-switch` and `pending-check`.
- `ExecStartPost`: run the health checks. On success, remove `pending-check`; if
  `failed-sha` was set, clear it and queue a recovery message. On failure, exit non-zero,
  which triggers `OnFailure`.
- `OnFailure=server-upgrade-failed.service`: if `/run/current-system` differs from
  `pre-switch`, activation happened, so run `nixos-rebuild switch --rollback` (which also
  resets the boot default). Then write `failed-sha`, remove `pending-check`, and queue a
  failure message with the stage (`build`, `activation` or `health`) and whether it rolled
  back.

`server-upgrade-health.service`, at boot (`After=multi-user.target network-online.target`):

- runs only when `pending-check` exists, which means upstream rebooted for a new kernel
  before `ExecStartPost` could run;
- waits up to 5 minutes for the system to settle, then runs the same health checks;
- on success: remove `pending-check` and `rolled-back`, queue a recovery message if
  `failed-sha` was set;
- on failure without `rolled-back`: roll back, write `failed-sha` and `rolled-back`, queue
  a failure message (stage `boot-health`), reboot into the previous generation;
- on failure with `rolled-back` set: do not reboot again; queue a failure message saying the
  rollback did not help.

Limits:

- A kernel that does not boot never reaches this unit. The Pi 5's generational loader keeps
  the previous entry, but choosing it needs physical access.
- A derivation not in the caches is built on the server.

### 5. ntfy (`hosts/taragarmr/`)

- `services.ntfy-sh`, listening only on taragarmr's WireGuard address. No Caddy vhost, no
  public exposure.
- `auth-default-access = "deny-all"` and two users, so a leaked token can do only one
  thing: `upgrade-publisher` may only write to `server-upgrades` (token on the servers,
  `server-upgrade/ntfy-publish-token`), and `krane` may only read it (token on the desktops
  and the phone, `server-upgrade/ntfy-read-token`). Both tokens are created on taragarmr
  once ntfy runs (see Secrets and Rollout).
- Phone: the ntfy app subscribes to `server-upgrades` through the WireGuard address with
  instant delivery on. This relies on the phone's WireGuard tunnel staying up
  (PersistentKeepalive is already set for it).
- Desktops: `modules/home/desktop/server-upgrade-notify.nix`, a user service running
  `ntfy subscribe` with a `notify-send` command, bound to `graphical-session.target` like
  `flake-update-notify`.

Messages:

- Failure, high priority: title `<host> upgrade failed (<sha7>)`; body: stage, whether it
  rolled back, and the last 30 lines of `journalctl -u nixos-upgrade -b`.
- Recovery, low priority: `<host> recovered on <sha7>`.

When taragarmr itself fails, it rolls back first and notifies afterwards, so ntfy is running
again by then. The GitHub issue covers cases where ntfy is unreachable.

### 6. GitHub issue (`scripts/server-upgrade-report.sh`)

A `curl` + `jq` script, authenticated with `server-upgrade/github-token`. Issues are created
only for failures. Each comment carries a hidden marker,
`<!-- server-upgrade host=<host> sha=<sha> status=failed|recovered -->`, and public text
with host, stage, whether it rolled back, and the hint `journalctl -u nixos-upgrade -b`.
No logs.

On failure:

1. List open issues labeled `server-upgrade`. If one is titled
   `Server upgrade failed: <sha7>`, comment on it.
2. Otherwise create it (label `server-upgrade`), with this host's report as the first
   comment. Then list again: if an older open issue for the same SHA exists (another host
   created one in the same minute), comment this host's report there and close the new
   issue as a duplicate of it.
3. Close every open `server-upgrade` issue for an older SHA as "superseded by #N".

The result is at most one open issue per upgrade cycle (target SHA), even when all four
servers fail.

On recovery:

1. If no open `server-upgrade` issue has a `failed` marker for this host, do nothing on
   GitHub. Recovery never creates an issue.
2. Otherwise post a `recovered` comment on that issue. Then read each host's latest marker
   in it, and close the issue if none says `failed`.

Delivery: the failure handler, the post-switch hook and the boot-time unit only write
messages to `/var/lib/server-upgrade/outbox/`. `server-upgrade-notify.service` sends them to
ntfy and runs the report script, with `Restart=on-failure`, `RestartSec=5min`, and a start
at boot. A message is removed once both channels accepted it, so a network that is down
during a rollback reboot only delays delivery.

## Secrets

Every server already has a sops file (`secrets/<host>.yaml`) and uses it: WireGuard keys on
all four (`modules/nixos/server/wireguard.nix`), plus CouchDB and restic on taragarmr. This
design adds two secrets, each declared only when its section exists (`hasSection`), the same
way `modules/nixos/common/sops.nix` gates its declarations:

| Secret | Files | Content |
|---|---|---|
| `server-upgrade/github-token` | the four server files | Fine-grained PAT, repository `LeeKrane/nixos-dotfiles` only, permission Issues: read and write. |
| `server-upgrade/ntfy-publish-token` | the four server files | Token of ntfy user `upgrade-publisher` (write-only on `server-upgrades`), created on taragarmr after ntfy is deployed. |
| `server-upgrade/ntfy-read-token` | the three desktop files (tariognatha, tarmantria, taractias) | Token of ntfy user `krane` (read-only on `server-upgrades`), created on taragarmr after ntfy is deployed. The phone's ntfy app uses the same user. |

How decryption works (`.sops.yaml`):

- Each server decrypts with an age key derived from its own
  `/etc/ssh/ssh_host_ed25519_key` (`sops.age.sshKeyPaths`). Those host keys were generated
  before install and are stored encrypted in the password manager.
- Every server file is also encrypted to the admin keys of tariognatha and tarmantria, each
  in `~/.config/sops/age/keys.txt` on that desktop.
- Desktop files are encrypted to that desktop's own admin key and host key.

What to back up so the secrets survive a redeploy:

1. The admin age keys, `~/.config/sops/age/keys.txt` on tariognatha and tarmantria. They
   are the root of trust: either one can decrypt every server file and re-key it with
   `sops updatekeys`. Losing both means every server secret has to be recreated.
2. Each server's SSH host key pair (`ssh_host_ed25519_key` and `.pub`), stored encrypted in
   the password manager. This is a convenience: a redeploy injects it again
   (`nixos-anywhere --extra-files` for taragarmr, copied onto the SD image for the Pis), so
   the host's age recipient is unchanged and its file decrypts on first boot. Losing it
   means generating a new key, replacing that host's recipient in `.sops.yaml`, and running
   `sops updatekeys secrets/<host>.yaml` with an admin key.
3. The PAT and the ntfy tokens need no separate backup: they are stored encrypted in the
   repo. A lost or leaked PAT is replaced by creating a new one and editing the files.

Keep the backups offline (password manager or encrypted USB), never in the repo.

## Error handling

| Case | Behavior |
|---|---|
| Gate not passed | `deploy` does not move; servers do nothing. |
| `git ls-remote` fails | `ExecCondition` skips the run; the next hourly run retries. No notification. |
| Build fails | Nothing changed. `failed-sha` set, failure message (stage `build`). |
| Activation fails | Rollback, `failed-sha` set, failure message (stage `activation`). |
| Health check fails after switch | Rollback, `failed-sha` set, failure message (stage `health`). |
| Health check fails after reboot | Rollback and one reboot, failure message (stage `boot-health`). |
| Rollback reboot also unhealthy | No further reboot; failure message says so. |
| ntfy or GitHub unreachable | Message stays in the outbox; retried every 5 minutes and at boot. |
| Several servers fail on one SHA | One issue, one comment per host. |
| Newer SHA arrives while an issue is open | The old issue closes as superseded when a host fails on the new SHA, or through recovery comments otherwise. |

## Testing

Script tests, in the pattern of `scripts/tests/flake-update-notify-test.sh` (commands stubbed
on `PATH`), run by `check.yml` next to that test. shellcheck already covers
`scripts/*.sh` and `scripts/tests/*.sh`.

`scripts/tests/server-upgrade-report-test.sh`, with `curl` stubbed as a fake GitHub API that
serves JSON fixtures and records requests:

- failure with no open issue creates one;
- failure with an open issue for the same SHA only comments;
- race: a newer duplicate closes itself and comments on the older issue;
- an issue for an older SHA is closed as superseded;
- recovery with no open issue for this host makes no GitHub request;
- recovery while another host still fails leaves the issue open;
- the last recovery closes it.

`scripts/tests/server-upgrade-hooks-test.sh`, with `git`, `nixos-rebuild`, `nixos-version`,
`systemctl` and `readlink` stubbed:

- `ExecCondition` skips a failed SHA;
- it skips when already deployed with no reboot pending;
- it runs when a reboot is pending;
- the failure handler rolls back only when `/run/current-system` changed;
- the boot-time unit reboots at most once;
- outbox entries stay until both channels accept them.

Eval checks, in `checks.server-eval` and `checks.pi-eval`:

- every server has `system.autoUpgrade.enable` with `github:LeeKrane/nixos-dotfiles/deploy#<host>`;
- reboot windows are 02–03, 03–04, 04–05, 05–06, distinct, taragarmr last;
- `healthChecks` is non-empty and `OnFailure` is wired;
- `services.ntfy-sh` is enabled only on taragarmr and bound to its WireGuard address;
- no desktop has `system.autoUpgrade` enabled.

CI verification:

1. Spike: `nix build --dry-run` of a Pi toplevel `.drv` on x86. Decides x86-only vs the
   `ubuntu-24.04-arm` leg.
2. Manual `workflow_dispatch` of update.yml: the PR body shows Pi rows in both summaries.
3. First push to `main` after the change: `deploy` appears at that SHA.

## Rollout

Order matters: the ntfy tokens exist only after ntfy runs on taragarmr, and the notifier
tolerates a missing token section (it is gated on `hasSection`).

1. Create the fine-grained PAT and add `server-upgrade/github-token` to the four server
   files (`sops secrets/<host>.yaml` on tariognatha or tarmantria).
2. `just switch taragarmr` to bring up ntfy. On taragarmr, create the users
   `upgrade-publisher` (write-only on `server-upgrades`) and `krane` (read-only), and
   generate a token for each. Add the publisher token as `server-upgrade/ntfy-publish-token`
   to the four server files, and the read token as `server-upgrade/ntfy-read-token` to the
   three desktop files.
3. Switch every server once (`just switch` on taragarmr, `nixos-rebuild --target-host` for
   the Pis), since auto-upgrade is not running yet, and switch the desktops for the
   subscriber. Check `systemctl list-timers nixos-upgrade.timer` on each server.
4. Subscribe the phone's ntfy app to `server-upgrades` through the WireGuard address.
5. Failure drill on tarronax: temporarily set its `healthChecks` to `[ "false" ]`, switch, run
   `systemctl start nixos-upgrade`. Expect a rollback, one ntfy push and exactly one issue.
   Revert, and expect a recovery push, a `recovered` comment and the issue closing.

## Related

- `docs/superpowers/specs/2026-09-30-ci-pipelines-design.md`
- `docs/superpowers/specs/2026-10-06-flake-update-notify-design.md`
- `secrets/README.md`
