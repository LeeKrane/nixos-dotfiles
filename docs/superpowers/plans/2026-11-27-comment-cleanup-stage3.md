# Comment cleanup stage 3: Markdown docs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut the repo's Markdown docs to current, verified, relevant content, delete finished plans, specs and handoffs, and close out the comment cleanup.

**Architecture:** Rationale moves from specs into the core docs first, then each core doc is rewritten and verified against the code, then the old docs are deleted with their pointers fixed in the same commit. A throwaway reference checker (`~/.cache/comment-cleanup/refcheck.py`) gates every commit.

**Tech Stack:** Markdown, Nix (comment and string edits only), Python 3 checker, `just`, `nix build`.

**Spec:** `docs/superpowers/specs/2026-11-27-comment-cleanup-stage3-design.md`

## Global Constraints

- Branch `doc-cleanup` in `/home/krane/.dotfiles`. Never push, never merge, never open a PR.
- Commit messages: subject line only, no body, no Claude or Anthropic attribution.
- Create and change files only with the Write or Edit tools (or the REPL `edit`/`write` helpers). Never with shell redirects, heredocs, `sed -i` or `tee`. Deletions use `git rm`.
- Use `command cat`, never bare `cat`.
- Every subagent dispatch passes `model` explicitly.
- Statements that cannot be verified from the repo go to the review-items file, never edited silently.
- The only code edits allowed: comments, and the assertion message in `modules/home/desktop/fallback-vendoring.nix`.
- Contracts (must hold after every commit):
  - `docs/VERIFY.md` keeps the heading `## 2. On-target checklist` (`install.sh` prints "docs/VERIFY.md section 2"; `docs/INSTALL.md` links `VERIFY.md#2-on-target-checklist`).
  - `docs/II-INTEGRATION.md` keeps the "Ported and dropped controls" table (patch messages `05-settings` 0011 to 0013 point at it).
  - `docs/II-INTEGRATION.md` headings quoted in code comments ("Settings persistence", "Patched files", "Preserved files", and any other the checker reports) keep their text, unless every quoting comment changes in the same commit.
- Checker command (run from anywhere): `python3 ~/.cache/comment-cleanup/refcheck.py ~/.dotfiles`. Baseline before this plan: 1 failure, `patches/ii/01-fixes/0006-...patch:9: missing path: modules/home/illogical-impulse.nix` (patch content is out of scope; goes to the review list). "Checker clean" in this plan means: no failures other than that one.
- SDD workspace: `.superpowers/sdd/2026-11-27-comment-cleanup-stage3/` (git-ignored). Receipts and `review-items.md` live there.

## Review Focus

1. A heading or anchor that code or a patch message depends on is renamed during a rewrite. Expected: the checker fails before commit (quoted-heading and anchor rules), the contracts above hold. Pinned by the checker run in every rewrite task, and the contract grep in Task 9.
2. `install.sh`'s prose string "docs/VERIFY.md section 2" is not a link, so no rule covers it. Expected: still true after the VERIFY rewrite. Pinned by the grep step in Task 5 and Task 9.
3. A spec is deleted before its rationale is migrated. Expected: every one of the 13 specs has a receipt entry before `git rm`. Pinned by the receipt check in Task 7.
4. A live gotcha from `MIGRATION-NOTES.md` is lost. Expected: every `##` section has a recorded disposition (moved to X, or dropped as history). Pinned by the disposition check in Task 8.
5. A rewritten procedure states a wrong command, flag or option. Expected: every command, flag, `just` recipe and Nix option in a rewritten doc exists in the code. Pinned by the verification table each rewrite task writes to its receipt.

---

### Task 1: Setup and baseline

**Files:**
- Create: `.superpowers/sdd/2026-11-27-comment-cleanup-stage3/review-items.md`

- [ ] **Step 1: Confirm the checker and baseline**

