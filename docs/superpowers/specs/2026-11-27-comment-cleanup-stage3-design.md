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
(specs, plans, handoffs), and the two code comments/strings that point at docs being deleted.

Out of scope: `CLAUDE.md` (agent instructions), `patches/` and patch commit messages
(cleaned in stage 2; no doc pointers in them). `HANDOFF-*.md` and `SPT-WINDOWS-GUIDE.md`,
listed in the stage handoff, do not exist in the repo.

## Per-file decisions

| File(s) | Action |
|---|---|
| `docs/superpowers/plans/*` (14) | Delete. |
| `docs/superpowers/specs/*` (15) | Migrate rationale (see below), then delete. The comment-cleanup specs are deleted in the last commit. |
| `docs/superpowers/handoffs/2026-10-02-ii-settings-*.md`, `handoff-plan5-ii-settings*.md` (6) | Delete. First, every user step in `ii-settings-user-steps.md` and `ii-settings-manual-test.md` that may not be done goes to the review list. |
| `docs/superpowers/handoffs/2026-11-25-jellyfin-media-server.md` | Keep. Its future spec and plan locations stay. Drop its pointer to the deleted `2026-11-23-server-auto-upgrade-design.md` as a house-format example. |
| `docs/superpowers/handoffs/2026-11-26-comment-cleanup-remaining-stages.md` | Delete in the last commit. |
| `docs/MIGRATION-NOTES.md` | Move each still-live gotcha into the doc that owns its area (`INSTALL.md`, `README.md` or `II-INTEGRATION.md`); drop migration history (KDE, zsh, GRUB, Alacritty and similar "from X to Y" notes); delete the file. |
| `docs/FALLBACK-VENDORING.md` | Fold into `II-INTEGRATION.md` as a section of at most 8 lines: trigger, approach, what breaks. Delete the file. |
| `docs/II-INTEGRATION.md` | Rewrite. Patch sections ("Patched files", "Backported fork fixes"): one paragraph per series, plus detail only for patches with non-obvious runtime effects (for example `KRANE_GUI_MONITORS`, preserved files). Per-patch detail otherwise lives in patch commit messages. Keep procedures (adding an override, patch workflow). |
| `README.md` | Rewrite. Drop "History". Update layout tree and doc index. |
| `docs/INSTALL.md`, `docs/VERIFY.md`, `secrets/README.md` | Rewrite. |
| `modules/home/desktop/fallback-vendoring.nix` | Point comment and assertion message at the new `II-INTEGRATION.md` section. String/comment change only. |
| `modules/nixos/server/auto-upgrade.nix` | Point the spec reference in its header comment at the migrated rationale, or drop it. |

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

Spec groups: nixvim (2 files), ii agent overview / translator / fork fixes (3), ii settings (5),
CI pipelines (1), install new host (1), flake update notify (1), update lanes + server auto-upgrade (2).
The 2 comment-cleanup specs are not migrated.

For each group, keep a piece of rationale only if all three hold:

1. It explains a non-obvious choice in code that still exists.
2. The code and the core docs do not already say it.
3. Someone could break something by not knowing it.

Each kept item becomes 1 to 3 lines in the owning doc, filed in the section about that code (no
"decisions" heading). Owners: ii to `II-INTEGRATION.md`; install, hosts and CI to `INSTALL.md` or
`README.md`; server upgrades to the server section of `secrets/README.md` or `README.md`.
Each migration writes a receipt to the plan's SDD workspace: what moved, where, and what was dropped
and why.

## Order

1. Rationale migration from specs.
2. Core doc rewrites, one doc at a time, which also verifies the migrated lines.
3. Deletions (plans, specs, finished handoffs, MIGRATION-NOTES, FALLBACK-VENDORING).
4. Reference fix-up across docs, code comments and strings.
5. Review list resolved by the user; decisions applied; list deleted.
6. Final review (below), one fix round.
7. Last commit deletes the comment-cleanup spec, plans and handoff. `~/.cache/comment-cleanup/` is
   deleted at the same time (outside git).

## Verification

Reference checker: a throwaway script under `~/.cache/comment-cleanup/`, deleted with it. It scans
every tracked `*.md`, comments in `.nix`, `.sh`, `.py` and `.qml` files, and patch commit messages, and fails on:

- a relative Markdown link or `#anchor` that does not resolve;
- a backticked repo path (`docs/...`, `modules/...`, `scripts/...`, `hosts/...`, `patches/...`) that does not exist;
- a `file:line` whose line does not exist;
- any mention of a deleted doc (`docs/superpowers/specs/`, `docs/superpowers/plans/`,
  `MIGRATION-NOTES`, `FALLBACK-VENDORING`, the deleted handoff names), except the Jellyfin
  handoff's intended future spec/plan locations;
- a patch number or name cited in `docs/II-INTEGRATION.md` that does not match `patches/ii/*/*.patch`.

This re-checks references created or broken by stages 1 and 2 as well.

Read-by-code check: grep for doc or comment text that code or tools read (`install.sh` markers,
assertion strings, golden files). None may break.

Build checks: `just ci`, `just check`, and
`nix build .#nixosConfigurations.tariognatha.config.system.build.toplevel` exit 0.
The only code edits are comment and assertion-string changes.

Final review: one `/code-review` on opus over the full stage 3 diff, one fix round. No further
rounds unless the user asks.

## Review list

`docs/superpowers/doc-review.md`, created during the work. It holds unverifiable claims,
possibly-undone ii-settings user steps, and finished-rollout calls that are unclear. The user
decides each item; decisions are applied; the list is deleted before the last commit.

## Commits

Subject line only, one per logical change:

1. Migrate spec rationale into core docs.
2. One commit per rewritten core doc (README, II-INTEGRATION, INSTALL, VERIFY, secrets/README),
   including moved MIGRATION-NOTES gotchas and the folded fallback section.
3. Delete finished plans.
4. Delete specs (except comment-cleanup).
5. Delete finished ii-settings handoffs.
6. Delete MIGRATION-NOTES and FALLBACK-VENDORING, update code pointers.
7. Reference fix-up.
8. Apply review-list decisions.
9. Final review fixes.
10. Delete comment-cleanup spec, plans and handoff.

## Done when

- Reference checker: 0 failures.
- Build checks pass.
- Review list resolved and deleted.
- `docs/superpowers/` holds only the Jellyfin handoff.
- `~/.cache/comment-cleanup/` deleted.
- Branch not merged until the user says so.
