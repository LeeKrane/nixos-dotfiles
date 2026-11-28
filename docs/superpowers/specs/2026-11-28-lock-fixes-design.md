# Lock screen fixes (issue 15, local fixes)

## Goal

Fix two lock screen problems reported in pctrade/end4-pC#72 and add a main-monitor setting. Output: new series `patches/ii/11-lock/`, exported with the workflow in `docs/II-INTEGRATION.md`. `11-lock` applies last; it stacks after `05-settings`, `08-bar-popouts`, `09-end4pc-fixes` and `10-icon-picker`.

Paths are relative to `dots/.config/quickshell/ii/` in the `krane` branch.

## Problems

1. The cursor jumps to the last monitor. `modules/ii/lock/Lock.qml` focuses each monitor in turn in the lock batch and again in the restore batch, so the last monitor keeps focus, and Hyprland moves the pointer there.
2. The lock UI (password field, clock, weather) shows on every monitor. The wanted result: the prompt and widgets on one monitor, the other monitors locked and showing only the blurred wallpaper. The wallpaper and blur come from `modules/ii/background/Background.qml` on every screen; it shows through the transparent lock surface because ii sets `session_lock_xray = true`. The clock and weather widgets also come from `Background.qml` (`WidgetCanvas`), not from `LockSurface`.

## Design

### Prompt screen

One screen is the prompt screen, chosen live from `Quickshell.screens` in this order: the screen named by `lock.mainMonitor` if connected; else the monitor focused at lock time if connected; else `Quickshell.screens[0]`. Some screen always qualifies, so a bad name or a missing record never leaves the session without a prompt. The choice is re-evaluated when screens change, so unplugging the main monitor while locked moves the prompt to a remaining screen. The result is a property on `GlobalStates` (`lockPromptScreen`, a screen name).

### Where the prompt shows

- `LockScreen.qml` stays shared with the waffle lock (`modules/waffle/lock/WaffleLock.qml`). It gets a property that defaults to "every screen"; only `modules/ii/lock/Lock.qml` sets it, so the waffle lock is unchanged.
- `LockSurface` stays loaded on every screen, so the password context (`LockContext.currentText`) takes typing from any screen. Its visible content is shown only on the prompt screen. This avoids keyboard input landing on a screen with no field.
- `Background.qml` hides `WidgetCanvas` (clock, weather) on non-prompt screens while locked. Those screens show the wallpaper, blurred when `lock.blur.enable` is on and unblurred when it is off.

### Cursor and focus

`Lock.qml` records the focused monitor and the cursor position (`hyprctl cursorpos`) before the lock batch. Both batches end with one `hl.dsp.focus({monitor = <recorded>})` and a cursor move back to the recorded position. Focusing a monitor moves the pointer to its centre, so the position restore is part of the fix.

### Nearest empty workspace

Port fork commit 03b134b into `Lock.qml`. When locking, each monitor's workspace moves to the next workspace id that has no windows and is not another monitor's current workspace, instead of `2147483647 - ws`. It reads `Hyprland.workspaces.values[].toplevels`. The fork's `pushedTargets` skip logic is not ported: there is one caller. The fork's `lastProcessedLockWall` and `MaterialThemeLoader` parts are not ported either. The search skips ids that a workspace rule pins to a monitor (tariognatha pins workspace 1 to DP-2 in `hosts/tariognatha/display.nix`), so a lock never pulls focus to another monitor. The hunks do not apply as written, so this is a hand-port of about 50 lines.

### Main monitor setting

- New option `lock.mainMonitor` (string, default empty) inside the existing `lock` object in `modules/common/Config.qml`. The patch does not change the `property bool launchOnStartup: false` line next to it, which a `kraneIiPatches` sed rewrites.
- A row in the Interface page's "Lock screen" section (`modules/settings/InterfaceConfig.qml`), a `ConfigComboBox` of the connected monitor names with an empty first entry, "Focused monitor". A saved name whose monitor is unplugged is still shown.

## Not doing

- A separate Lock settings page, and other lock settings.
- Changes to the waffle lock.

## Verification

Runs on tariognatha, which has 2 monitors.

- `git am -3` over all series, then `nixos-rebuild build`.
- Lock with the pointer on each monitor: after unlock, the pointer and focus are back on the original monitor.
- With `lock.mainMonitor` set to each monitor: the prompt, clock and weather appear only there; the other monitor shows the wallpaper; typing works with the pointer on either monitor; the password unlocks.
- With an empty name and with a disconnected name: the prompt appears on the focused monitor.
- Unplug the prompt monitor while locked: the prompt moves to the remaining screen.
- Boot through lock-on-start with the name set and with it empty: a prompt appears.
- `lock.blur.enable` off: the other monitor shows the unblurred wallpaper.
- Lock with windows open on both monitors: workspaces move to empty ones and return after unlock; a workspace in use and a workspace pinned by a rule are not taken.
- Waffle lock, if enabled on a host: unchanged.
- `docs/II-INTEGRATION.md`: add `08-bar-popouts` (missing today) and `11-lock` to the series list in "Backported fork fixes", and a `### 11-lock` section. `docs/VERIFY.md`: add the checks above, next to "Autologin and lock-on-start".