Run: `git -C ~/.cache/comment-cleanup log --oneline -1 -- refcheck.py && python3 ~/.cache/comment-cleanup/refcheck.py ~/.dotfiles`
Expected: commit "Add stage 3 reference checker"; output is exactly the one baseline failure; exit 1.

- [ ] **Step 2: Record the quoted-heading contracts**

Run: `git -C ~/.dotfiles grep -nE 'docs/[A-Za-z_./-]+\.md[^"]{0,30}"' -- . ':!docs/superpowers'`
Write every doc + heading pair found to the ledger under "Contracts".

- [ ] **Step 3: Start the review-items file**

Write `review-items.md` with:

```markdown
# Stage 3 review items

## Patch messages
- `patches/ii/01-fixes/0006` message says `modules/home/illogical-impulse.nix`; the file is now `modules/home/desktop/illogical-impulse.nix`. Patch content is out of scope for stage 3. Decide: leave, or re-export the patch with the path fixed.
```

No commit (workspace is git-ignored).

### Task 2: Migrate spec rationale into core docs

**Files:**
- Modify: `docs/II-INTEGRATION.md`, `docs/INSTALL.md`, `README.md`, `secrets/README.md` (only where a kept item belongs)
- Create: `.superpowers/sdd/2026-11-27-comment-cleanup-stage3/receipt-migration.md`

Groups (13 specs):

| Group | Specs (`docs/superpowers/specs/`) | Owner doc |
|---|---|---|
| nixvim | `2026-09-23-nixvim-migration-design.md` | `README.md` |
| ii fork work | `2026-09-27-ii-agent-overview-design.md`, `2026-09-27-ii-translator-design.md`, `2026-09-27-ii-fork-fixes-design.md` | `docs/II-INTEGRATION.md` |
| ii settings | `2026-09-27-ii-settings-design.md`, `2026-10-02-ii-settings-boot-path-design.md`, `2026-10-02-ii-settings-gui-write-paths-design.md`, `2026-10-02-ii-settings-input-hardening-design.md` | `docs/II-INTEGRATION.md` |
| CI | `2026-09-30-ci-pipelines-design.md` | `README.md` |
| install | `2026-09-30-install-new-host-design.md` | `docs/INSTALL.md` |
| flake update notify | `2026-10-06-flake-update-notify-design.md` | `README.md` |
| updates | `2026-11-23-update-lanes-design.md`, `2026-11-23-server-auto-upgrade-design.md` | `secrets/README.md` server section or `README.md` |

- [ ] **Step 1: Migrate one group at a time**

For each group: read its specs, then the owner doc and the code the spec describes. Keep a piece of rationale only if all three hold: (1) it explains a non-obvious choice in code that still exists; (2) neither the code (comments included) nor any core doc already says it; (3) someone could break something by not knowing it. Add each kept item as 1 to 3 lines in the owner doc's section about that code. No "decisions" heading. Append to `receipt-migration.md` per spec: kept items (text + where), dropped items with a one-line reason.

A sonnet subagent may do one group per dispatch; groups run one after another (same files).

- [ ] **Step 2: Check receipt coverage**

Run: `for f in <the 13 spec basenames>; do grep -q "$f" .superpowers/sdd/2026-11-27-comment-cleanup-stage3/receipt-migration.md || echo "MISSING $f"; done`
Expected: no output.

- [ ] **Step 3: Checker**

Run the checker. Expected: clean.

- [ ] **Step 4: Commit**

`git add docs/II-INTEGRATION.md docs/INSTALL.md README.md secrets/README.md && git commit -m "Migrate spec rationale into core docs"`

### Task 3: Rewrite docs/II-INTEGRATION.md

**Files:**
- Modify: `docs/II-INTEGRATION.md`
- Create: `.superpowers/sdd/2026-11-27-comment-cleanup-stage3/receipt-ii-integration.md`

- [ ] **Step 1: Rewrite**

