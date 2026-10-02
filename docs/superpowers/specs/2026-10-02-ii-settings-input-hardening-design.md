# ii settings: input hardening design

Companion fix spec to [2026-09-27-ii-settings-design.md](2026-09-27-ii-settings-design.md).
Covers the pre-merge issues raised against untrusted/unvalidated inputs in
[2026-10-02-ii-settings-premerge.md](../handoffs/2026-10-02-ii-settings-premerge.md)
(the `Ai.qml` `set_shell_config` approval gap, the `autostart.py` crash on a
malformed entry, preset-name validation, and the template `.gitignore` gap).

File paths below are in the dots-hyprland clone's `krane` branch
(`patches/ii/05-settings/` in this repo), under
`dots/.config/quickshell/ii/`, unless marked otherwise.

## Problem

**`set_shell_config` has no approval gate**: `services/Ai.qml`'s
`handleFunctionCall` (lines 802-830) dispatches the AI's function calls.
`run_shell_command` sets `message.functionPending = true` and waits for the
user to call `approveCommand`/`rejectCommand` (lines 762-801) before
`commandExecutionProc` ever runs. `set_shell_config` has no such gate: it
calls `Config.setNestedValue(key, value)` directly, inline, the moment the
model emits the call. Every other AI-triggered write to the system goes
through a confirmation step; a config write does not, even though
`Config.setNestedValue` can reach the same `hyprland`/`monitors`/`idle` keys
the settings GUI writes under lock, bypassing the GUI entirely and with no
record the user approved it.

**`autostart.py` crashes on one malformed entry**: `scripts/hyprland/autostart.py`
(55 lines) loops over the autostart list with no per-entry `try`/`except`.
Line 32, `cmd = app.get('cmd', '').strip()`, raises `AttributeError` if `app`
is not a dict (`'str' object has no attribute 'get'`) or if `cmd` is present
but not a string (`.strip()` on a non-`str`). The `workspace` field (lines
36-39) is validated correctly — `isinstance(workspace, int) and not
isinstance(workspace, bool)`, otherwise a stderr warning and `continue` — but
`delay` (lines 41-43) is checked only with `delay < 0`, and Python's `<` on
`float('nan')` is always `False`, so a `delay` of `NaN` passes validation
unchanged. `time.sleep(delay)` at line 55 then raises `ValueError: cannot
convert float NaN to integer`-shaped error, crashing the whole script. Since
there is no per-entry guard, one bad entry anywhere in the list stops every
entry after it from autostarting, not just the bad one. `lua_str()` (lines
7-10) escapes backslash, double quote, newline, tab, and carriage return, but
not a NUL byte; a `cmd` containing one is not safely represented in the
generated Lua string literal.

**Preset names are only partly validated**: `scripts/presets.sh`'s
`SAFE_NAME_RE='^[A-Za-z0-9._ -]+$'` and `is_unsafe_name()` (lines 39,
136-138) are checked by a guard block (lines 257-266) that runs only for the
`--remove|--apply)` and `--import-zip)` actions. The `--save)` (line 270) and
`--export-zip)` (line 310) actions build file paths from the name argument
with no such check. `services/Presets.qml`'s `save()` (line 73) only replaces
whitespace with underscores (`name.replace(/\s/g, "_")`) before sending the
name to the shell script; `exportZip()` (line 119) forwards the name with no
cleanup at all. A name containing `/` or `..` reaches a shell `cp`/`zip`
command unchecked from either the QML or the shell side on these two
actions, which can write or read outside the presets directory.

**Template `.gitignore` is missing a line the real hosts have**:
`templates/host/illogical-impulse/.gitignore` does not list `presets/*.zip`;
`hosts/{tariognatha,tarmantria,taractias}/illogical-impulse/.gitignore` each
do (confirmed by diff — each real host's `.gitignore` has exactly one extra
line, `presets/*.zip`, beyond the template). A host created from the
template after this point would track preset zip exports in git until
someone notices and adds the line by hand.

## Goals

- Every AI-triggered config write goes through the same approval step as an
  AI-triggered shell command.
