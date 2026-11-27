# Comment cleanup stage 3: Markdown docs

Branch `doc-cleanup`. Stages 1 (code comments) and 2 (comments in `patches/`) are done.
This stage cleans the Markdown docs and closes out the whole cleanup.
Rules from `docs/superpowers/specs/2026-11-26-comment-cleanup-design.md` still apply where they fit.
Statements that cannot be verified from the repo go to a review list for the user and are never edited silently.

## Goal

Concise docs that hold only current, verified, relevant information. History, finished work and
pure style rules go. Git history is the archive for everything deleted.

## Scope

In scope: `README.md`, `docs/*.md`, `secrets/README.md`, all of `docs/superpowers/`
(specs, plans, handoffs), and code comments and strings that point at docs or doc sections
this stage deletes or renames.

Out of scope: `CLAUDE.md` (agent instructions). `patches/` content is not edited, but three patch
commit messages point at `docs/II-INTEGRATION.md` ("dropped, see docs/II-INTEGRATION.md" in
`patches/ii/05-settings/0011`, `0012` and `0013`), so the doc must keep what they point at
(see Contracts). `HANDOFF-*.md` and `SPT-WINDOWS-GUIDE.md`, listed in the stage handoff, do not
exist in the repo.

## Per-file decisions

| File(s) | Action |
|---|---|
| `docs/superpowers/plans/*`: 11 finished plans | Delete. |
| `docs/superpowers/specs/*`: 13 non-cleanup specs | Migrate rationale (see below), then delete. |
| Comment-cleanup docs: 3 specs (stage 1, 2, 3), 2 plans (stage 1, 2, plus stage 3 once written), 1 handoff | Delete in the last commit. |
| `docs/superpowers/handoffs/2026-10-02-ii-settings-*.md` (4), `handoff-plan5-ii-settings*.md` (2) | Delete. First, every user step in `2026-10-02-ii-settings-user-steps.md` and `2026-10-02-ii-settings-manual-test.md` that may not be done goes to the review list. |
| `docs/superpowers/handoffs/2026-11-25-jellyfin-media-server.md` | Keep. Its future spec and plan locations stay. Drop its pointer to the deleted `2026-11-23-server-auto-upgrade-design.md` as a house-format example. |
| `docs/MIGRATION-NOTES.md` | Move each still-live gotcha into the doc that owns its area (`INSTALL.md`, `VERIFY.md`, `README.md`, `II-INTEGRATION.md` or `secrets/README.md`; for example monitor position goes to `VERIFY.md`, `rclone.conf` to `secrets/README.md` or `INSTALL.md`). Drop migration history ("from X to Y" notes: KDE, zsh, GRUB, Alacritty and similar). Delete the file. |
| `docs/FALLBACK-VENDORING.md` | Fold into `II-INTEGRATION.md` as a section of at most 8 lines: trigger, approach, what breaks. Delete the file. |
| `docs/II-INTEGRATION.md` | Rewrite. Patch sections ("Patched files", "Backported fork fixes"): one paragraph per series, plus detail only for patches with non-obvious runtime effects (for example `KRANE_GUI_MONITORS`, preserved files). Per-patch detail otherwise lives in patch commit messages. Keep procedures (adding an override, patch workflow). |
| `README.md` | Rewrite. Drop "History". Update layout tree and doc index. |
| `docs/INSTALL.md`, `docs/VERIFY.md`, `secrets/README.md` | Rewrite. |
| `modules/home/desktop/fallback-vendoring.nix` | Point comment and assertion message at the new `II-INTEGRATION.md` section. Reword the assertion so it promises only what the short section gives (approach, not step-by-step instructions). |
| `modules/nixos/server/auto-upgrade.nix` | Header comment cites the server-auto-upgrade spec. Point it at the migrated rationale, or drop the reference. |

## Contracts the rewrite must keep

Headings and anchors that code, other docs or patch messages depend on:

- `docs/VERIFY.md` heading `## 2. On-target checklist` (`install.sh` prints "docs/VERIFY.md section 2";
  `docs/INSTALL.md` links `VERIFY.md#2-on-target-checklist`).
- `docs/II-INTEGRATION.md` "Ported and dropped controls" table (patch messages 05-settings
  0011 to 0013 point at it).
- `docs/II-INTEGRATION.md` section names quoted in code comments, for example "Settings persistence",
  "Patched files", "Preserved files", "Wiped on every switch". A heading may change only if every
  quoting comment changes in the same commit.

The executor builds the full list from the reference checker's first run (before any edit) and
re-checks it at the end.

## Rules for rewritten docs

- Verify every statement against the code: paths, option names, commands, flags, `file:line`,
  host names, patch series and patch names. Fix false statements.
- Statements that cannot be checked from the repo (hardware behaviour, NVIDIA steps, dual-boot,
  manual steps a user may or may not have done) go to the review list.