Apply the spec's "Rules for rewritten docs" to every section. Specific changes:
- "Patched files" and "Backported fork fixes": one paragraph per series (`01-fixes`, `02-translator`, `04-agents`, `05-settings`, `06-notifications`, `07-idle`): purpose, ordering or dependencies. Keep detail only for patches with non-obvious runtime effects (`KRANE_GUI_MONITORS`, preserved files, and others you find; list them in the receipt with why). Drop per-patch tables that repeat commit messages.
- Line 277 says `05-settings` "is not present yet"; it exists. Fix.
- Keep "Ported and dropped controls" (contract), "How to add an override", the patch "Workflow" and "When to stop using patches" (trim to rules that prevent damage).
- Remove pointers to `docs/superpowers/specs/` and `docs/superpowers/plans/` (lines near 375, 505, 553, 753); state the needed fact inline or drop it.
- Add a section "If the soymou module breaks" of at most 8 lines, from `docs/FALLBACK-VENDORING.md`: trigger, approach (self-vendor dots-hyprland, which `krane.iiVendored.enable` stubs), what breaks. No step list. Replace the link to `FALLBACK-VENDORING.md` (near line 817) with a link to this section.
- Move ii-related live gotchas from `docs/MIGRATION-NOTES.md` (for example "Dropped: upstream ii's Edit user keybinds bind") into the matching section. Record dispositions in the receipt.

- [ ] **Step 2: Verify statements**

For every path, option, command, `file:line`, series and patch name: confirm it in the code (`git grep`, the patches dir, the scratch clone `~/.cache/comment-cleanup/dots-hyprland` branch `krane`). Write a table to the receipt: statement, evidence, result. Unverifiable ones go to `review-items.md` under "II-INTEGRATION".

- [ ] **Step 3: Checker and contracts**

Run the checker: clean. Run `grep -n 'Ported and dropped controls\|Settings persistence\|Patched files\|Preserved files' docs/II-INTEGRATION.md`: each heading still present (or every quoting comment updated in this commit).

- [ ] **Step 4: Commit**

`git add -A docs/II-INTEGRATION.md modules pkgs && git commit -m "Rewrite II-INTEGRATION doc: verified, per-series patch notes, fallback section"` (stage only files you changed).

### Task 4: Rewrite docs/INSTALL.md

**Files:**
- Modify: `docs/INSTALL.md`
- Create: `.superpowers/sdd/2026-11-27-comment-cleanup-stage3/receipt-install.md`

- [ ] **Step 1: Rewrite**

Apply the rewrite rules. Keep procedures: `./install.sh` steps, flags, setup mode, new machine, NVIDIA ladder, dual-boot entry, data migration, Appendix A and B. Verify every flag and step against `install.sh` (function names `run_install_mode`, `run_setup_mode`, flag parser). Move install-related live gotchas from `docs/MIGRATION-NOTES.md` (for example `*.hm-bak` files, hostnames, `home.stateVersion` if still relevant) and record dispositions in the receipt. Hardware behaviour (NVIDIA, dual-boot, DNS timeouts) that the code cannot confirm goes to `review-items.md` under "INSTALL".

- [ ] **Step 2: Verification table**

Write to the receipt: statement, evidence, result, for every command, flag and path.

- [ ] **Step 3: Checker**

Clean. Also: `grep -n 'VERIFY.md#2-on-target-checklist' docs/INSTALL.md` still matches (or the link was dropped on purpose and the anchor rule passes).

- [ ] **Step 4: Commit**

`git add docs/INSTALL.md && git commit -m "Rewrite INSTALL doc against current install.sh"`

### Task 5: Rewrite docs/VERIFY.md

**Files:**
- Modify: `docs/VERIFY.md`
- Create: `.superpowers/sdd/2026-11-27-comment-cleanup-stage3/receipt-verify.md`

- [ ] **Step 1: Rewrite**

Apply the rewrite rules. Keep "1. Docker loop" (verify against `scripts/docker-check.sh` and the `justfile`), keep `## 2. On-target checklist` word for word as the heading (contract), keep "Settings window" checks if they are re-run per switch. Move "Monitor position and mouse device name, verify on target" from `docs/MIGRATION-NOTES.md` into the on-target checklist; record disposition.

