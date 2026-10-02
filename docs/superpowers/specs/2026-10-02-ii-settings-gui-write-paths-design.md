# ii settings: GUI write-path fixes design

Companion fix spec to [2026-09-27-ii-settings-design.md](2026-09-27-ii-settings-design.md).
Covers the pre-merge issues raised against the settings GUI's write paths in
[2026-10-02-ii-settings-premerge.md](../handoffs/2026-10-02-ii-settings-premerge.md)
(M3, M4, the `HyprlandConfigOption` watchdog, the ungated monitor luminance/VRR
controls, and the revert-timer countdown).

All file paths below are in the dots-hyprland clone's `krane` branch
(`patches/ii/05-settings/` in this repo), under
`dots/.config/quickshell/ii/`, unless marked otherwise.

## Problem

**M3**: `modules/settings/HyprlandConfig.qml` binds `enabled: !page.revertPending`
on exactly three controls — `monitorCanvas`, the per-monitor
`ContentSubsection`, and the bit-depth/color-management group (lines 124,
130, 231) — all inside the Displays section. The Hyprland (Layout, Input)
and Idle sections have no `revertPending` gate at all. While a monitor
`try` is pending confirm-or-revert, those other sections can still call
`KraneSettings.set(...)`, each of which takes the repo-file lock
(`krane_ii_settings.py`'s `Settings.set`) independently of the pending
`try`. A `set` that runs while a `try` is pending reads the repo file,
writes its own change, re-renders `krane_gui.lua` from that post-edit repo
state, and reloads — overwriting the live file the `try` wrote, so the
tried (not-yet-confirmed) monitor rule is lost from the live config even
though the repo file still marks it pending.

**M4**: the Displays page's spin boxes already use `onValueModified`
(scale, position X/Y, bit depth, luminance fields). The Hyprland page's spin
boxes (gaps, border size, rounding, blur passes/size, opacities, shadow
range, repeat delay/rate, idle timeouts, touchpad scroll factor — the
`onValueChanged` hits at `HyprlandConfig.qml:437` (keyboard-layout debounce,
a `Timer.restart()` so it is harmless), `468`, `481` (Input), `549`, `610`
(Idle), `700`-`802` (nine hits, Visual & Aesthetics / Autostart Apps),
`845`, `869` (Animations)) still use `onValueChanged`, which fires on every
keystroke/drag tick, not just on a committed edit. Each handler calls
`KraneSettings.set(...)`, so a drag emits one `set` (one repo-file write,
one Hyprland reload) per intermediate value.

**Watchdog gap**: `modules/common/models/hyprland/HyprlandConfigOption.qml`'s
`fetchProc` (a `Process` running `hyprctl getoption -j <key>`) has no
timeout. If Hyprland does not answer, `fetchProc.running` (aliased as
`fetching`) never returns to `false` and `loaded` never becomes `true`.
Every control bound to that option checks `fetching || !loaded` before
writing (e.g. `HyprlandConfig.qml:444`, `456`, `469`, ...), so a hung fetch
makes the control permanently discard edits with no indication to the user
of why.

**Ungated luminance/VRR-adjacent controls**: `page.monitorLocked(field)`
(`HyprlandConfig.qml:43-44`) wraps `KraneSettings.isMonitorFieldLocked` and
already gates `disabled`, `mode`, `transform`, `scale`, `position`,
`bitdepth`, and `cm` (lines 138-260). The SDR brightness/saturation and
luminance controls further down the Displays group, and the bit-depth
group's sibling controls, are not all confirmed to carry the same
`monitorLocked` gate — any monitor field that schema.json defines
(`sdrbrightness`, `sdrsaturation`, `sdr_min_luminance`, `sdr_max_luminance`,
`min_luminance`, `max_luminance`, `max_avg_luminance`) but that
`HyprlandConfig.qml` does not gate with `page.monitorLocked(<field>)` can be
set by the GUI even when Nix owns that field for the output
(`modules/home/ii-settings.nix`'s `optionalMonitorFields`/`nixMonitors`),
which the Nix-side `overlap` assertion then only catches at the next
`nixos-rebuild switch`, not live. `vrr` itself (schema.json: `int, -1..3`)
has no UI control at all in `HyprlandConfig.qml` — a latent model/writer-only
gap, not a currently-ungated control, so it needs no gating fix here, only a
note that adding a VRR control later must come with a `monitorLocked("vrr")`
gate from the start.

**Countdown not tied to the real timer**: the revert-pending `NoticeBox`
(`HyprlandConfig.qml:91-116`) keeps its own `countdown: 15` property,
reset to 15 whenever the banner becomes visible and decremented locally by
a 1-second `Timer`. It does not read the actual remaining time on
`krane-ii-settings-revert.timer`. If the settings window is closed and
reopened (or Quickshell restarts) while the server-side timer is already
partway through its 15 seconds, the banner shows a fresh 15 s that does not
match when the revert actually fires.

## Goals

- A pending `try`/boot-check revert blocks every settings write, not just
  the Displays section.
- Hyprland-page spin boxes write once per committed edit, matching the
  Displays page.
- A hung `hyprctl getoption` is visible to the user and does not leave a
  control silently inert forever.
- Every monitor field the GUI can write is gated by `monitorLocked` when
  Nix can own it.
- The revert countdown shown to the user matches the real timer.

## Non-goals

- Adding a VRR UI control (out of scope; this spec only requires that if
  and when one is added, it must ship with the same `monitorLocked` gate
  the other fields already use).
- Changing the confirm-or-revert state machine's server side
  (`krane_ii_settings.py`) beyond the `get()` addition below — see Spec 1
  ([2026-10-02-ii-settings-boot-path-design.md](2026-10-02-ii-settings-boot-path-design.md))
  for the timeout and boot-path work.

## Design

### M3: one `revertPending` rule, extended to every section

`HyprlandConfig.qml` already computes `page.revertPending`
(`KraneSettings.state.revertPending === true`, line 49). The Hyprland
section's top-level `GroupedList`/`ContentSubsection` wrapper and the Idle
section's wrapper each gain `enabled: !page.revertPending`, the same
property the Displays controls already use — one rule, applied at the
section-wrapper level so each individual control does not need its own
binding. This matches the existing Displays-section pattern: wrap the
section, not each field.

### M4: Hyprland-page spin boxes move to `onValueModified`

Every `onValueChanged` handler on a `ConfigSpinBox` in the Input, Idle,
Visual & Aesthetics/Autostart, and Animations sections becomes
`onValueModified`. `ConfigSpinBox` (the shared widget both pages use) already
forwards `valueModified` from its underlying `SpinBox`, since the Displays
page already relies on it — no widget change needed, this is a mechanical
rename at each of the thirteen call sites (`437` stays `onValueChanged`,
since it only restarts a debounce timer and firing on every keystroke is the
intended behaviour; `468`, `481`, `549`, `610`, `700`-`802`, `845`, `869`
become `onValueModified`).

### `HyprlandConfigOption` fetch watchdog

```qml
Process {
    id: fetchProc
    property list<string> baseCommand: ["hyprctl", "getoption", "-j"]
    stdout: StdioCollector {
        onStreamFinished: {
            watchdog.stop()
            ...
        }
    }
}

Timer {
    id: watchdog
    interval: 5000
    onTriggered: {
        fetchProc.running = false
        root.loaded = true
        root.available = false
    }
}

function fetch() {
    fetchProc.command = fetchProc.baseCommand.concat([root.key])
    fetchProc.running = true
    watchdog.restart()
}
```

`available` is a new `property bool` on `HyprlandConfigOption`, defaulting
`true`, set `false` only by the watchdog (and back to `true` at the start
of the next successful `fetch()`, alongside the existing `onReloaded`
handler calling `root.fetch()`). Controls add `!available` to their
disabled/label logic the same way `monitorLocked` already does — e.g.
`enabled: !optX.monitorLocked && optX.available`, label suffix `· hyprctl
did not answer` when `!available`. This gives a hung fetch a visible,
specific message instead of an inert control.

### Ungated monitor fields

Every monitor field in `schema.json`'s `monitor` object that
`HyprlandConfig.qml` exposes a control for gets `page.monitorLocked(<field>)`
on its `enabled` binding, matching the pattern already used for `disabled`,
`mode`, `transform`, `scale`, `position`, `bitdepth`, and `cm`:
`sdrbrightness`, `sdrsaturation`, `sdr_min_luminance`, `sdr_max_luminance`,
`min_luminance`, `max_luminance`, `max_avg_luminance`. `vrr` has no control
to gate; a one-line comment at the top of the Displays section notes that
any future VRR control must gate on `page.monitorLocked("vrr")` from the
start.

### Revert deadline from the real timer

`krane_ii_settings.py`'s `Settings.get()` gains a `revertDeadline` field:
UTC epoch seconds when `krane-ii-settings-revert.timer` will next fire, or
`null` when `revertPending` is false.

```python
def revert_deadline(self):
    result = subprocess.run(
        [SYSTEMCTL, "--user", "show", f"{REVERT_UNIT}.timer",
         "-p", "NextElapseUSecRealtime", "--value"],
        capture_output=True, text=True, timeout=10)
    text = result.stdout.strip()
    if result.returncode != 0 or not text or text in ("0", "n/a"):
        return None
    return int(text) / 1_000_000
```

called from `get()` only when `self.runtime.revert_timer_active()` is
true. `KraneSettings.qml`'s polling of `get()` already refreshes
`state.revertPending`; `state.revertDeadline` is added the same way. The
`NoticeBox` binds its displayed seconds to
`Math.max(0, Math.round(KraneSettings.state.revertDeadline - (Date.now() /
1000)))` and recomputes every second instead of counting down a local
integer, so it reflects the real timer across a Quickshell restart.

## Error handling

- `revert_deadline()` returning `None` (timer not active, or `systemctl
  show` itself times out/fails) leaves `revertDeadline` as `null`; the
  banner falls back to a static "reverting soon" message rather than a
  countdown, instead of showing a stale or negative number.
- `available: false` on a `HyprlandConfigOption` does not block `reset()`
  or `setValue()` outright — the user may still act — it only disables the
  control's own toggle/spin box, since the control cannot tell current
  state without a successful fetch and writing blind risks clobbering an
  unrelated value.

## Testing

- Writer unit test: fake `systemctl show ... NextElapseUSecRealtime`
  output, assert `get()`'s `revertDeadline` matches; assert `null` when the
  timer is not active and when `systemctl` fails.
- Manual/smoke: trigger a monitor `try`, confirm the Hyprland and Idle
  sections are disabled for its duration; drag a Hyprland-page spin box and
  confirm exactly one write lands in `hosts/<host>/ii-settings.json` per
  commit, not per tick (same check `docs/superpowers/handoffs/2026-10-02-ii-settings-manual-test.md`
  already runs for the Displays page, extended to the Hyprland page).
- GUI checks folded into
  [2026-10-02-ii-settings-manual-test.md](../handoffs/2026-10-02-ii-settings-manual-test.md)
  rather than a separate pass, since they need a live Hyprland session.

## Docs

No `docs/II-INTEGRATION.md` change: the persistence model itself is
unchanged, only the GUI's own gating and the `get()` output shape. A
`revertDeadline` field is a transport detail (`get()`'s JSON state used by
the GUI), not part of the on-disk persistence format `II-INTEGRATION.md`
documents.

## Commits

Clone-side changes land as fixups of the commit that introduced each file,
then the whole `05-settings` series is re-exported to
`patches/ii/05-settings/` in this repo (same convention the original spec's
"Delivery mechanism" section sets): `HyprlandConfig.qml` (M3, M4, the
monitor-field gating, the countdown binding),
`HyprlandConfigOption.qml` (the watchdog). One dotfiles commit covers the
re-exported patches together with `krane_ii_settings.py`'s `revert_deadline`
and its test.
