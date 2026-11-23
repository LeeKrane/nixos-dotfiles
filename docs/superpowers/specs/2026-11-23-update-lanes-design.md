# Update lanes: one weekly PR per host role

The weekly `update` workflow (`.github/workflows/update.yml`) runs `nix flake update` on
every input and opens one pull request from `ci/flake-update`. Since the server auto-upgrade
(`docs/superpowers/specs/2026-11-23-server-auto-upgrade-design.md`), merging that PR deploys
to all four servers within about an hour: `check.yml` passes on `main`, `promote.yml` moves
`deploy`, and every server's hourly `system.autoUpgrade` switches to it.

Servers and desktops already run different package sets. `lib/mk-host.nix` gives
`role = "server"` hosts `nixpkgs-stable` (which follows `nixos-raspberrypi/nixpkgs`, a
nixos-26.05 pin), `home-manager-stable` and `nixvim-stable`. Desktops use nixos-unstable.
The single PR still bundles both bumps under one merge decision: a stable point release for
the servers and an unstable bump for the desktops.

This spec splits the weekly update into two lanes, each with its own branch and PR, from
the same workflow. Merging the desktop PR then never changes server packages (apart from
the one accepted leak below), and upgrading the servers is a merge decision of its own.

It supersedes the single-PR parts of `docs/superpowers/specs/2026-09-30-ci-pipelines-design.md`
and `docs/superpowers/specs/2026-10-06-flake-update-notify-design.md`. Those documents
stay unchanged as history.

## Goals

- Two PRs per weekly run, one per lane: `ci/flake-update-servers` and
  `ci/flake-update-desktops`.
- Each PR reports only on the hosts whose system closure it changes, with host lists
  collapsed to `all`, `servers` or `desktops` where they cover a whole group.
- When one lane PR merges and the other lane's PR then conflicts, it regenerates
  automatically. No manual step, and no second full run in a normal week.
- The desktop notifier alerts on both PRs and says which lane each one is.

## Non-goals

- Separate flakes, lock files or workflows per role. Shared inputs would drift, and one
  owner cannot tend two locks.
- Gating or staging `deploy` (canary hosts, soak times, per-host refs). `promote.yml`, the
  upgrade hooks and `system.configurationRevision = self.rev` stay as they are. Removing
  `self.rev` would break the hooks' "already on this SHA" and "already failed" checks
  (`scripts/server-upgrade-hooks.sh`, `cmd_condition`).
- A different cadence per lane. Both lanes run every Monday at 04:17 UTC.

## Decision record

A council review on 2026-11-23 compared four options: (a) keep one PR; (b) two PRs from
one workflow; (c) gated or staged promotion; (d) separate pipelines or flakes. It chose
(b). The rejected options and why:

- (c) needs the `self.rev` change above, or per-host deploy refs. A Raspberry Pi canary
  also says little about taragarmr (x86_64, WireGuard hub, ntfy host).
- (d) duplicates the shared inputs and lets the less-watched lock go stale.

Commits that change only desktop configuration still reach the servers through
`self.rev`. Each one causes a revision-only activation with no service changes, which also
exercises the rollback path. This is accepted.

## Lanes

`scripts/update-lanes.nix` defines the lanes in one place.

- **servers**: `nixos-raspberrypi` (which moves `nixpkgs-stable` through its `follows`),
  `home-manager-stable` and `nixvim-stable`. Also the inputs both roles use: `sops-nix`,
  `disko` and `nix-index-database`. Servers are the stricter audience, so anything that can
  reach them rides the server PR. Only this lane runs `scripts/update-claude-code.sh`,
  because `pkgs/claude-code` is installed on servers too.
- **desktops**: every other updatable root input of `flake.lock`, computed rather than
  listed. Root inputs that only `follows` another input (`nixpkgs-stable`) are in neither
  lane: they cannot be updated on their own and move with the input they follow. Today
  that is `nixpkgs`, `home-manager`, `nixvim`, `dots-hyprland`, `illogical-flake`,
  `quickshell`, `zen-browser` and `nixos-hardware`. A new input lands here by default. If
  it actually affects the servers, the changed-host report shows the servers in the desktop
  PR, so the misplacement is visible.