- A malformed autostart entry is skipped with a warning; it does not stop
  the rest of the list from starting.
- A preset name reaching a shell command or file path is restricted to the
  same safe character set on every action that accepts one, not just two of
  five.
- A new host created from the template ignores preset zip exports the same
  way the three existing hosts do.

## Non-goals

- Not changing what `set_shell_config` is allowed to write (no new
  allowlist/blacklist logic) — only gating the existing call behind
  confirmation.
- Not changing the confirm-or-revert state machine or any Displays-page
  behavior — Spec 2's scope
  ([2026-10-02-ii-settings-gui-write-paths-design.md](2026-10-02-ii-settings-gui-write-paths-design.md)).
- Not changing `krane_ii_settings.py`'s own validation (`validate_data`,
  `schema.json`) — this spec only hardens the preset-name and autostart
  scripts and the AI approval path, which sit outside that writer.

## Design

### Gate `set_shell_config` behind the existing approval machinery

`handleFunctionCall` (`services/Ai.qml:802-830`) currently has two shapes:
an immediate call (`get_shell_config`, `set_shell_config`,
`switch_to_search_mode`) and a deferred one (`run_shell_command`, via
`message.functionPending`/`approveCommand`/`rejectCommand`/
`commandExecutionProc`, lines 762-801). `set_shell_config` moves to the
deferred shape:

```qml
case "set_shell_config":
    message.functionPending = true
    message.pendingDescription = `set ${args.key} = ${JSON.stringify(args.value)}`
    message.pendingApply = () => Config.setNestedValue(args.key, args.value)
    break
```

`approveCommand` already exists to flip `functionPending` off and run the
pending action for `run_shell_command`; it gains a branch that calls
`message.pendingApply()` when that property is set, instead of assuming
every pending message is a shell command. `rejectCommand` needs no change —
it already just clears `functionPending` without running anything.
`pendingDescription` is shown in the same confirmation UI `run_shell_command`
already renders (replacing the command text with the config
description), so the approval UI is uniform: "run `<command>`" or "set
`<key>` = `<value>`", same two buttons.

This is a krane-only clone patch (`services/Ai.qml` is not an upstream
file in the sense of carrying an upstream fix yet) — marked in the patch
header: `Drop when: upstream gates set_shell_config`.

Rejected alternative: gate only the config keys that look command-shaped
(e.g. paths under `hyprland.exec`) and leave plain value keys (theme,
accent color) immediate. Rejected because the set of "command-shaped" keys
is exactly the kind of list that drifts as `schema.json` grows, and the
cost of gating everything is one extra click per AI-driven config change,
not a workflow change — gating every `set_shell_config` call is simpler and
does not need to be kept in sync with the schema.

### `autostart.py`: skip malformed entries, do not crash

Lines 30-43 gain the same shape the existing `workspace` check already
uses — validate, warn to stderr, `continue` — applied to the whole entry
and to `delay`:

```python
for app in autostart_list:
    if not isinstance(app, dict):
        print(f"autostart: skipping non-object entry: {app!r}", file=sys.stderr)
        continue
    cmd = app.get('cmd', '')
    if not isinstance(cmd, str) or not cmd.strip() or '\x00' in cmd:
        print(f"autostart: skipping entry with invalid cmd: {app!r}", file=sys.stderr)
        continue
    cmd = cmd.strip()
    workspace = app.get('workspace')
    if workspace is not None and (not isinstance(workspace, int) or isinstance(workspace, bool)):
        print(f"autostart: skipping entry with invalid workspace: {app!r}", file=sys.stderr)
        continue
    delay = app.get('delay', 0)
    if not isinstance(delay, (int, float)) or isinstance(delay, bool) or not math.isfinite(delay) or delay < 0:
        delay = 0
    ...
```