- [ ] **Step 2: Verification table and contract grep**

Receipt table as in Task 4. Run: `grep -n 'VERIFY.md section 2' install.sh && grep -n '^## 2. On-target checklist$' docs/VERIFY.md`. Expected: both match.

- [ ] **Step 3: Checker**

Clean.

- [ ] **Step 4: Commit**

`git add docs/VERIFY.md && git commit -m "Rewrite VERIFY doc"`

### Task 6: Rewrite secrets/README.md

**Files:**
- Modify: `secrets/README.md`
- Create: `.superpowers/sdd/2026-11-27-comment-cleanup-stage3/receipt-secrets.md`

- [ ] **Step 1: Rewrite**

Apply the rewrite rules. Keep "Files" (verify each file against `secrets/` and `.sops.yaml`), "How to create one", "Rotating or re-keying". "Never": keep only rules that prevent a leak or lockout, one line each with the reason. "Rollout checklist" under server upgrades: delete if the rollout is done (evidence: the server hosts import `modules/nixos/server/auto-upgrade.nix` and their secrets exist); if unsure, `review-items.md` under "secrets". Move the `rclone.conf` live-file gotcha from `docs/MIGRATION-NOTES.md` here or to `INSTALL.md`; record disposition.

- [ ] **Step 2: Verification table**

Receipt table as in Task 4.

- [ ] **Step 3: Checker**

Clean.

- [ ] **Step 4: Commit**

`git add secrets/README.md && git commit -m "Rewrite secrets README"`

### Task 7: Rewrite README.md

**Files:**
- Modify: `README.md`
- Create: `.superpowers/sdd/2026-11-27-comment-cleanup-stage3/receipt-readme.md`

- [ ] **Step 1: Rewrite**

Apply the rewrite rules. Drop "History". Update "Layout" so it matches `git ls-files` top-level dirs and no longer lists `MIGRATION-NOTES` or `FALLBACK-VENDORING`. Update "Docs" to list only docs that will remain: `docs/INSTALL.md`, `docs/VERIFY.md`, `docs/II-INTEGRATION.md`, `secrets/README.md`. Verify hosts against `hosts/` and `flake.nix`, checks and CI against `justfile` and `.github/workflows/`. Move remaining general gotchas from `docs/MIGRATION-NOTES.md` (default browser, Go toolchain, rust-analyzer, texlive, no standalone python3, UWSM, NixVim notes) only if still true and non-obvious; record dispositions.

Note: the checker will flag `MIGRATION-NOTES` mentions only once the file is deleted; README must already not mention it after this task.

- [ ] **Step 2: Verification table**

Receipt table as in Task 4.

- [ ] **Step 3: Checker**

Clean. Also `grep -n 'MIGRATION-NOTES\|FALLBACK-VENDORING' README.md`: no output.

- [ ] **Step 4: Commit**

`git add README.md && git commit -m "Rewrite README"`

### Task 8: Delete finished plans

**Files:**
- Delete: `docs/superpowers/plans/` `2026-09-23-nixvim-phase1.md`, `2026-09-23-nixvim-phase2.md`, `2026-09-27-ii-agent-overview.md`, `2026-09-27-ii-fork-fixes.md`, `2026-09-27-ii-settings.md`, `2026-09-27-ii-translator.md`, `2026-09-30-ci-pipelines.md`, `2026-09-30-install-new-host.md`, `2026-10-06-flake-update-notify.md`, `2026-11-23-server-auto-upgrade.md`, `2026-11-23-update-lanes.md`

- [ ] **Step 1: Find pointers**

Run: `git grep -n 'docs/superpowers/plans/' -- . ':!docs/superpowers/specs' ':!docs/superpowers/plans'`. Fix each pointer outside the comment-cleanup docs (state the fact inline or drop it). The Jellyfin handoff's future `docs/superpowers/plans/` location stays.

