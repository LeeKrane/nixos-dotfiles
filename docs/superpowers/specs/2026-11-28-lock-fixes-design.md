# Lock screen fixes (issue 15, local fixes)

## Goal

Fix two lock screen problems reported in pctrade/end4-pC#72 and add a main-monitor setting. Output: new series `patches/ii/09-lock/`, exported with the workflow in `docs/II-INTEGRATION.md`.

Paths are relative to `dots/.config/quickshell/ii/` in the `krane` branch.

## Problems

1. The cursor jumps to the last monitor. `modules/ii/lock/Lock.qml` focuses each monitor in turn in the lock batch and again in the restore batch, so the last monitor keeps focus and the pointer warps there. Cause verified by reading the code.
2. The lock UI appears on every monitor. The reporter wants it on one monitor, with the others locked but showing no UI. In our tree `modules/common/panels/lock/LockScreen.qml` creates one `LockSurface` per screen. Why the reporter saw blank monitors is not established; it is not needed to implement the target behavior.

## Design

### Cursor and focus

`Lock.qml` records the focused monitor before the lock batch. Both batches (lock and restore) end with one `hl.dsp.focus({monitor = <recorded>})`. This keeps the pointer where it was and, as far as the session-lock protocol allows, gives keyboard focus to the original monitor. Verify keyboard input reaches the password field on the main monitor.

### Nearest empty workspace

Port fork commit 03b134b into the same file. When locking, each monitor's workspace moves to the next workspace id that has no windows and is not another monitor's current workspace, instead of `2147483647 - ws`. The push is skipped when targets are unchanged, and the state is cleared on restore. It reads `Hyprland.workspaces.values[].toplevels`. The bar may briefly show a low-numbered real workspace during the lock. The fork's `lastProcessedLockWall` and `MaterialThemeLoader` parts are not ported. The hunks do not apply as written, so this is a hand-port of about 50 lines.

### Main monitor setting

- New option `lock.mainMonitor` (string, default empty) in `modules/common/Config.qml`, declared like `05-settings/0001`. A row in the settings app on the Lock page picks it from the connected monitors, by name (for example `DP-1`).
- In the `LockScreen.qml` loader, the full `LockSurface` (clock, password field) is active only on the screen whose name equals `lock.mainMonitor`.
- Every other screen shows the blurred wallpaper and nothing else. It still holds the session-lock surface, so the session stays locked and no input reaches it.
- Fallback: when `lock.mainMonitor` is empty, or names a monitor that is not connected, the monitor that was focused at lock time is used. A bad name must never leave the session with no password prompt.

## Not doing

- Other settings on the lock page.
- The waffle lock (`modules/waffle/lock/WaffleLock.qml`).

## Verification

Runs on tariognatha, which has 2 monitors.

- `git am -3` over all series, then `nixos-rebuild build`.
- Lock with the pointer on each monitor: the pointer stays put; after unlock, focus returns to the original monitor.
- With `lock.mainMonitor` set to each monitor: the prompt appears only there; the other monitor shows the blurred wallpaper; typing the password unlocks.
- With an empty name and with a disconnected name: the prompt appears on the focused monitor.
- Lock while windows are open on both monitors: workspaces move to empty ones and return after unlock; a third workspace in use is not taken.
- Hotplug a monitor while locked: it does not expose the session.
- `docs/II-INTEGRATION.md` gets a `### 09-lock` section; `docs/VERIFY.md` gets the checks above.
