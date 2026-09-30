# GitHub Actions CI for the dotfiles flake

This repo has no CI. Every check lives in `scripts/docker-check.sh` and runs only
when invoked by hand. This spec adds two GitHub Actions workflows:

- a **gate** that evaluates and lints the flake on every push to `main` and on
  every pull request, and
- a weekly **update** job that bumps `flake.lock` and the claude-code manifest,
  runs the gate against the result, and opens a pull request.

## Goals

- Catch evaluation, formatting and lint errors before `just switch` reaches a
  host.
- Detect upstream drift (`nixpkgs`, `illogical-flake`, `dots-hyprland` and the
  `patches/ii/` series applied on top of them) within a week, without manual
  `just update` runs.
- Stay lightweight: no full system builds, no binary cache, short feedback.

## Non-goals

- Real `toplevel` builds. Quickshell compiles from source and tariognatha pulls
  CUDA; both exceed a free runner's disk and time budget without a binary
  cache. Build-time failures stay caught locally by `just switch` or
  `just docker-build`.
- A binary cache (Cachix, Attic), VM boot tests, per-input update PRs, and
  notifications beyond GitHub's defaults.
- Evaluating `tariognatha-vm`.

## Background

Facts the design relies on:

- `lib/mk-host.nix` patches `illogical-flake` and `dots-hyprland` (with the
  `patches/ii/` series) through `applyPatches` and imports the result
  (import-from-derivation). Evaluating a host therefore applies every patch, so
  a patch that no longer applies fails evaluation. Eval-only CI covers patch
  drift.