- Cut history: "previously", "was changed from", rejected alternatives, dated narrative.
- Instructional text:
  - Procedures (how to add an override, patch workflow, create or rotate a secret, install steps,
    NVIDIA ladder): keep, verified and tightened.
  - Policy and "never" lists: keep only rules whose violation causes real damage (leaked secret,
    clobbered key, broken boot), one line each with the reason. Drop pure style preferences.
  - Checklists for finished one-off rollouts: delete. Keep checklists that are re-run per host or
    install (for example `VERIFY.md`'s on-target list). If unsure whether a rollout is finished,
    review list.
- One owner per fact. Other docs link to it instead of repeating it.
- Plain, concise prose. No filler.

## Rationale migration (specs to core docs)

13 specs in 7 groups: nixvim (1), ii agent overview / translator / fork fixes (3), ii settings
(4: settings, boot path, GUI write paths, input hardening), CI pipelines (1), install new host (1),
flake update notify (1), update lanes + server auto-upgrade (2).

For each group, keep a piece of rationale only if all three hold:

1. It explains a non-obvious choice in code that still exists.
2. The code and the core docs do not already say it.
3. Someone could break something by not knowing it.

Each kept item becomes 1 to 3 lines in the owning doc, filed in the section about that code (no
"decisions" heading). Owners: ii to `II-INTEGRATION.md`; install, hosts and CI to `INSTALL.md` or
`README.md`; server upgrades to the server section of `secrets/README.md` or `README.md`.
Each group writes a receipt to the plan's SDD workspace
(`.superpowers/sdd/2026-11-27-comment-cleanup-stage3/`, git-ignored): what moved, where, and
what was dropped and why.

## Order

1. Rationale migration from specs.
2. Core doc rewrites, one doc at a time, which also verifies the migrated lines. Order:
   `II-INTEGRATION.md` (includes the folded fallback section), `INSTALL.md`, `VERIFY.md`,
   `secrets/README.md`, `README.md` last (it links the others).
3. Deletions. Each deletion commit also fixes every pointer to what it deletes, so no commit
   leaves a dangling reference.
4. Reference sweep across all tracked text files.
5. Review list resolved by the user; decisions applied; list deleted.
6. Final review (below), one fix round.
7. Last commit deletes the comment-cleanup specs, plans and handoff. `~/.cache/comment-cleanup/` is
   deleted at the same time (outside git).

## Verification

Reference checker: a throwaway script under `~/.cache/comment-cleanup/`, deleted with it. It scans
every tracked text file (Markdown, Nix, shell, Python, QML, `justfile`, `.github/**`, patch files
including their commit messages) and fails on:

- a relative Markdown link or `#anchor` that does not resolve;
- a repo path token, meaning anything starting with a top-level tracked directory
  (`docs/`, `modules/`, `scripts/`, `hosts/`, `patches/`, `secrets/`, `pkgs/`, `lib/`, `tests/`,
  `templates/`, `config/` and any other top-level directory present), that does not exist;
- a `file:line` whose line does not exist;
- a quoted doc section name next to a doc path (for example `docs/II-INTEGRATION.md "Patched files"`)
  that matches no heading in that doc;
- any mention of a deleted doc (`docs/superpowers/specs/<name>`, `docs/superpowers/plans/<name>`,
  `MIGRATION-NOTES`, `FALLBACK-VENDORING`, the deleted handoff names);
- a patch number or name cited in `docs/II-INTEGRATION.md` that does not match `patches/ii/*/*.patch`.

Exemptions, applied to every rule: tokens containing a `<...>` placeholder (for example
`hosts/<host>/`, `<date>-jellyfin-...`), and the Jellyfin handoff's future
`docs/superpowers/specs/` and `docs/superpowers/plans/` locations.

The checker runs once before any edit (baseline; pre-existing failures from stages 1 and 2 are
fixed in this stage too) and after every commit.

Read-by-code check: grep for doc or comment text that code or tools read (`install.sh` markers and
messages, assertion strings, golden files). None may break.

Build checks: `just ci`, `just check`, and
`nix build .#nixosConfigurations.tariognatha.config.system.build.toplevel` exit 0. `just check` is
the gate for server-module edits (`auto-upgrade.nix`), since only `tariognatha` is built.
The only code edits are comment and assertion-string changes. GitHub CI skips docs-only pushes
(`.github/workflows/check.yml` ignores `**.md` and `docs/**`), so local checks are the gate.

Final review: one `/code-review` on opus over the full stage 3 diff, one fix round. No further
rounds unless the user asks.

## Review list

`docs/superpowers/doc-review.md`, committed in its own commit when created and removed in the
commit that applies the decisions (as in stage 2). It holds unverifiable claims, possibly-undone
ii-settings user steps, and finished-rollout calls that are unclear. The user decides each item.

## Commits

Subject line only, one per logical change, in this order:

1. Migrate spec rationale into core docs.
2. One commit per rewritten core doc, in the order under "Order" step 2. The `II-INTEGRATION.md`
   commit adds the folded fallback section and its moved gotchas; each later doc commit adds its
   moved MIGRATION-NOTES gotchas.
3. Delete finished plans.
4. Delete non-cleanup specs; repoint `auto-upgrade.nix` and any other spec pointers.
5. Delete finished ii-settings handoffs; fix the Jellyfin handoff.
6. Delete MIGRATION-NOTES and FALLBACK-VENDORING; repoint `fallback-vendoring.nix` and README links.
7. Reference sweep fixes (if any remain).
8. Add review list.
9. Apply review-list decisions and drop the list.
10. Final review fixes.
11. Delete comment-cleanup specs, plans and handoff.

## Done when

- Reference checker: 0 failures.
- Build checks pass.
- Review list resolved and deleted.
- `docs/superpowers/` holds only the Jellyfin handoff.
- `~/.cache/comment-cleanup/` deleted.
- Branch not merged until the user says so.
