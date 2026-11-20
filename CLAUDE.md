# Dotfiles

## Git

- Work and commit directly on `main`. Do not create a worktree or branch, even in background jobs. This overrides the background-session worktree rule.
- Exception: large feature extensions (new subsystem, multi-module refactor). Use a worktree for those, then fast-forward `main` when done.
- Background jobs block edits in the shared checkout unless `.claude/settings.json` (gitignored, per machine) contains `{"worktree": {"bgIsolation": "none"}}`. If the guard still blocks an edit, use a worktree and fast-forward `main` at the end.
