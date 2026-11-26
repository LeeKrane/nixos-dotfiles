# Comment cleanup, stage 1: code comments

Date: 2026-11-26
Branch: `doc-cleanup` (no worktree; not merged or pushed until the user says so)

## Goal

Cut the comment volume (about 5,000 comment lines in 26,000 lines of code) down to
comments that carry information the code cannot. Stale or speculative comments
create false rules and assumptions for future readers, human or AI.

## Stages

1. Code comments (this spec).
2. Comments in `patches/ii/` (own spec): rebuild the series in a scratch clone at the
   flake's pinned rev, clean commit by commit, re-export with `git format-patch`.
   The stale fork at `~/src/dots-hyprland` stays untouched.
3. Markdown docs (own spec): make them concise and relevant.

## Rules

Default is delete. A comment survives only if it fits a keep category, and a
survivor is trimmed to the fewest words that keep its meaning.

Keep:

- **Why/workaround notes that are verified and necessary.** Check each claim
  against the code and its sources (referenced code still exists, linked issue or
  version still matches, the behavior it guards is still there). Verified and
  needed: keep, trimmed. Verified false or obsolete: delete. Cannot be verified
  from the repo (hardware quirk, unlinked upstream bug, timing workaround): leave
  untouched and add it to the review list.
- **Machine-read directives:** shebangs, `# shellcheck ...`, lint pragmas
  (statix, deadnix, `# noqa`, `# type:`), modelines, `# @ts-...`.
- **External references** (URL, issue number) behind a pinned version, hash or
  workaround.
- **License or attribution headers.**
- **Section banners**, reduced to one short line (`# Audio`), no padding or rulers.
- **Template placeholder hints** in `templates/` (what to fill in), trimmed.

Delete:

- Comments that restate what the next line or block does.
- Commented-out code.
- History or changelog notes ("previously", "was changed", "since session X").
- All prescriptive rules for future editors ("always", "never", "do not change",
  "keep in sync with").
- Speculation ("probably", "should be fine", "might").

Scope details:

- Comments inside Nix strings that become generated config files (Hyprland, fish,
  Lua, shell) follow the same rules.
- Test files follow the same rules; a descriptive test name replaces a comment.
- Out of scope: `LICENSE`, `flake.lock`, JSON, `android/`, `assets/`,
  `secrets/`, `patches/` (stage 2), `*.md` (stage 3).

## Execution

One sonnet subagent per area. Each receives this spec, edits only its area with
Edit/Write, and returns its diff summary plus its unverifiable notes. One commit per
area (subject line only):

1. `modules/nixos`
2. `modules/home`
3. `modules/nixvim`
4. `hosts` and `templates`
5. `lib`, `flake.nix`, `overlays`
6. `scripts`, `install.sh`, `justfile`, `.github`
7. `pkgs`
8. Rest (`tests`, `config`, root dotfiles such as `.sops.yaml`, `statix.toml`)

Unverifiable notes go to `docs/superpowers/comment-review.md`
(file:line, comment text, why it could not be verified). The user decides each one;
the file is deleted before merge.

## Verification

Per area commit:

- Comment-only check: a script strips comments from the old and new version of every
  changed file and compares. Any difference other than comments or blank lines
  fails the area.
- `just ci` (lint: nixfmt, statix, deadnix, shellcheck, actionlint; plus
  `scripts/tests`).

After all areas:

- `just check` (`nix flake check` and every host's toplevel dry-run, in docker).
- `just install-test` (only if `install.sh` changed).
- `pkgs/krane-ii-settings` pytest suite.
- Opus review of the full stage diff against this spec.

## Success criteria

- Every remaining comment fits a keep category.
- No code change in the diff, confirmed by the comment-only check.
- All checks above pass.
- Every unverifiable note is either in the review list or untouched.