- [ ] **Step 2: Delete and check**

`git rm` the 11 files. Run the checker: clean.

- [ ] **Step 3: Commit**

`git commit -m "Delete finished implementation plans"` (include any pointer fixes).

### Task 9: Delete non-cleanup specs

**Files:**
- Delete: the 13 specs in Task 2's table
- Modify: `modules/nixos/server/auto-upgrade.nix` (line 3 comment), any other pointer found

- [ ] **Step 1: Receipt check**

Repeat Task 2 Step 2. Expected: no MISSING line.

- [ ] **Step 2: Fix pointers**

Run: `git grep -n 'docs/superpowers/specs/' -- . ':!docs/superpowers/specs' ':!docs/superpowers/plans'`. In `auto-upgrade.nix` replace "See docs/superpowers/specs/2026-11-23-server-auto-upgrade-design.md." with a pointer to where Task 2 put the rationale, or drop the sentence. Jellyfin handoff: drop the line pointing at `2026-11-23-server-auto-upgrade-design.md` as a format example (handled in Task 10). Leave the comment-cleanup docs.

- [ ] **Step 3: Delete, check, build**

`git rm` the 13 specs. Run the checker: clean (the Jellyfin line may fail until Task 10; if so, fix it here instead). Run `just check`: exit 0 (gate for the server-module comment edit).

- [ ] **Step 4: Contract grep**

Run: `grep -n 'VERIFY.md section 2' install.sh && grep -n '^## 2. On-target checklist$' docs/VERIFY.md && grep -n 'Ported and dropped controls' docs/II-INTEGRATION.md`. Expected: all match.

- [ ] **Step 5: Commit**

`git commit -m "Delete finished design specs"`

### Task 10: Delete finished ii-settings handoffs

**Files:**
- Delete: `docs/superpowers/handoffs/2026-10-02-ii-settings-changes.md`, `2026-10-02-ii-settings-manual-test.md`, `2026-10-02-ii-settings-premerge.md`, `2026-10-02-ii-settings-user-steps.md`, `handoff-plan5-ii-settings.md`, `handoff-plan5-ii-settings-vm.md`
- Modify: `docs/superpowers/handoffs/2026-11-25-jellyfin-media-server.md`

- [ ] **Step 1: Extract possibly-undone user steps**

Read `2026-10-02-ii-settings-user-steps.md` and `2026-10-02-ii-settings-manual-test.md`. For each step or check: if the repo shows it done (code, config, commits), note the evidence in the ledger; otherwise add it to `review-items.md` under "ii-settings user steps", one line each with the original wording.

- [ ] **Step 2: Fix Jellyfin handoff**

Remove the line "Existing specs in `docs/superpowers/specs/` show the house format, for example `2026-11-23-server-auto-upgrade-design.md`." Keep the future spec and plan locations.

- [ ] **Step 3: Delete and check**

`git rm` the 6 handoffs. `git grep -n 'ii-settings-\(changes\|manual-test\|premerge\|user-steps\)\|handoff-plan5'` outside the comment-cleanup docs: no output. Checker: clean.

- [ ] **Step 4: Commit**

`git commit -m "Delete finished ii-settings handoffs"`

### Task 11: Delete MIGRATION-NOTES and FALLBACK-VENDORING

**Files:**
- Delete: `docs/MIGRATION-NOTES.md`, `docs/FALLBACK-VENDORING.md`
- Modify: `modules/home/desktop/fallback-vendoring.nix` (lines 1, 21, 31)

- [ ] **Step 1: Disposition check**

Run: `grep '^## ' docs/MIGRATION-NOTES.md`. Every heading must appear in one of the receipts (Tasks 3 to 7) as "moved to <doc>" or "dropped: history". Add any missing one now (move it, or record why it is history).

- [ ] **Step 2: Repoint fallback-vendoring.nix**

