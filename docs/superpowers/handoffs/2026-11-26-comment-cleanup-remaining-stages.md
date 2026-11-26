# Comment cleanup: remaining stages

Branch `doc-cleanup`. Stage 1 (code comments) is done; rules in
`docs/superpowers/specs/2026-11-26-comment-cleanup-design.md` apply to both stages below.
Unverifiable notes go to a review list for the user, never edited silently.

## Stage 2: comments in `patches/`

- Scope: comments in `+` lines of all 66 `patches/ii/*/*.patch` (all authored in this repo)
  and the three standalone patches in `patches/`. Context lines are upstream: untouched.
- Open question: commit messages (fork commit, problem, port, drop-when) stay as is, or get
  trimmed too. Recommendation: leave them.
- Method: scratch clone of dots-hyprland at the flake's pinned rev (`flake.lock`), `git am`
  every series in order, clean comments commit by commit, re-export each series with
  `git format-patch --zero-commit --no-signature --no-numbered` (see `docs/II-INTEGRATION.md`).
  Never hand-edit `.patch` files. The stale fork `~/src/dots-hyprland` stays untouched.
- Done when: series apply cleanly, `just ci`, `just check` pass, diff of the patched source
  is comment-only.

## Stage 3: Markdown docs

- Scope: `README.md`, `docs/*.md`, `HANDOFF-*.md`, `SPT-WINDOWS-GUIDE.md`,
  `secrets/README.md`, `docs/superpowers/` (specs, plans, handoffs).
- Goal: concise docs with only relevant, current information. Delete stale or finished
  handoffs/plans, cut history and prescriptive rules, verify every claim against the code.
- Open question: keep or delete finished `docs/superpowers/` plans and specs.
- Done when: every remaining doc statement is verified, links resolve, user approved deletions.

## Before merge

Delete `~/.cache/comment-cleanup/` (throwaway checker). Merge only when the user says so.
