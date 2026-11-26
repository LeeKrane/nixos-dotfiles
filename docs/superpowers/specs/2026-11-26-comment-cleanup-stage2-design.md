# Comment cleanup, stage 2: comments in `patches/ii/`

Date: 2026-11-26
Branch: `doc-cleanup` (not merged or pushed until the user says so)

## Goal

Apply the stage 1 rules (`docs/superpowers/specs/2026-11-26-comment-cleanup-design.md`,
"Rules") to the comments that the `patches/ii/` series add, without changing any code
and without changing the series layout.

## Scope

In scope: comment lines, including trailing comments on code lines, in the `+` lines of
all 66 patches in `patches/ii/` (01-fixes 11, 02-translator 6, 04-agents 4,
05-settings 41, 06-notifications 1, 07-idle 3). About 475 added comment lines, 312 of them
in `05-settings`. Files are mostly QML, plus py, sh, js, lua and one txt.

Out of scope:

- Context and `-` lines (upstream code).
- Patch commit messages (fork commit, problem, port, drop-when): left as is.
- The three standalone patches in `patches/`.

Before deleting a comment, grep the dotfiles repo (code, docs, patch commit messages)
for pointers to it ("see ... comment", quoted phrases, file:line). Keep the comment or
move the pointer target.

## Method

All work happens in a scratch clone. `~/src/dots-hyprland` stays untouched. Patch
files are never edited by hand; they are re-exported with `git format-patch`.

### 1. Scratch clone

- Clone `https://github.com/end-4/dots-hyprland` to
  `~/.cache/comment-cleanup/dots-hyprland`.
- `PIN` is `.nodes."dots-hyprland".locked.rev` in `flake.lock`.
- Enable `rerere.enabled`.
- Apply the series with the apply loop from `docs/II-INTEGRATION.md` ("Workflow"),
  adapted: the clone path is the scratch clone, not `~/src/dots-hyprland`.
- Create the `krane/<dir>` tags. Keep the original history as branch `orig` and
  tags `orig/<dir>` for the checker.
- Confirm `git rev-list --count PIN..krane` is 66.

### 2. Inventory

A script writes two lists:

- (a) Comment lines in the final tree whose blame commit is in `PIN..krane`, excluding
  lines whose `+` origin is on list (b). Each entry: file, line, text, blame commit
  subject, series.
- (b) `+` comment lines, keyed by (introducing commit subject, file, text), that have
  no list (a) entry with the same key. This covers lines whose final-tree blame is a
  later commit and lines a later commit deletes. Example: commit A adds
  `code // note`, commit B changes only `code`; blame names B, so absorb would put
  the edit into B and A's patch would still add the comment. These are folded by hand
  (step 4b).

Every `+` comment line in the 66 patches matches exactly one entry; the inventory
script fails if a line matches zero entries or two.

### 3. Editing

- Sonnet subagents in parallel. Split the files in list (a) into disjoint groups by
  file, never by series, because 24 files are touched by more than one series. About
  6 groups.
- Each subagent receives the stage 1 rules, this spec and its list entries from both
  lists. It edits only its list (a) lines in the working tree with Edit/Write. For its
  list (b) entries it only returns a decision per entry (delete, or the trimmed text);
  the main thread applies those in step 4b.
- Unverifiable comments stay untouched and go to the review list with their reason.
- Each subagent returns a summary of its changes and its unverifiable notes.

### 4a. List (a): fold edits into their commits

- `git add -u`, then `git absorb --base "$PIN"` (`nix shell nixpkgs#git-absorb`).
  `--base` is needed because absorb only searches the last 10 commits by default.
- Hunks absorb cannot place: `git commit --fixup=<sha>` by hand, using the blame commit
  from list (a).
- `GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash "$PIN"`.
- A manual fixup can conflict when a later commit changed nearby lines. Resolve as the
  later commit's version with the list (a) decision applied (comment deleted or
  trimmed); the checker proves the result.

### 4b. List (b): edit the introducing commits

Runs after 4a, as a separate rebase.

- `git rebase -i "$PIN"` with a script as `GIT_SEQUENCE_EDITOR` that marks every
  introducing commit from list (b) `edit`, matched by commit subject because 4a
  rewrote the SHAs.
- At each stop, apply the subagent's decisions for that commit, `git commit --amend`,
  `git rebase --continue`.