Line 1 comment and the assertion message (lines 21 and 31) point at `docs/II-INTEGRATION.md` section "If the soymou module breaks". Reword the assertion so it does not promise step-by-step instructions, for example: "krane.iiVendored.enable is a stub; see docs/II-INTEGRATION.md "If the soymou module breaks" for the self-vendoring approach." Keep the assertion condition unchanged.

- [ ] **Step 3: Delete and check**

`git rm` both docs. Checker: clean. `git grep -n 'MIGRATION-NOTES\|FALLBACK-VENDORING'` outside comment-cleanup docs: no output. Run `just ci`: exit 0.

- [ ] **Step 4: Commit**

`git commit -m "Delete MIGRATION-NOTES and FALLBACK-VENDORING after folding them into core docs"`

### Task 12: Reference sweep and build checks

- [ ] **Step 1: Full checks**

Run the checker: clean. Run the read-by-code grep: `git grep -nE 'GENERATED FILE|see docs/|docs/[A-Za-z-]+\.md' -- install.sh scripts modules pkgs justfile .github` and confirm each hit names a doc and section that exist. Run `just ci`, `just check`, `nix build .#nixosConfigurations.tariognatha.config.system.build.toplevel --no-link`: all exit 0.

- [ ] **Step 2: Commit fixes (only if any)**

`git commit -m "Fix doc references after stage 3 rewrite"`

### Task 13: Review list (user gate)

**Files:**
- Create: `docs/superpowers/doc-review.md`

- [ ] **Step 1: Write and commit the list**

Copy `review-items.md` into `docs/superpowers/doc-review.md`, each item with a checkbox and a suggested decision. `git add docs/superpowers/doc-review.md && git commit -m "Add stage 3 doc review list"`

- [ ] **Step 2: Stop for the user**

Ask the user to mark each item. This is the only planned pause.

- [ ] **Step 3: Apply decisions**

Apply each decision to the docs (and, if the user asks, re-export patch `01-fixes/0006` with the stage 2 workflow). Checker clean. `git rm docs/superpowers/doc-review.md`. `git commit -m "Apply stage 3 doc review decisions"`

### Task 14: Final review

- [ ] **Step 1: Review**

Run `/code-review` on opus over `d54882d..HEAD` (the stage 3 diff), focused on: false statements, lost rationale, broken references, assertion text.

- [ ] **Step 2: One fix round**

Apply valid findings. Checker clean, `just ci` and `just check` exit 0. `git commit -m "Apply stage 3 final review fixes"`. No further review rounds unless the user asks.

### Task 15: Close out the comment cleanup

**Files:**
- Delete: `docs/superpowers/specs/2026-11-26-comment-cleanup-design.md`, `docs/superpowers/specs/2026-11-26-comment-cleanup-stage2-design.md`, `docs/superpowers/specs/2026-11-27-comment-cleanup-stage3-design.md`, `docs/superpowers/plans/2026-11-26-comment-cleanup-stage1.md`, `docs/superpowers/plans/2026-11-26-comment-cleanup-stage2.md`, `docs/superpowers/plans/2026-11-27-comment-cleanup-stage3.md`, `docs/superpowers/handoffs/2026-11-26-comment-cleanup-remaining-stages.md`

- [ ] **Step 1: Last checker run**

Checker: clean. `git grep -n 'comment-cleanup'` outside the files above: no output (fix any hit).

- [ ] **Step 2: Delete and commit**

`git rm` the 7 files. Confirm `git ls-files docs/superpowers` prints only `docs/superpowers/handoffs/2026-11-25-jellyfin-media-server.md`. `git commit -m "Delete comment cleanup specs, plans and handoff"`

- [ ] **Step 3: Delete the scratch directory**

`rm -rf ~/.cache/comment-cleanup` (spec-approved; holds only the throwaway clone, tools and checker). Confirm it is gone.

- [ ] **Step 4: Report**

Report to the user: commits, review-list outcome, checks run. Do not merge.
