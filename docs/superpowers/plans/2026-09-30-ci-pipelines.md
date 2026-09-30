# GitHub Actions CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a parallel eval/lint gate on push and pull request, plus a weekly job that updates flake inputs and claude-code, runs the gate, and opens a pull request.

**Architecture:** `check.yml` runs independent jobs in parallel (`lint`, one `eval` per host, `flake-check`, a path-gated `nvim`) and is also callable through `workflow_call`. `update.yml` bumps inputs on `ci/flake-update`, calls `check.yml` against that branch, then creates or edits one pull request with `gh`. Nothing builds a system toplevel.

**Tech Stack:** GitHub Actions, Nix flakes, `cachix/install-nix-action`, `dorny/paths-filter`, statix, deadnix, shellcheck, nixfmt, actionlint.

**Spec:** `docs/superpowers/specs/2026-09-30-ci-pipelines-design.md`

## Global Constraints

- Work only in the worktree `/home/krane/.dotfiles/.claude/worktrees/ci-pipelines`, branch `ci-pipelines`.
- Commit messages: subject line only, no body, no Claude/Anthropic attribution, no `Co-Authored-By`.
- Never push to a remote without the user's explicit approval (Task 5 asks first).
- Pin third-party actions by commit SHA with the tag as a trailing comment:
  - `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1`
  - `cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24 # v31.11.1`
  - `dorny/paths-filter@ceb8a2b8f2d89434be7ff52d3de7ec3738c5cc9d # v4.0.3`
- Lint tools come from the flake's locked nixpkgs: `nix shell --inputs-from . nixpkgs#<tool>`, never bare `nixpkgs#<tool>` (that resolves the registry's unpinned nixpkgs).
- Eval host matrix: exactly `tariognatha`, `tarmantria`, `taractias`. Not `tariognatha-vm`.
- `paths-ignore` for push and pull_request: `'**.md'`, `'docs/**'`, `'LICENSE'`.
- `nvim` filter paths: `modules/nixvim/**`, `flake.nix`, `flake.lock`, `overlays/**`.
- Update branch: `ci/flake-update`. Update commit subject: `Update flake inputs and claude-code`. Schedule: `17 4 * * 1`.
- No job reads a secret other than the automatic `GITHUB_TOKEN`.

## Review Focus

- A week with no upstream change: `update` must stop cleanly, with no push, no gate run and no pull request, and the run must show success, not failure.
- `nvim` under `workflow_call` from a `schedule` or `workflow_dispatch` event: `dorny/paths-filter` does not support those events, so the filter step must be skipped when `force-nvim` is true, not merely ignored.
- The gate called from `update.yml`: its concurrency group must key on `inputs.ref`, or it cancels (or is cancelled by) the `push` run on `main`.
- An open update pull request whose gate recovers the next week: `gh pr edit` must reset the title, dropping the `[gate failing] ` prefix.
- A docs-only push (`docs/**`, `*.md`): no gate run at all.

Each line is checked in Task 5's live verification, the only place workflows actually execute. Tasks 2 and 3 pin the static half with `actionlint` and a `grep` for the exact expression.

---

## File structure

- Create `.github/workflows/check.yml`: the gate; one job per concern.
- Create `.github/workflows/update.yml`: weekly drift detector; three sequential jobs.
- Create `.github/dependabot.yml`: monthly grouped bumps of the pinned actions.
- Create `statix.toml`: repo-wide statix config (disables two style lints, see Task 1).
- Modify `scripts/docker-check.sh`: `lint` mode uses the same deadnix flags as CI; SC2016 suppressions.
- Modify `scripts/proton-drive-rclone-mount.sh:278`: drop an unused variable.
- Modify `lib/mk-host.nix:89`: rename an unused lambda argument.
- Modify `modules/nixvim/keymaps.nix:26`: `key = key;` becomes `inherit key;`.
- Modify `README.md`: `check` and `update` status badges under the title, one line about CI under Quickstart.
- Formatting-only changes from `nix fmt` in `hosts/*/hardware-configuration.nix`, `hosts/tariognatha/display.nix`, `lib/mk-host.nix`, `modules/home/steam.nix`.

---

### Task 1: Make the tree pass CI's lint gate

The planning session already ran `nix fmt -- .` in the worktree, so the six formatting-only files are modified but not committed. Check with `git status` first. Baseline findings, measured on the current tree:

- **statix**: about 40 `W20 repeated_keys` (dotted keys such as `programs.x = …; programs.y = …;`, idiomatic NixOS module style), 14 `W10 empty_pattern` (`{ ... }:` module headers, also idiomatic), and 1 `W3 manual_inherit` at `modules/nixvim/keymaps.nix:26`.
- **deadnix**: an unused `pkgs` in the three `hosts/*/hardware-configuration.nix`, which `install.sh` generates (see `install.sh:750`), plus an unused `n` at `lib/mk-host.nix:89`.
- **shellcheck**: 2× SC2016 in `scripts/docker-check.sh` (lines 86 and 121, intentional single-quoted in-container scripts) and 1× SC2034 at `scripts/proton-drive-rclone-mount.sh:278`.

Decision: disable `repeated_keys` and `empty_pattern` repo-wide rather than rewriting about 30 modules into nested sets. Both lints fight idiomatic NixOS style, and the rewrite is churn with no correctness value. Fix everything else.

**Files:**
- Create: `statix.toml`
- Modify: `modules/nixvim/keymaps.nix:26`, `lib/mk-host.nix:89`, `scripts/docker-check.sh:86,119-127`, `scripts/proton-drive-rclone-mount.sh:278`
- Commit: the pending `nix fmt` changes