- `checks.x86_64-linux` holds `lua-syntax` (cheap, and it also fails if
  `flake.nix`'s `hosts` list disagrees with `hosts/`), `nvim` and
  `nvim-specs` (build the NixVim package, heavier).
- sops secrets stay encrypted in the repo. Evaluation never decrypts them, so
  no CI job needs a secret.
- A pull request opened with `GITHUB_TOKEN` does not trigger other workflows.
  The design runs the gate inside the update workflow instead of relying on a
  `pull_request` trigger, which avoids a personal access token or GitHub App.

## Design

### Job layout: one job per concern, in parallel

Every gate job starts at the same time on its own runner. Wall-clock time is
about the slowest job, and a failing host shows up as its own red job. The
cost is the setup (checkout, Nix install) paid once per job. The cheap lint
steps share one job to limit that overhead.

### `.github/workflows/check.yml` (the gate)

Triggers:

- `push` to `main`
- `pull_request`
- `workflow_call` with two inputs:
  - `ref` (string, default empty, meaning the triggering ref): the ref to check
    out.
  - `force-nvim` (boolean, default `false`): run the `nvim` job regardless of
    changed paths.

`push` and `pull_request` use `paths-ignore: ['**.md', 'docs/**', 'LICENSE']`.

`concurrency: { group: check-${{ inputs.ref || github.ref }}, cancel-in-progress: true }`.
Under `workflow_call`, `github.ref` is the caller's ref (`main`), so the group
keys on `inputs.ref` first; otherwise a called gate on `ci/flake-update` would
cancel, or be cancelled by, a push run on `main`.

Top-level `permissions: contents: read`. No job reads a secret.

Shared setup in every job:

1. `actions/checkout`, with `ref: ${{ inputs.ref }}` (empty falls back to the
   triggering ref).
2. `cachix/install-nix-action` (flakes on, `cache.nixos.org` configured).

No Nix store cache in the first version: for eval jobs, restoring a GitHub
Actions cache costs about as much as fetching the flake inputs fresh. Add
`nix-community/cache-nix-action` later only if measured runs show input
fetching dominates.

All third-party actions are pinned by commit SHA, with the tag in a trailing
comment.

Jobs:

| Job | Steps |
|---|---|
| `lint` | `nix fmt -- .` then `git diff --exit-code`; `nix run nixpkgs#statix -- check .`; `nix run nixpkgs#deadnix -- --fail .`; `nix shell nixpkgs#shellcheck -c shellcheck -x -S style install.sh scripts/*.sh` |
| `eval` | matrix `host: [tariognatha, tarmantria, taractias]`, `fail-fast: false`; `nix eval --raw .#nixosConfigurations.${{ matrix.host }}.config.system.build.toplevel.drvPath` |
| `flake-check` | `nix flake check --no-build`; `nix build .#checks.x86_64-linux.lua-syntax` |
| `nvim` | conditional, see below; `nix build .#checks.x86_64-linux.nvim .#checks.x86_64-linux.nvim-specs` |

CI's `lint` fails on findings, unlike the report-only `just lint`. Before the
workflow lands, the tree must pass statix, deadnix and shellcheck cleanly:
fix each finding, or scope it out with an inline suppression that states why.

The eval matrix is hardcoded in YAML rather than discovered from
`nixosConfigurations`, because discovery needs an extra job on every run.
Hosts are added rarely, and `lua-syntax` already fails loudly when `flake.nix`
and `hosts/` disagree. Adding a host means adding it to the matrix too.

#### `nvim` path gate

The `nvim` job always starts. Its first step after checkout is
`dorny/paths-filter` with the filter
`modules/nixvim/**`, `flake.nix`, `flake.lock`, `overlays/**`.

- On a match, or when `inputs.force-nvim` is true, the build step runs.
- Otherwise the build step is skipped and the job reports success, so a
  required status check never waits on a job that did not run.

Nix is installed only when the build step will run, so a skipped `nvim` job
costs a few seconds.

### `.github/workflows/update.yml` (drift detector)

Triggers: `schedule` weekly (Monday, an off-minute early UTC, e.g. `17 4 * * 1`)
and `workflow_dispatch`.

`concurrency: { group: update, cancel-in-progress: false }`, so a manual run
queues behind a scheduled one instead of racing it on `ci/flake-update`.

Three jobs in sequence:

1. **`update`** (`permissions: contents: write`)
   - Check out `main`, install Nix.
   - Run `nix flake update 2>&1 | tee update.log`, then
     `scripts/update-claude-code.sh`. The runner image provides the
     `python3` and `curl` the script needs.
   - If `git status --porcelain` is empty, set output `changed=false` and stop.
   - Otherwise commit as `github-actions[bot]` with the subject
     `Update flake inputs and claude-code` (subject only, no body), and
     force-push to `ci/flake-update`. Each run replaces the previous week's
     branch.
   - Set output `changed=true`, and a `summary` output holding the
     `Updated input '...'` lines from `update.log` plus the claude-code
     `old -> new` line.
2. **`check`** (`needs: update`, `if: needs.update.outputs.changed == 'true'`)
   - `uses: ./.github/workflows/check.yml` with `ref: ci/flake-update` and
     `force-nvim: true`.
3. **`pr`** (`needs: [update, check]`,
   `if: always() && needs.update.outputs.changed == 'true'`,
   `permissions: pull-requests: write`)
   - With `gh`, create the pull request from `ci/flake-update` into `main`, or
     edit the open one.
   - Title: `Update flake inputs`, prefixed `[gate failing] ` when
     `needs.check.result != 'success'`.
   - Body: the `summary` output, the gate result, and a link to the workflow
     run.
   - The pull request opens even when the gate fails, so drift is visible
     instead of silent.

### `.github/dependabot.yml`

One entry: ecosystem `github-actions`, directory `/`, interval `monthly`, all
updates grouped into a single pull request. Keeps the SHA-pinned actions
current. Dependabot pull requests trigger `check.yml` normally.

## Error handling

- Any failing step fails its job; GitHub's default notification (email, web)
  reports it. No bots or chat integrations.
- `fail-fast: false` on the eval matrix, so one broken host does not cancel the
  others.
- The update workflow reports gate failure in the pull request title and body
  rather than failing silently.

## Known limits (accepted)

- **Eval only.** A patch that applies but fails to compile, or a wrong hash in
  `pkgs/`, passes CI. Before merging an update pull request, run
  `gh pr checkout <n> && just switch <host>` on one machine.
- **Update pull requests show no checks.** They are opened with `GITHUB_TOKEN`,
  so GitHub does not run `check.yml` on them. The gate result is in the body.
  Merging runs `check.yml` on `main` through the `push` trigger.
- **Scheduled workflows auto-disable** after 60 days without repository
  activity; GitHub emails a warning first.

## One-time setup (manual, outside the repo)

- Settings, Actions, General: enable "Allow GitHub Actions to create and
  approve pull requests" (needed by the `pr` job).

## Testing

- Validate both workflow files with `actionlint` locally before committing.
- Push the branch and open a pull request: all gate jobs run. The branch
  touches none of the `nvim` filter paths, so confirm `nvim` skips its build
  and still reports success.
- Run `update.yml` once with `workflow_dispatch` from the branch: confirm the
  `ci/flake-update` branch, the reused gate run and the pull request body.
- Deliberately break one host (for example a typo in `hosts/taractias/`) on a
  throwaway commit and confirm only `eval (taractias)` fails.

## Files

- `.github/workflows/check.yml` (new)
- `.github/workflows/update.yml` (new)
- `.github/dependabot.yml` (new)
- Nix and shell sources touched only as needed to pass `lint` cleanly.
- `README.md`: GitHub-native status badges for `check.yml` (filtered to
  `branch=main`) and `update.yml` directly under the title, and one line under
  Quickstart pointing to the CI workflows.
