# Comment cleanup: remaining stages

Branch `doc-cleanup`. Stage 1 (code comments) is done; rules in
`docs/superpowers/specs/2026-11-26-comment-cleanup-design.md` apply to both stages below.
Unverifiable notes go to a review list for the user, never edited silently.

Next session: write one spec per stage (brainstorming, then writing-plans), starting with stage 2.

## Cross-reference check (both stages)

Stage 1 broke references: docs and comments pointed at comments it deleted (host install
headers, apps.nix out-of-scope list, "see its own comment" pointers). Each spec must include:

- Before deleting a comment, grep the repo (code, docs, patches, commit-message tables) for
  pointers to it ("see ... comment", "header", file:line, quoted phrases). Keep it or move the
  pointer target.
- After cleaning, re-scan: every file:line, path, section name and "see X" in code, docs and
  patch commit messages still resolves. Patch numbers/names cited in `docs/II-INTEGRATION.md`
  must match the re-exported series.
- Grep for removed comment text that code reads (markers like `GENERATED FILE` grepped by
  `install.sh`, template placeholders, golden files).
- Stage 3 runs last and must re-verify references created or broken by stages 1 and 2.

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