**Interfaces:**
- Produces: these exact lint commands exit 0 from the repo root (Task 2's `lint` job runs them verbatim):
  - `nix fmt -- --check .`
  - `nix shell --inputs-from . nixpkgs#statix -c statix check .`
  - `nix shell --inputs-from . nixpkgs#deadnix -c deadnix --fail --exclude hosts/*/hardware-configuration.nix -- .`
  - `nix shell --inputs-from . nixpkgs#shellcheck -c shellcheck -x -S style install.sh scripts/*.sh`

- [ ] **Step 1: Confirm each lint fails today**

Run each of the four commands above from the worktree root.
Expected: `nix fmt -- --check .` passes (formatting already applied, not yet committed). statix, deadnix and shellcheck exit non-zero with the findings listed above.

- [ ] **Step 2: Commit the formatting**

```bash
git add hosts/taractias/hardware-configuration.nix hosts/tariognatha/hardware-configuration.nix hosts/tarmantria/hardware-configuration.nix hosts/tariognatha/display.nix lib/mk-host.nix modules/home/steam.nix
git commit -m "Format the tree with nixfmt"
```

If `git status` shows other modified files, run `git diff` on them. Include them only if the diff is formatting-only.

- [ ] **Step 3: Add `statix.toml` at the repo root**

```toml
# Both lints flag idiomatic NixOS module style: dotted keys repeated across a
# module (`programs.a = ...; programs.b = ...;`) and `{ ... }:` headers on
# modules that take no arguments. Rewriting ~30 modules would be churn.
disabled = [
  "repeated_keys",
  "empty_pattern",
]
```

- [ ] **Step 4: Fix the `manual_inherit` finding**

In `modules/nixvim/keymaps.nix`, inside `termWinMap`, replace:

```nix
    key = key;
```

with:

```nix
    inherit key;
```

- [ ] **Step 5: Run statix**

Run: `nix shell --inputs-from . nixpkgs#statix -c statix check .`
Expected: exit 0, no output.

- [ ] **Step 6: Fix the deadnix finding in `lib/mk-host.nix:89`**

Replace `(n: t: t == "directory")` with `(_n: t: t == "directory")`. Leave the rest of the line as it is.

- [ ] **Step 7: Run deadnix**

Run: `nix shell --inputs-from . nixpkgs#deadnix -c deadnix --fail --exclude hosts/*/hardware-configuration.nix -- .`
Expected: exit 0, no warnings. The generated `hardware-configuration.nix` files are excluded because `install.sh` rewrites them on every install.

- [ ] **Step 8: Mirror the CI deadnix flags in `just lint`**

In `scripts/docker-check.sh`, `lint)` case, replace:

```sh
            nix run nixpkgs#deadnix -- . || status=1
```

with:

```sh
            nix run nixpkgs#deadnix -- --exclude hosts/*/hardware-configuration.nix -- . || status=1
```

Local stays report-only: no `--fail`, and the `|| status=1` is kept.

- [ ] **Step 9: Suppress the intentional SC2016s**

In `scripts/docker-check.sh`, add a directive on the line directly above each `run_in_container '` in the `check)` and `lint)` cases:

```sh
        # shellcheck disable=SC2016 # expands inside the container's sh, not here
        run_in_container '
```

(`check)` already has a comment line above `run_in_container`. Put the directive between that comment and `run_in_container`.)

- [ ] **Step 10: Fix the SC2034 in `scripts/proton-drive-rclone-mount.sh:278`**

Only yad's exit code is read. Replace the start of the multi-line capture:

```sh
				yad_response=$(yad --center --title="$RCLONE_REMOTE Mount Failed" \
					--text="<b>$local_message</b>\n\n$local_detail\n\nWould you like to retry the mount?" \
					--button="Retry!gtk-refresh:0" \
					--button="Cancel!gtk-cancel:1" \
					--undecorated --width=450 --height=150)
```

with:

```sh
				yad --center --title="$RCLONE_REMOTE Mount Failed" \
					--text="<b>$local_message</b>\n\n$local_detail\n\nWould you like to retry the mount?" \
					--button="Retry!gtk-refresh:0" \
					--button="Cancel!gtk-cancel:1" \
					--undecorated --width=450 --height=150 >/dev/null
```

The next line, `yad_exit_code=$?`, still captures yad's exit status: a plain command sets `$?` the same way the command substitution did.

- [ ] **Step 11: Run shellcheck**

Run: `nix shell --inputs-from . nixpkgs#shellcheck -c shellcheck -x -S style install.sh scripts/*.sh`
Expected: exit 0, no output.

- [ ] **Step 12: Run all four lint commands, then an eval as a regression check**

Run the four Interface commands in order. Expected: all exit 0.
Then run: `nix eval --raw .#nixosConfigurations.tarmantria.config.system.build.toplevel.drvPath`
Expected: prints a `/nix/store/…-nixos-system-tarmantria-….drv` path, which shows the `mk-host.nix` edit still evaluates.

- [ ] **Step 13: Commit**

```bash
git add statix.toml modules/nixvim/keymaps.nix lib/mk-host.nix scripts/docker-check.sh scripts/proton-drive-rclone-mount.sh
git commit -m "Make the tree pass statix, deadnix and shellcheck for CI"
```

---

### Task 2: Gate workflow `check.yml`

**Files:**
- Create: `.github/workflows/check.yml`

**Interfaces:**
- Consumes: Task 1's four lint commands.
- Produces: a reusable workflow `./.github/workflows/check.yml` with `workflow_call` inputs `ref` (string, default `''`) and `force-nvim` (boolean, default `false`). Job ids: `lint`, `eval`, `flake-check`, `nvim`. Task 3 calls it and reads the calling job's `result`.

- [ ] **Step 1: Write the workflow**

```yaml
name: check

on:
  push:
    branches: [main]
    paths-ignore: ['**.md', 'docs/**', 'LICENSE']
  pull_request:
    paths-ignore: ['**.md', 'docs/**', 'LICENSE']
  workflow_call:
    inputs:
      ref:
        description: Ref to check out; empty means the triggering ref.
        type: string
        default: ''
      force-nvim:
        description: Build the nvim checks regardless of changed paths.
        type: boolean
        default: false

# Under workflow_call, github.ref is the caller's ref (main), so key on
# inputs.ref first; otherwise update.yml's gate would cancel, or be
# cancelled by, the push run on main.
concurrency:
  group: check-${{ inputs.ref || github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          ref: ${{ inputs.ref }}
      - uses: cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24 # v31.11.1
      - name: nixfmt
        run: nix fmt -- --check .
      - name: statix
        run: nix shell --inputs-from . nixpkgs#statix -c statix check .
      - name: deadnix
        run: nix shell --inputs-from . nixpkgs#deadnix -c deadnix --fail --exclude hosts/*/hardware-configuration.nix -- .
      - name: shellcheck
        run: nix shell --inputs-from . nixpkgs#shellcheck -c shellcheck -x -S style install.sh scripts/*.sh

  eval:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        host: [tariognatha, tarmantria, taractias]
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          ref: ${{ inputs.ref }}
      - uses: cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24 # v31.11.1
      # Evaluating a host applies every patch under patches/ (applyPatches
      # imported in lib/mk-host.nix), so upstream drift fails here.
      - name: eval ${{ matrix.host }}
        run: nix eval --raw .#nixosConfigurations.${{ matrix.host }}.config.system.build.toplevel.drvPath

  flake-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          ref: ${{ inputs.ref }}
      - uses: cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24 # v31.11.1
      - name: flake check
        run: nix flake check --no-build
      - name: lua-syntax
        run: nix build --no-link .#checks.x86_64-linux.lua-syntax

  nvim:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          ref: ${{ inputs.ref }}
      # paths-filter supports only push and pull_request events; a forced run
      # (update.yml, on schedule/workflow_dispatch) skips it entirely.
      - uses: dorny/paths-filter@ceb8a2b8f2d89434be7ff52d3de7ec3738c5cc9d # v4.0.3
        id: filter
        if: ${{ !inputs.force-nvim }}
        with:
          filters: |
            nvim:
              - 'modules/nixvim/**'
              - 'flake.nix'
              - 'flake.lock'
              - 'overlays/**'
      - uses: cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24 # v31.11.1
        if: ${{ inputs.force-nvim || steps.filter.outputs.nvim == 'true' }}
      - name: nvim checks
        if: ${{ inputs.force-nvim || steps.filter.outputs.nvim == 'true' }}
        run: nix build --no-link .#checks.x86_64-linux.nvim .#checks.x86_64-linux.nvim-specs
```

Note: the spec's `nix fmt -- .` plus `git diff --exit-code` is replaced by `nix fmt -- --check .`. Same result, one command, and it never modifies the checkout.

- [ ] **Step 2: Lint the workflow**

Run: `nix shell --inputs-from . nixpkgs#actionlint -c actionlint .github/workflows/check.yml`
Expected: exit 0, no output. If shellcheck-in-actionlint flags the `run:` lines, fix the flagged line rather than disabling the check.

- [ ] **Step 3: Pin the Review Focus expressions statically**

Run:
```bash
grep -n 'check-${{ inputs.ref || github.ref }}' .github/workflows/check.yml
grep -n "if: \${{ !inputs.force-nvim }}" .github/workflows/check.yml
grep -c "paths-ignore: \['\*\*.md', 'docs/\*\*', 'LICENSE'\]" .github/workflows/check.yml
```
Expected: one match, one match, and `2`.

- [ ] **Step 4: Run each job's commands locally**

From the worktree root, run the `lint` job's four commands, then
`nix eval --raw .#nixosConfigurations.tariognatha.config.system.build.toplevel.drvPath` (and the same for `tarmantria` and `taractias`), then `nix flake check --no-build` and `nix build --no-link .#checks.x86_64-linux.lua-syntax`.
Expected: all exit 0. This is the same sequence the runners execute.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/check.yml
git commit -m "Add a parallel eval and lint gate for pushes and pull requests"
```

---

### Task 3: Update workflow `update.yml`

**Files:**
- Create: `.github/workflows/update.yml`

**Interfaces:**
- Consumes: `./.github/workflows/check.yml` with inputs `ref`, `force-nvim` (Task 2); `scripts/update-claude-code.sh`, which prints `claude-code already at X` or `claude-code X -> Y`.
- Produces: branch `ci/flake-update` and one open pull request into `main`.

- [ ] **Step 1: Write the workflow**

```yaml
name: update

on:
  schedule:
    - cron: '17 4 * * 1'
  workflow_dispatch:

# A manual run queues behind a scheduled one instead of racing it on the branch.
concurrency:
  group: update
  cancel-in-progress: false

permissions: {}

jobs:
  update:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    outputs:
      changed: ${{ steps.commit.outputs.changed }}
      summary: ${{ steps.commit.outputs.summary }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          ref: main
      - uses: cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24 # v31.11.1
      - name: Update inputs and claude-code
        run: |
          set -o pipefail
          nix flake update 2>&1 | tee "$RUNNER_TEMP/update.log"
          scripts/update-claude-code.sh 2>&1 | tee -a "$RUNNER_TEMP/update.log"
      - name: Commit and push
        id: commit
        run: |
          if [ -z "$(git status --porcelain -- flake.lock pkgs/claude-code)" ]; then
            echo "Nothing to update."
            echo "changed=false" >> "$GITHUB_OUTPUT"
            exit 0
          fi
          git config user.name 'github-actions[bot]'
          git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
          git add flake.lock pkgs/claude-code
          git commit -m 'Update flake inputs and claude-code'
          git push --force origin HEAD:refs/heads/ci/flake-update
          {
            echo "changed=true"
            echo "summary<<SUMMARY_EOF"
            grep -A2 "Updated input" "$RUNNER_TEMP/update.log" || true
            grep -E '^claude-code .* -> ' "$RUNNER_TEMP/update.log" || true
            echo "SUMMARY_EOF"
          } >> "$GITHUB_OUTPUT"

  check:
    needs: update
    if: needs.update.outputs.changed == 'true'
    permissions:
      contents: read
    uses: ./.github/workflows/check.yml
    with:
      ref: ci/flake-update
      force-nvim: true

  pr:
    needs: [update, check]
    if: always() && needs.update.outputs.changed == 'true'
    runs-on: ubuntu-latest
    permissions:
      pull-requests: write
    steps:
      - name: Create or update the pull request
        env:
          GH_TOKEN: ${{ github.token }}
          GH_REPO: ${{ github.repository }}
          RESULT: ${{ needs.check.result }}
          SUMMARY: ${{ needs.update.outputs.summary }}
          RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
        run: |
          title='Update flake inputs'
          if [ "$RESULT" != success ]; then
            title="[gate failing] $title"
          fi
          body=$(printf '%s\n\n```\n%s\n```\n\n%s\n\n%s\n' \
            "Gate result: **$RESULT** ([run]($RUN_URL))" \
            "$SUMMARY" \
            'CI checks eval only. Before merging, run `gh pr checkout <n> && just switch <host>` on one machine.' \
            'Checks do not appear on this pull request: it is opened with GITHUB_TOKEN, which triggers no workflows. Merging runs the gate on main.')
          number=$(gh pr list --head ci/flake-update --base main --state open --json number --jq '.[0].number // empty')
          if [ -n "$number" ]; then
            gh pr edit "$number" --title "$title" --body "$body"
          else
            gh pr create --head ci/flake-update --base main --title "$title" --body "$body"
          fi
```

- [ ] **Step 2: Lint the workflow**

Run: `nix shell --inputs-from . nixpkgs#actionlint -c actionlint .github/workflows/update.yml .github/workflows/check.yml`
Expected: exit 0. actionlint also validates the `uses: ./.github/workflows/check.yml` call against the declared inputs, so a misspelled `force-nvim` fails here.

- [ ] **Step 3: Check the commit step's no-change path locally**

In a throwaway clone:

```bash
tmp=$(mktemp -d "$CLAUDE_JOB_DIR/tmp/upd.XXXX") && git clone -q . "$tmp" && cd "$tmp"
[ -z "$(git status --porcelain -- flake.lock pkgs/claude-code)" ] && echo "no-change path taken"
echo x >> flake.lock
[ -n "$(git status --porcelain -- flake.lock pkgs/claude-code)" ] && echo "change path taken"
```

Expected: `no-change path taken`, then `change path taken`. (`$CLAUDE_JOB_DIR/tmp` is the job's scratch space; use any temp dir outside the repo if it is unset.)

- [ ] **Step 4: Check the summary extraction against real output**

```bash
nix flake update --output-lock-file "$CLAUDE_JOB_DIR/tmp/probe.lock" 2>&1 | tee "$CLAUDE_JOB_DIR/tmp/update.log" >/dev/null
grep -A2 "Updated input" "$CLAUDE_JOB_DIR/tmp/update.log" | head -9
```

Expected: blocks of `• Updated input '<name>':` followed by the old and new `'github:…'` lines. If nix prints nothing (inputs already current), the grep prints nothing, and `|| true` in the workflow keeps that from failing. `--output-lock-file` keeps the repo's `flake.lock` untouched.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/update.yml
git commit -m "Add a weekly flake and claude-code update that gates and opens a pull request"
```

---

### Task 4: Dependabot and README

**Files:**
- Create: `.github/dependabot.yml`
- Modify: `README.md` (Quickstart section, after the `just check` paragraph)

- [ ] **Step 1: Write `.github/dependabot.yml`**

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: monthly
    groups:
      actions:
        patterns: ['*']
```

- [ ] **Step 2: Validate it parses**

Run: `nix shell --inputs-from . nixpkgs#yq-go -c yq '.updates[0].groups.actions.patterns[0]' .github/dependabot.yml`
Expected: `*`

- [ ] **Step 3: Add the README line**

In `README.md`, directly after the paragraph that starts with ``just check` evaluates the flake``, insert:

```markdown
CI runs the same eval and lint gate on every push to `main` and every pull request (`.github/workflows/check.yml`), and a weekly job opens a pull request with updated flake inputs and claude-code (`.github/workflows/update.yml`). Both are eval-only, not builds.
```

- [ ] **Step 4: Add CI status badges under the README title**

In `README.md`, insert between the `# nixos-dotfiles` line and the first paragraph, with one blank line on each side:

```markdown
[![check](https://github.com/LeeKrane/nixos-dotfiles/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/LeeKrane/nixos-dotfiles/actions/workflows/check.yml?query=branch%3Amain)
[![update](https://github.com/LeeKrane/nixos-dotfiles/actions/workflows/update.yml/badge.svg)](https://github.com/LeeKrane/nixos-dotfiles/actions/workflows/update.yml)
```

What each badge shows:
- `check`: the latest gate run on `main`. `?branch=main` keeps pull request runs from turning it red.
- `update`: the latest weekly run. It goes red when the update itself fails, or when the gate called against `ci/flake-update` fails, because a failed called workflow fails the caller's run. A week with nothing to update shows green.

GitHub serves these SVGs itself: no third-party badge service, no token. For a private repo they render only for viewers with access.

- [ ] **Step 5: Check the badge URLs**

Run: `grep -c 'actions/workflows/\(check\|update\)\.yml/badge\.svg' README.md`
Expected: `2`. The URLs start returning real status only after Task 5 pushes the workflows. Until then GitHub serves a "no status" badge; Task 5 Step 2 confirms they render.

- [ ] **Step 6: Commit**

```bash
git add .github/dependabot.yml README.md
git commit -m "Add grouped Dependabot bumps for actions, CI badges and a CI note to the README"
```

---

### Task 5: Live verification on GitHub (needs the user)

Workflows only really run on GitHub. This task needs a push, so **stop and ask the user for explicit approval before Step 1.** The user must also enable Settings, Actions, General, "Allow GitHub Actions to create and approve pull requests", before Step 4.

`update.yml` only becomes dispatchable once it exists on the default branch. `workflow_dispatch` from a non-default branch works only if the file also exists on `main`. So Steps 1–3 verify the gate from the branch, and Steps 4–5 run after the user merges into `main`.

- [ ] **Step 1: Push the branch (after approval)**

```bash
git push -u origin ci-pipelines
```

- [ ] **Step 2: Open a pull request and watch the gate**

`gh` is not installed on this host. Run it with `nix shell nixpkgs#gh -c gh …`, or let the user open the pull request in the browser.
Expected on the pull request: `lint`, `eval (tariognatha)`, `eval (tarmantria)`, `eval (taractias)`, `flake-check` and `nvim` all green. `nvim` builds, because `flake.nix`/`overlays` are untouched but `modules/nixvim/keymaps.nix` changed in Task 1. Note each job's duration for the report. Open the branch's `README.md` on GitHub and confirm both badges render (`check` stays "no status" until the first run on `main`).

- [ ] **Step 3: Prove host isolation and the skip path**

On the same branch, push a throwaway commit that breaks one host, e.g. `echo 'broken' >> hosts/taractias/display.nix`.
Expected: only `eval (taractias)` fails, and `nvim` reports success with its build step skipped (no filter path touched).
Then push a docs-only commit (edit `docs/VERIFY.md`). Expected: no `check` run starts.
Revert both with `git revert --no-edit HEAD HEAD~1` (the docs commit is on top) and push.

- [ ] **Step 4: After the user merges into `main`, dispatch the update**

Run `gh workflow run update.yml`, then `gh run watch`.
Expected: either (a) `update` reports "Nothing to update." and `check`/`pr` are skipped, with the run green, or (b) branch `ci/flake-update` exists, the called `check` jobs run against it, and a pull request titled `Update flake inputs` (or `[gate failing] Update flake inputs`) appears. Its body holds the gate result, the run link and the `Updated input` lines.

- [ ] **Step 5: Confirm no collision with `main`**

While Step 4's run is in its `check` stage, confirm in the Actions tab that no `check` run on `main` was cancelled. Their concurrency groups are `check-ci/flake-update` and `check-refs/heads/main`.

Report durations, results and anything unexpected back to the user. No commit in this task unless a fix is needed. A fix goes through Tasks 2/3 again.
