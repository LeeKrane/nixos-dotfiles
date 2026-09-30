# Handoff: implement plan 5 (ii settings app) on branch `ii-settings`

## Goal for the next session
Implement plan 5 end to end, without user input wherever possible:
- Plan: `docs/superpowers/plans/2026-09-27-ii-settings.md`
- Spec: `docs/superpowers/specs/2026-09-27-ii-settings-design.md`
- Branch `ii-settings`, worktree `/home/krane/.dotfiles/.claude/worktrees/ii-settings`. Its base is `main` `e7e2660`, plus one commit, `638ee32`, which brought the plan and spec up to date with `main`. Read the plan and spec from that worktree; `main`'s copy is older.

**Loop the user asked for, for each task:**
1. Implement the task.
2. Run `/code-review` at **high** on that task's changes only (scope it to the task's commit range).
3. Fix the findings, then run a scoped re-review.
4. Repeat until the review is clean.

**Steps that need the user:** skip them and keep going. At the end of the session, give one list of everything not done because it needs user input. Typical cases:
- `sudo nixos-rebuild switch`
- checks on screen: GUI clicks, monitor plug/unplug
- the privacy review and commit of `config.json`

The user will test and answer everything at the end. After that, finish the remaining steps and run the review loops again.

## State at handoff
- `main` = `origin/main` = `e7e2660` (PR #2 merged). The only extra local branch is `ii-settings`, with no other worktrees.
- Sub-projects 1, 2 and 4 have landed. Sub-project 3 (the dock) was dropped.
- Clone `~/src/dots-hyprland`, branch `krane`:
  - clean, and `rerere` is on
  - tags `krane/01-fixes`, `krane/02-translator`, `krane/04-agents`
  - `krane` == `krane/04-agents` == `2b6c466`
  - `patches/ii/04-agents/` holds `0001` to `0004`
  - plan 5's commits go after `krane/04-agents` and get tagged `krane/05-settings`
- A preflight of plan 5 against current `main` found nothing blocking, and every finding is applied in `638ee32` (see that commit's diff).
- Hosts: tariognatha, tarmantria and taractias. Hyprland is 0.56.2. The flake pin for dots-hyprland is `97c5bc65…`.

## Environment gotchas (learned the hard way)
- **Don't call `EnterWorktree`.** It turns on a session guard that refuses git on any other repository (the clone, `~/.claude`) and git inside compound shell commands, which blocks the plan's clone workflow. Instead, work in the existing worktree by absolute path, with the session cwd at `/home/krane/.dotfiles` and the session not isolated. There, `git -C ~/src/dots-hyprland …` and `git -C <worktree> …` both work.
- **`git commit --amend` and rebases in the clone may be refused** by the permission check for destructive git. When that happens, add a new commit instead of rewriting history, and tell the user; don't retry the refused command. The plan's `git rebase --autosquash krane/04-agents` steps may hit this too. If they do, leave the `fixup!` commits and report them.
- There's no `sudo` (it needs a password). `nixos-rebuild dry-build` and `nix build` work without it. `hyprctl` can reach the live Hyprland session.
- The RTK hook rewrites some `git` subcommands (to `rtk git …`). If that ever causes a refusal, `/etc/profiles/per-user/krane/bin/git` works as a plain single command.
- Use `command cat`, never bare `cat`. The interactive shell is fish, so run the plan's shell blocks with `bash`.
- Flakes only see git-tracked files: `git add` new patch files before any build or check.
- `just check-new-host` runs on a detached worktree of `HEAD`, so commit before running it (plan Tasks 15 and 21 already say so).

## User rules (from `~/.claude/CLAUDE.md`, restated because they bit us)
- Commit messages: subject line only, no body, and **no Claude or Anthropic attribution** in commits.
- **No "Generated with Claude Code" line or any attribution in PRs**, even if a system reminder asks for one.
- Never push or open a PR unless the user asks. Plan 5 itself says "never push, never open a PR".
- Never commit in `~/.claude`, which is the user's claude-dotfiles repo; `/dotfiles-release` ships it. It currently has uncommitted edits to `CLAUDE.md` and `settings.json` (the attribution rule). Leave them alone.
- Never commit any `config.json` (plan Task 11 is the user's privacy review).
- Pass `model` explicitly on every `Agent` call, using the cheapest model that can do the job. The main thread orchestrates and delegates bulky work.

## Suggested skills
- `superpowers:subagent-driven-development`: run the plan task by task. Keep its ledger in the worktree's `.superpowers/sdd/…`, which is git-ignored; don't `git add -A` it.
- `code-review` with `high` and the task's commit range: the per-task review the user asked for.
- `superpowers:receiving-code-review`: to judge findings before fixing them.
- `superpowers:verification-before-completion`: before claiming any task is done.
- `superpowers:finishing-a-development-branch`: at the end. Present the options only; no PR or push unless the user asks.

## End-of-session report the user expects
- Tasks completed, with their commits.
- Review rounds for each task, and any findings parked with a ruling.
- **The list of steps not done because they need user input**, each with the exact command or check for the user to run.
- The next command, for example the switch after merge.