`math` joins the existing imports (already used this way in
`krane_ii_settings.py`'s own validation, same idiom). The NUL check on `cmd`
makes the "skip, do not pass to Lua" rule explicit instead of relying on
`lua_str()` to do something safe with a byte it does not escape; `lua_str()`
itself is unchanged; no entry containing a NUL reaches it after this fix.
A bad `workspace` keeps its existing skip-with-warning behavior; a bad
`delay` is clamped to `0` rather than skipping the whole entry, since a
timing-only problem on an otherwise-valid entry should not drop a real
autostart command — only `cmd` and `workspace` are "skip the entry" failures.

### Preset-name validation on every action, not just two

`scripts/presets.sh`'s guard block (currently `case "$action" in
--remove|--apply) ... esac`, lines 257-266) gains `--save` and
`--export-zip` to its case list, so all four name-bearing actions
(`--remove`, `--apply`, `--import-zip`, `--save`, `--export-zip`) are
checked by the same `is_unsafe_name()` call before the main dispatch runs.

`services/Presets.qml`'s `save()` (line 73) and `exportZip()` (line 119)
each gain a client-side check before building the shell command, using the
same character class as `SAFE_NAME_RE`:

```qml
function isUnsafeName(name) {
    return !/^[A-Za-z0-9._ -]+$/.test(name) || name.includes("..") || name.startsWith(".")
}
```

A name failing this check is rejected in the UI (same inline error pattern
`apply()`/`remove()` already use for a failed shell call) before
`presets.sh` is ever invoked, so the user gets immediate feedback instead
of a silent shell-side failure; the shell-side check in `presets.sh` is
kept regardless, since `presets.sh` can be invoked directly (not only
through the GUI) and must not trust any caller.

### Template `.gitignore` gains the missing line

`templates/host/illogical-impulse/.gitignore` gains `presets/*.zip`,
matching the line already present in all three real hosts'
`illogical-impulse/.gitignore` (confirmed identical across
`tariognatha`, `tarmantria`, `taractias` by diff against the template —
each host's file differs from the template by exactly this one line).

## Error handling

- A rejected `set_shell_config` (user clicks reject) behaves exactly like a
  rejected `run_shell_command` today: `functionPending` clears, nothing is
  written, the AI conversation continues with no further message implying
  success.
- An `autostart.py` entry skipped for `cmd`/`workspace` still lets every
  other entry in the list start, in order, with its own `delay`; the
  skipped entry's warning goes to stderr (already how `workspace` failures
  are reported) so it shows up in the service's journal without blocking
  the unit.
- A preset name rejected in `Presets.qml` never reaches `presets.sh`; a
  name that somehow does reach `presets.sh` directly (manual invocation,
  or a future caller) is still caught by the now-complete shell-side guard,
  which exits non-zero without touching the filesystem.

## Testing

- `Ai.qml`/approval: manual check — ask the assistant to change a setting,
  confirm a prompt appears before `Config.setNestedValue` runs, confirm
  rejecting it leaves the value unchanged.
- `autostart.py` unit tests: a list containing one non-dict entry, one
  entry with a non-string `cmd`, one with a NUL in `cmd`, one with
  `delay: float('nan')`, and one valid entry — assert the valid entry still
  starts and the script exits 0, with warnings on stderr for each bad entry.
- `presets.sh`/`Presets.qml`: attempt `--save`/`exportZip` with a name
  containing `/`, `..`, and a leading dot; assert each is rejected before
  any file is written, both from the GUI and from a direct `presets.sh`
  call.
- Manual: create a host from `templates/host/illogical-impulse/` and
  confirm `git status` does not show an exported preset zip as untracked.

## Docs

No `docs/II-INTEGRATION.md` or `docs/VERIFY.md` change — these are
input-validation fixes to existing documented behavior, not a change to the
persistence model or a new user-facing verification step beyond what
[2026-10-02-ii-settings-manual-test.md](../handoffs/2026-10-02-ii-settings-manual-test.md)
already covers for presets and autostart.

## Commits

Clone-side changes (`services/Ai.qml`, `scripts/hyprland/autostart.py`,
`scripts/presets.sh`, `services/Presets.qml`) land as fixups and are
re-exported to `patches/ii/05-settings/` in this repo, same convention as
Spec 2. One dotfiles commit covers the re-exported patches together with
`templates/host/illogical-impulse/.gitignore`.
