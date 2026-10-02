# ii settings: pre-merge issues

Issues raised against the ii settings branch during its final whole-branch
review and fix wave, grouped by the fix spec that covers them. Each spec has
the full design (code, file paths, rationale); this table is the index.
Original design: [2026-09-27-ii-settings-design.md](../specs/2026-09-27-ii-settings-design.md).

## Spec 1 — boot path

[2026-10-02-ii-settings-boot-path-design.md](../specs/2026-10-02-ii-settings-boot-path-design.md)

| Issue | Impact | Fix | Spec |
|---|---|---|---|
| D1: `activate()` can raise `FileNotFoundError` before login, caught nowhere | A GUI change made since the last switch is silently lost on a plain reboot; the shell's `\|\| true` hides the crash entirely | Fall back to a repo-relative lock file when the runtime directory doesn't exist yet | Spec 1 |
| `kraneIiHyprReload` isn't ordered after `kraneIiActivate` | The Hyprland reload that follows activation can race the GUI re-render it's supposed to pick up | Add `kraneIiActivate` to `kraneIiHyprReload`'s `entryAfter` | Spec 1 |
| M1: `KRANE_GUI_MONITORS` only emitted when a host has GUI monitor rules | Lua that reads the global (hotplug merge hooks) sees it undefined instead of empty on a host with none yet | Always emit the table, even when empty | Spec 1 |
| M2: boot-check doesn't wait for the `hyprlock` fallback | If ii's own lock IPC never comes up, the settings dialog can open while a fallback `hyprlock` still covers the screen | Also wait on `pidof hyprlock` | Spec 1 |
| No subprocess timeouts | A hung `hyprctl`/`systemctl`/`qs ipc call` blocks activation or a GUI write indefinitely | Bounded `timeout=` on every subprocess call, translated to "nothing applied" | Spec 1 |

## Spec 2 — GUI write paths

[2026-10-02-ii-settings-gui-write-paths-design.md](../specs/2026-10-02-ii-settings-gui-write-paths-design.md)

| Issue | Impact | Fix | Spec |
|---|---|---|---|
| M3: only the Displays section disables while a revert is pending | A Hyprland-page or Idle-page change during that window can overwrite the live file's tried (not-yet-confirmed) monitor rule | Extend the same `revertPending` gate to the Hyprland and Idle section wrappers | Spec 2 |
| M4: Hyprland-page spin boxes fire on every drag tick | One `set` (one repo write, one reload) per intermediate value instead of per committed edit | Switch those handlers from `onValueChanged` to `onValueModified` | Spec 2 |
| `HyprlandConfigOption`'s `hyprctl getoption` fetch has no timeout | A hung fetch leaves a control permanently inert with no indication why | Add a 5-second watchdog; surface "hyprctl did not answer" on the control | Spec 2 |
| SDR brightness/saturation and luminance fields aren't all confirmed gated by `monitorLocked` | A field Nix owns for a given output could be set live by the GUI, caught only at the next switch, not live | Add `page.monitorLocked(<field>)` to every monitor field the GUI exposes | Spec 2 |
| Revert banner's countdown is a local 15-second timer, not the real one | Reopening the settings window mid-countdown shows a fresh 15s that doesn't match when the revert actually fires | Read the real timer's deadline and count down from that | Spec 2 |

## Spec 3 — input hardening

[2026-10-02-ii-settings-input-hardening-design.md](../specs/2026-10-02-ii-settings-input-hardening-design.md)

| Issue | Impact | Fix | Spec |
|---|---|---|---|
| `Ai.qml`'s `set_shell_config` writes config with no approval step | The AI assistant can change settings with no confirmation, unlike every other AI-triggered action | Route it through the same approve/reject flow `run_shell_command` already uses | Spec 3 |
| M5: a malformed autostart entry crashes the whole list | One bad entry (hand-edited or AI-written) stops every autostart app after it from starting | Skip the bad entry with a warning; validate `delay` against NaN the same way `workspace` is already validated | Spec 3 |
| Preset save/export don't validate the preset name | A name containing `/` or `..` reaches a shell command unchecked on two of the five preset actions | Apply the existing safe-name check to every action that takes a name, client- and shell-side | Spec 3 |
| Template host `.gitignore` is missing `presets/*.zip` | A host created from the template would track exported preset ZIPs in git until someone notices | Add the line to the template, matching all three real hosts | Spec 3 |

## No spec

- **Clone commit-format slips**: two of the clone's `krane/05-settings`
  commits deviate cosmetically from the plan's commit-message format (one
  uses a `/blob/` URL where a different link form was expected; one has
  extra blank lines between fields). Cosmetic only, not reviewed against a
  spec — a rewording pass if anyone wants it tidied, not a blocker.
- **Verification gates**: a full-system `nixos-rebuild dry-build` for
  tariognatha and a `just check-new-host` run haven't been completed on real
  hardware (the test VM's limited memory reliably OOM-kills a full
  dry-build; the narrower `home.activationPackage` build was used instead
  and passed). These need to run on real hardware before merge, but they're
  verification steps, not code fixes, so there's no spec for them — see
  [2026-10-02-ii-settings-user-steps.md](2026-10-02-ii-settings-user-steps.md).

## Deferred, not blocking

A few items were looked at and judged safe to leave as-is: the clone's
ported fork pages (Quick, General, Bar, Background, Interface, Services,
About, Profile) beyond spot checks, since they sit outside the persistence
design this branch adds; `presets.sh`'s internals beyond its call shapes and
the existing import allowlist, already reviewed in depth earlier in the
branch; and whether Hyprland 0.56 keeps its Lua state across a
`reload config-only` (affects only whether M1's empty-table case is
reachable in practice) — undetermined without a live test, and harmless
either way once M1's fix lands. None of these block a merge.

## Merge criteria

- Specs 1-3 reviewed and, for whichever are approved, implemented and
  re-reviewed.
- The two verification gates above (tariognatha dry-build, `just
  check-new-host`) run clean on real hardware.
- The manual test checklist
  ([2026-10-02-ii-settings-manual-test.md](2026-10-02-ii-settings-manual-test.md))
  passes on at least one real host.
- Each switched host's `illogical-impulse/config.json` has had its privacy
  review and its own commit (see
  [2026-10-02-ii-settings-user-steps.md](2026-10-02-ii-settings-user-steps.md)).
- taractias is not required for merge — it stays on the deferred list until
  its hardware is verified, same as earlier in this branch.