The file evaluates to `{ servers = [ ... ]; desktops = [ ... ]; }`, given the root input
names from `flake.lock`. It fails evaluation when a server-lane name is not a root input,
so a renamed input cannot drop out of both lanes silently.

### Accepted leak: codegraph

`modules/home/server/default.nix` installs `unstable.codegraph`, taken from
`nixpkgs-unstable`, which is the desktop `nixpkgs` input. A desktop-lane `nixpkgs` bump
therefore changes all four server closures. Only the user profile changes (codegraph and
its unstable runtime dependencies), not system services. This is accepted. The
desktop PR reports it through the changed-host list (see "PR body").

### Merge behaviour, verified

On 2026-11-23, both lanes were updated in a scratch clone of `main`. The server lane
changed 24 lines of `flake.lock` and the desktop lane 25. `git merge` of the two branches
was clean, `nix flake metadata --no-update-lock-file` accepted the result, and the merged
lock was byte-identical to a full `nix flake update`.

`flake.lock` stores each node as its own JSON block, so the lanes normally merge on their
own. A textual conflict needs edits on adjacent lines, or an input that adds or drops a
transitive input and so renumbers the `nixpkgs_N` node names. Both are rare. "Refresh on
conflict" below covers them.

## Workflow

Today's jobs (`update`, `check`, `security`, `pr`) move to a reusable workflow,
`.github/workflows/update-lane.yml`, which takes a `lane` input. `update.yml` keeps the
triggers and the concurrency group. It runs a `select` job, then one matrix job over the
selected lanes that calls `update-lane.yml` per lane. Matrix legs of a plain job cannot pass
per-leg outputs (the pushed SHA, the changed hosts) to later jobs reliably, but a called
workflow keeps each lane's job outputs to itself. `check` calls `check.yml` once per lane with
that lane's pushed SHA, and the full eval matrix stays unchanged. Artifact names carry the
lane (`update-summary-servers`, ...), because both lanes share one workflow run.

### Triggers and lane selection

| Trigger | Lanes |
|---|---|
| `schedule` (`17 4 * * 1`) | both |
| `workflow_dispatch`, input `lane`: `both` (default), `servers` or `desktops` | as chosen |
| `push` to `main`, paths `flake.lock` or `pkgs/claude-code/**` | only lanes whose open PR is `CONFLICTING` |

`select` outputs a JSON list of lanes. An empty list skips every later job, and the run
ends green.

### Refresh on conflict

On the push trigger, `select` checks each lane that has an open same-repo PR from
`ci/flake-update-<lane>`, using `gh pr view --json mergeable`.

- GitHub computes `mergeable` lazily, so `select` polls every 10 s for up to 2 minutes
  while the answer is `UNKNOWN`. If it is still `UNKNOWN` at the deadline, the lane is not
  selected and the job logs a warning. Next Monday's run, or a manual dispatch, covers it.
- `CONFLICTING`: the lane is selected and regenerates from the new `main`.
- `MERGEABLE`, or no open PR: the lane is not selected.

A clean week costs one `select` run of about 10 s. The merged lane needs no extra check:
`check.yml` runs on `main` before `promote.yml` moves `deploy`.

The `select` logic lives in `scripts/update-select-lanes.sh`, so it can be tested with a
stub `gh`.

### Concurrency

The single `update` concurrency group stays (`cancel-in-progress: false`). A conflict
refresh queues behind a running weekly run instead of racing it on the lane branches.

### update job (per lane)

1. Save the old `flake.lock`.
2. Run `nix flake update <lane inputs>`. In the server lane only, also run
   `scripts/update-claude-code.sh`. Both log to `update.log`.
3. If neither `flake.lock` nor `pkgs/claude-code` changed, the leg ends with "Nothing to
   update", and the lane's existing PR stays untouched.
4. Evaluate every host's toplevel `drvPath` before and after the update. The `security`
   job does this today; it moves here. The hosts whose `drvPath` changed become the
   leg's `hosts` output. If no host changed, the PR is still opened, with a note that no
   host closure changed.
5. Evaluate package versions before and after, for the changed hosts only
   (`scripts/update-versions.nix`, as today).
