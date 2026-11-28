# Backport end4-pC fixes (issue 15, backports)

## Goal

Carry the fixes from pctrade/end4-pC since `dc2ca26` that touch code in our patched ii. Issue 15 lists them. This spec covers its Backport and Maybe sections. The Local fixes section has its own specs. Output: new patches in `patches/ii/`, exported with the workflow in `docs/II-INTEGRATION.md`.

All paths below are relative to `dots/.config/quickshell/ii/` in the `krane` branch of `~/src/dots-hyprland`. The fork uses `modules/ii/...`; our tree has the same paths, except settings pages, which live in `modules/settings/`.

## Method

The investigation compared hunks by eye. No patch was applied. Every item therefore starts with `git am -3` (or `git apply --check`) of the fork commit onto the `krane` tip, and falls back to a hand-port when that fails. Each commit message records the problem, the port and when to drop it, as in the existing series.

Work and verification happen on tariognatha: it has a discrete GPU, and the overview, region selector and thumbnails need a real session.

## Items

### Series `01-fixes` (continue numbering after `0011`)

| Fork commit | Change | Files | Port |
| --- | --- | --- | --- |
| 584cd9e | Guard `NotifTimer.onTriggered` against an already-removed notification: destroy the timer and return. | `services/Notifications.qml` | clean |
| ebeef46 | In the `lspci` fallback, pick the first non-Intel display controller, else the first; strip the space before `(rev xx)`. | `services/SystemInfo.qml` | clean, 6 lines |
| 061b321 | Look up the model id case-insensitively in `setModel`; keep the real id. | `services/Ai.qml` | offset only |
| 5f1b4b4 | Decode one frame of a video wallpaper with ffmpeg; use `[0]` for images. | `scripts/ai/gemini-categorize-wallpaper.sh` | clean |
| e3bb865 (icon hunk) | `'scheduleb'` to `'schedule'`. Only this hunk; the rest of the commit is not ported. | `modules/common/functions/NotificationUtils.qml` | one line |
| 18737b3 | Compare player position and length with `Math.abs`; use `player.isPlaying`. | `modules/ii/mediaControls/MediaControls.qml`, `services/MprisController.qml` | the `SidebarRightContent` hunk is skipped, its pattern does not exist here |
| a25766e | `mkdir -p "$(dirname "$thumb")"` before generating. | `modules/common/widgets/ThumbnailImage.qml` | hand-port as its own patch after `0001`, which rewrote the same command |
| 6de2c5f | Force `PNG:-` and `wl-copy --type image/png`. | `modules/common/utils/ScreenshotAction.qml`, `modules/ii/overlay/recorder/Recorder.qml` | hand-port; the `RegionSelector.qml` hunk is skipped if its grim line is absent |
| 18b00f2 | Mask the overview with an unscaled proxy item, and a fullscreen mask while a window is dragged. | `modules/ii/overview/Overview.qml` | hand-port; leave out the clipboard-popover `Region` |
| d6c8d5d | Accept base64 data URIs and raw paths for MPRIS album art. | `modules/ii/mediaControls/PlayerControl.qml`, optional null guards in `services/MprisController.qml` | hand-port; the other six files of the commit do not exist here |
| e3bb865 (polling) | Gate the `ResourceUsage` timer on `consumers > 0`; each widget increments on mount and decrements on destruction. | `services/ResourceUsage.qml`, `modules/ii/bar/Resources.qml`, `modules/ii/verticalBar/Resources.qml`, `modules/ii/overlay/resources/Resources.qml`, background resources widget if present | hand-port; the disk-every-10-ticks half is dropped, our tree has no `diskProc` |
| 03b134b | Lock to the nearest empty workspace instead of `2147483647 - ws`. | `modules/ii/lock/Lock.qml` | moved to the lock spec |

A patch must not change text that a `kraneIiPatches` sed matches (`property bool launchOnStartup: false`). None of these does.

### Icon picker (`05-settings`)

Fork commit 52814a6 adds an icon picker, an icon color and a custom icon folder for the left sidebar button.

- Decision: keep our `bar.topLeftIcon` key and add `bar.topLeftIconColor` and `bar.topLeftIconsPath`. The fork's `custom.*` object is not adopted: it would force a config migration in every host's `config.json` for one button.
- Port: `IconPickerGrid.qml` (new), `FileUtils.folderUrl`, the `CustomIcon.customFolder` property and a Bar settings section, about 120 lines. The `SidebarRightContent` hunk is skipped.
- Config defaults are declared the way `05-settings/0001` declares keys. The settings port gets the new Bar page rows next to the existing icon row, following `05-settings/0011`.
- Agents-tab visibility of the button (`aiChat || translator || anime`) is checked while porting.
- The patch is placed at the end of `05-settings`, or in a new directory if `git am` ordering makes that cleaner. The choice is made during the plan.

## Not doing

- 1c999a4, kitty font zoom: needs kitty remote control. Low value for the attack surface it adds.
- 91c19a4, bar clock centering: targets a `ClockWidget` structure we do not have.
- 959a5c8, Android quick panel: no reproduction in our tree. Revisit if the stale rows are seen.
- 67bff63, region selector freeze: behavior change with no observed mismatch.
- Disk polling half of e3bb865, and the other hunks of e3bb865 (WorldClock, Updates, ConfigTextArea, BackgroundConfig, RippleButton, SecondaryTabButton, WidgetCard, OverviewWindow).

## Verification

- Each patch applies on a fresh `git am -3` loop over all series, in order.
- `nixos-rebuild build` on tariognatha succeeds (`applyPatches` fails on any stale patch).
- Manual checks in a switched session: notification dismissed during its timeout does not log a TypeError; About page shows the discrete GPU; a wallpaper switch with a video wallpaper stays under normal memory; opening a new thumbnail size works; copying a screenshot pastes into a browser; overview edge windows are clickable while the overview opens; Telegram or similar player art shows; the vertical bar graphs still update; the icon picker saves and the left button changes.
- `docs/II-INTEGRATION.md` lists the new patches under their series, one line each; `docs/VERIFY.md` gets the manual checks that cannot be automated.
