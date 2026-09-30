# Handoff: continue plan 5 (ii settings app) from Task 4, in a VM

## Why a VM
The user sets up a VM so that the many settings-window smoke runs (`qs -p .../settings.qml`, 12 s each) can happen there, in parallel with the user's own desktop. Run smoke tests inside the VM's Hyprland session, not on the user's host.

## Read first
- Previous handoff (goal, per-task review loop, env gotchas, user rules, expected end report): `docs/superpowers/handoffs/handoff-plan5-ii-settings.md` (also inside the bundle below). All of it still applies.
- Plan: `docs/superpowers/plans/2026-09-27-ii-settings.md`, spec: `docs/superpowers/specs/2026-09-27-ii-settings-design.md` (branch `ii-settings`).
- Ledger (progress, rulings, deferred minors, snapshot trees): `.superpowers/sdd/2026-09-27-ii-settings/progress.md`. Also in that folder: `env-notes.md` (rules handed to every implementer), `reviewer-instructions.md` / `rereview-instructions.md` (reviewer prompts at effort high), `pkg.sh` (two-repo review package: clone range + dotfiles tree/commit range), `task-N-brief.md` for Tasks 1–25, and `task-1..3-report.md` / `task-2..3-review.md`.

## State
- Dotfiles branch `ii-settings`: `ec0d6d7` (Tasks 2+3 committed, on user's request, as one commit) on top of `638ee32`. Not pushed. The plan otherwise groups commits per the spec's "Commits" section (staged until a group ends). Next group commit is Task 11 (Phase A).
- Clone `~/src/dots-hyprland`, branch `krane`: `c85bfe9b`, `4e7120fb` after `krane/04-agents` (`2b6c466`); tag `krane/05-settings` = `4e7120fb`. **Local only.** On the VM, rebuild from the committed patches: `git -C ~/src/dots-hyprland am -3 <dotfiles>/patches/ii/05-settings/*.patch` on branch `krane` at `krane/04-agents`, then `git tag -f krane/05-settings krane`. The commit hashes will differ; that is fine.
- `~/src/ii-tools/` (forkcheck.py, fork-files.txt, baseline/forkcheck.txt, baseline/*.log for the 8 upstream pages, migtest.sh, phase-a-start): never committed by plan rule. Restore from the bundle. The baseline logs came from the host's session; if smoke noise differs in the VM, regenerate them with Task 3 Step 5 (from `git -C ~/src/dots-hyprland checkout 4e7120fb` state), before comparing Task 6+ pages.
- Done: Task 1 (tools), Task 2 (config dir symlink + migration, review clean, 4 minors deferred), Task 3 (Config.qml subset + II_SETTINGS_PAGE, review clean). Next: **Task 4** (Shared widgets changed by the fork).

## Transfer bundle
`/tmp/plan5-vm-bundle.tgz` holds `ii-tools/`, `.superpowers/sdd/2026-09-27-ii-settings/` and the previous handoff. Unpack: `ii-tools` into `~/src/`, the `.superpowers/...` path into the dotfiles checkout (or worktree) root, the handoff into `/tmp`.
In the VM: adjust `env-notes.md` and `pkg.sh` if the dotfiles checkout path differs from `/home/krane/.dotfiles/.claude/worktrees/ii-settings`.

## Workflow used (keep it)
Per task: `task-N-brief.md` → implementer subagent (sonnet; haiku for pure transcription) pointed at env-notes + brief, writes `task-N-report.md` → `git write-tree` snapshot recorded in ledger → `pkg.sh taskN <clone-base> <clone-head> <prev-snapshot> <new-snapshot>` → reviewer subagent (sonnet; opus for risky Nix/activation or security) using `reviewer-instructions.md` → fix rounds with `rereview-instructions.md` until clean → ledger `Task N: complete ...`.
The real `/code-review` skill was not used, because the task diffs span two repos and dotfiles changes are staged, not committed. Reviewer subagents run at effort "high" instead (ruling in the ledger). Tell the user this if they expected the built-in skill.
The `handoff` skill can only be invoked by the user.

## Steps waiting on the user (so far)
- Task 1: confirm sub-project 1's workflow has survived one pin bump on the hosts.
- Task 2 Step 6: live activation, conflict check and `sudo nixos-rebuild switch --flake .#tarmantria`. Exact commands are in `task-2-report.md`.
- Task 2 Step 8: change the wallpaper in ii's picker, then run the two checks in `task-2-report.md`.
- Task 11: privacy review and commit of `config.json` (plan).

## Suggested skills
- `superpowers:subagent-driven-development`: resume from the ledger. Tasks with `complete` lines are done.
- `superpowers:receiving-code-review`: judge review findings before fixing them.
- `superpowers:verification-before-completion`: before claiming a task is done.
- `superpowers:finishing-a-development-branch`: at the end. Present the options only; no push or PR.
- `code-review` (high): only if the user wants the built-in review on a committed range.