- Conflicts in later commits: take the later commit's side for the conflicted lines.
  It already carries its list (a) edits from 4a.

If a commit becomes empty in 4a or 4b, stop and ask the user.

### 5. Re-tag and export

- Old tags point at pre-rewrite commits. Move each `krane/<dir>` tag to the new commit
  whose subject matches the last subject of that series in `orig`.
- Check that `git rev-list --count PIN..krane/07-idle` is 66 and that each series range
  has 11/6/4/41/1/3 commits.
- Export with the export loop from `docs/II-INTEGRATION.md`, adapted: scratch clone
  path, and the guard also fails on `.git/rebase-merge` (unfinished `rebase -i`), not
  only `.git/rebase-apply`.
- `git -C ~/.dotfiles add patches/ii` before any Nix check: the flake reads the git
  tree, so unstaged patches would test the old series.
- One dotfiles commit per series directory, subject line only.

## Review list

Unverifiable comments go to `docs/superpowers/comment-review.md`: patch file, commit
subject, file:line in the patched source, comment text, why it could not be verified.
The user decides each entry. Decisions are applied in a second round of steps 2 to 5,
then the file is deleted.

## Verification

Comment-only checker, a throwaway at `~/.cache/comment-cleanup/check.py`:

- Pair each `orig` commit with its new commit by subject. 66 pairs; a missing or
  extra subject fails.
- Per pair, diff the two trees line by line. No comment stripping: strippers break on
  `$#`, `${#x}`, `#` or `//` inside strings, regex literals and Lua `--[[ ]]`.
  A changed line passes only if it is:
  - a removed blank line or a removed full-line comment;
  - a full-line comment replaced by a full-line comment (trimmed survivor);
  - the old line with its trailing comment cut off or replaced, the code part
    byte-identical (compared after `rstrip`). A `//` or `#` inside a string can
    make a real code change look like this, so the checker prints every cut or
    replaced trailing comment with its old and new line, and each one is checked by
    hand.
- Comment syntax per file type: QML/js `//`, and lines inside a `/* ... */` block,
  tracked from open to close by a per-file state machine on the `orig` version (a
  ` * ` line outside an open block is code); py/sh `#`; lua `--`. Any other file
  type must match exactly.
- Python docstrings count as code, must match exactly, and are out of scope for this
  stage.
- Shebangs (`#!`) and the machine-read directives from the stage 1 rules stay
  byte-identical. QML `pragma`/`.pragma` lines are code.
- Every removed or changed line in the final tree must blame (in `orig`) to a commit
  in `PIN..orig`. This rejects edits to upstream comments.

Syntax check on every changed file in the final tree: `bash -n` (sh),
`python -m py_compile` (py), `luac -p` (lua), `qmlformat` (QML/js, from
`qt6.qtdeclarative`, used only as a parser, output discarded; `qmllint` is unusable
here because it warns on the unresolved Quickshell imports). A file passes if its tool
succeeds on the new tree whenever it succeeds on `orig`. This catches a bad
trailing-comment cut such as `echo "a # b"` to `echo "a`, which the line rules alone
would pass. Tools run through `nix shell`.

Other checks:

- Every `+` comment line left in the exported patches fits a keep category or is on the
  review list (script lists them, checked by hand).
- Exported filenames are identical to the old ones. `index` lines and hunk offsets may
  change.
- Cross-references: patch numbers, names and "see ..." pointers in
  `docs/II-INTEGRATION.md`, `lib/mk-host.nix`, `README.md` and the patch commit
  messages still resolve.
- `just ci` and `just check`.
- `nix build .#nixosConfigurations.tariognatha.config.system.build.toplevel` (desktop
  host). `dots-hyprland-patched` is the `patchedDotfiles` binding in `lib/mk-host.nix`,
  not a flake output; the toplevel build reaches it. This is the only check that applies
  the series in Nix, after `illogical-flake-cheatsheet-fkeys.patch`; `just check` only
  dry-runs.
- Opus review of the full stage diff against this spec.

No live test: the code is unchanged, and the checker proves it.

## Done when

- The exported series applies cleanly in the `nix build` above.
- All 66 pairs pass the checker, and all checks above pass.
- The review list is resolved and deleted.
- `~/.cache/comment-cleanup/` is deleted before merge.
