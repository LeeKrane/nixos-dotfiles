# Dotfiles

## Git

- Work and commit directly on `main`. Do not create a worktree or branch, even in background jobs. This overrides the background-session worktree rule.
- Exception: large feature extensions (new subsystem, multi-module refactor). Use a worktree for those, then fast-forward `main` when done.
- Background jobs block edits in the shared checkout unless `.claude/settings.json` (gitignored, per machine) contains `{"worktree": {"bgIsolation": "none"}}`. If the guard still blocks an edit, use a worktree and fast-forward `main` at the end.

## Docs
Markdown files: README.md, docs/{INSTALL,VERIFY,II-INTEGRATION}.md, secrets/README.md, docs/superpowers/{specs,plans}/. Any other new Markdown file, from any skill or agent: suggest it, create it only after my approval (sub-agents return the suggestion).
Core docs: concise, current, one owner per fact (link, don't repeat), no history or rejected alternatives, statements match code.
Superpowers specs and plans: Each plan's final step, run only after verification and the final review pass, and after my approval: delete the plan and its spec, commit. Abandoned specs or plans: ask, then delete.