6. Render the summary (`scripts/update-summary.sh`).
7. Commit and force-push to `ci/flake-update-<lane>-staging`. The commit message is
   `Update server inputs and claude-code` or `Update desktop inputs`.

### security job (per lane)

As today, but only for the leg's changed hosts. It still evaluates the before and after
`drvPath`s itself, because a fresh runner does not have the `update` job's derivations.

### pr job (per lane)

As today: build the body, cap its size, move `ci/flake-update-<lane>` to the exact staging
SHA, then create or edit the lane's PR (same-repo filter kept). Titles:
`Update server inputs` and `Update desktop inputs`, each with the existing
`[gate failing] ` prefix when the gate fails.

## PR body

- **Server PR**, first line: "Merging deploys to every server within about an hour
  (promote.yml moves deploy)."
- **Desktop PR**, first line when the changed hosts include any server: "Also changes:
  <collapsed server list> (user profile)."
- **Gate line, version table and security section**: as today, limited to the changed
  hosts.
- **Before-merge commands**: these name the lane branch:
  `git fetch origin ci/flake-update-<lane> && git switch -C ci/flake-update-<lane> FETCH_HEAD`,
  then `just switch <host>`. The server PR suggests taragarmr.

### Host list collapsing

Every host list printed in a PR body is collapsed against the flake's full host set, using
the roles in `lib.hostMeta`. This covers the version table's Hosts column, the security
section's host lists and the "Also changes" line.

1. If the list contains every host of the flake: `all`.
2. Otherwise, every complete role group becomes its role name: `servers` (all
   `role = "server"` hosts) and `desktops` (all `role = "desktop"` hosts).
3. Hosts left over are listed by name after the groups, in the existing order.

"All" always means every host of the flake, not every host in the lane. Examples:
- All seven hosts give `all`.
- The four servers give `servers`.
- Everything except taractias gives `servers, tariognatha, tarmantria`.
- Hosts added later join their role group automatically through `hostMeta`.

The collapsing is one jq function shared by `scripts/update-summary.sh` and
`scripts/security-summary.sh`. Both get a `HOST_ROLES` JSON (`{host: role}`), which the
workflow passes from `lib.hostMeta`.

## Desktop notifier

`modules/home/desktop/flake-update-notify.nix` defines one service and timer per lane
(`flake-update-notify-servers`, `flake-update-notify-desktops`) instead of the single
`flake-update-notify` unit. Each unit sets `BRANCH=ci/flake-update-<lane>` and a `LABEL`
(`Server update` or `Desktop update`). One unit per lane keeps the script's retry and
"never show a popup twice" logic per lane, unchanged. The script
(`scripts/flake-update-notify.sh`) keys its state file by branch, so two lanes never share
dedupe state. The notification summary reads "<LABEL> ready (#N)", for example "Server
update ready (#12)", and clicking it opens that PR. Without `LABEL`, the summary stays
"Flake update ready (#N)".

## Migration

This runs once, after the implementation is on `main`:

1. Close the open `ci/flake-update` PR, with a comment pointing to the lane PRs.
2. Delete the `ci/flake-update` and `ci/flake-update-staging` branches.
3. Dispatch `update` with `lane=both` to open both lane PRs.

## Testing

Bash tests in `scripts/tests/`, run by `check.yml` like the existing ones:

- **Lanes**: the server list plus the computed desktop list equals the root inputs of
  `flake.lock`, with no overlap. Evaluation fails on an unknown server-lane name.
- **Host collapsing**: `all`, `servers`, `desktops`, `servers` plus individual desktops,
  individual hosts only, and the empty list.
- **Lane selection**: with a stub `gh`, cover the schedule and dispatch inputs, and on push:
  `CONFLICTING`, `MERGEABLE`, `UNKNOWN` resolving to `CONFLICTING` within the deadline,
  `UNKNOWN` until the deadline, no open PR, and a fork PR from a same-named branch
  (ignored).
- **Notifier**: two branches, separate state per branch, and lane-specific text.

After merging, a `lane=both` dispatch (the migration step) checks the real run. It should
produce two PRs whose bodies list only changed hosts, with collapsed names.
