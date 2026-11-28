# Backport end4-pC fixes (issue 15, backports)

## Goal

Carry the fixes from pctrade/end4-pC since `dc2ca26` that touch code in our patched ii. Issue 15 lists them. This spec covers its Backport and Maybe sections. Lock fixes have their own spec (`2026-11-28-lock-fixes-design.md`); the volume mixer item waits for a runtime test and has no spec yet.

Output, exported with the workflow in `docs/II-INTEGRATION.md`:

- `patches/ii/09-end4pc-fixes/`: the fix backports.
- `patches/ii/10-icon-picker/`: the left sidebar icon picker.

Both are new directories after `08-bar-popouts`, built on the `krane` tip. No existing series is rebased. `11-lock` follows from the lock spec.

Paths are relative to `dots/.config/quickshell/ii/` in the `krane` branch of `~/src/dots-hyprland`. The fork's paths start at the repo root (`modules/ii/...`); settings pages live in `modules/settings/` here, in `modules/ii/settings/pages/` in the fork.

## Method

Per item: fetch the fork commit as a patch, `gh api repos/pctrade/end4-pC/commits/<sha> -H 'Accept: application/vnd.github.patch'`, and apply it with `git am --directory=dots/.config/quickshell/ii` (plus `--exclude` for files not ported). Do not use `-3`: the fork's blobs are not in the clone. When the patch fails on context, hand-port it by editing the file and committing. Each commit message records the problem, the port and when to drop it, as in the existing series. Later series already touch some of the same files (`Notifications.qml`, `SystemInfo.qml`, `Ai.qml`, `ThumbnailImage.qml`), so ports start from the tip, not from the pin.

Work and verification happen on tariognatha: it has a discrete GPU, and the overview and thumbnails need a real session.

## `09-end4pc-fixes`

| Fork commit | Change | Files | Port |
| --- | --- | --- | --- |
| 584cd9e | Guard `NotifTimer.onTriggered` against an already-removed notification: destroy the timer and return. | `services/Notifications.qml` | apply |
| ebeef46 | In the `lspci` fallback, pick the first non-Intel display controller, else the first; strip the space before `(rev xx)`. | `services/SystemInfo.qml` | apply, offset |
| 061b321 | Look up the model id case-insensitively in `setModel`; keep the real id. | `services/Ai.qml` | apply, offset |
| 5f1b4b4 | Decode one frame of a video wallpaper with ffmpeg; use `[0]` for images. | `scripts/ai/gemini-categorize-wallpaper.sh` | apply |
| e3bb865 (icon hunk) | `'scheduleb'` to `'schedule'`. Only this hunk. | `modules/common/functions/NotificationUtils.qml` | hand-port, one line |
| 18737b3 | Compare player position and length with `Math.abs`; use `player.isPlaying`. | `modules/ii/mediaControls/MediaControls.qml`, `services/MprisController.qml` | apply with `--exclude` for `SidebarRightContent.qml`, whose pattern is absent here |
| a25766e | Add `mkdir -p "$(dirname "$2")" &&` to the thumbnail one-liner that `05-settings/0022` rewrote (`$1` source, `$2` destination). | `modules/common/widgets/ThumbnailImage.qml` | hand-port; the fork hunk's context does not exist here |
| 6de2c5f | Force `PNG:-` and `wl-copy --type image/png`. | `modules/common/utils/ScreenshotAction.qml`, `modules/ii/overlay/recorder/Recorder.qml` | apply with `--exclude` for `RegionSelector.qml` (its grim line is absent) |
| 18b00f2 | While a window preview is dragged, mask the whole screen so the overview stays open (`windowDragging` plus a fullscreen `Region`). Only the drag half: our `columnLayout` has no open-animation scale, so the proxy-mask half has nothing to fix, and there is no clipboard-popover `Region`. | `modules/ii/overview/Overview.qml` | hand-port; whether a drag closes our overview is unconfirmed, check on the session first and drop the item if it does not |
| d6c8d5d | Accept base64 data URIs and raw file paths for album art; keep `curl` only for `http(s)`. Our `PlayerControl.qml` curls every art URL with no scheme check (`:63-73`). | `modules/ii/mediaControls/PlayerControl.qml`, optional null guards in `services/MprisController.qml` | reimplement; the fork commit does not touch this file, and `bar/Media.qml` and `lock/LockSurface.qml` have no art code |

None of these changes `property bool launchOnStartup: false` in `Config.qml` (sed rule: see "Backported fork fixes" in `docs/II-INTEGRATION.md`).

## `10-icon-picker`

Fork commit 52814a6: an icon picker, an icon color and a custom icon folder for the left sidebar button.

- Keys: keep `bar.topLeftIcon` (default `spark`). Add `bar.topLeftIconColor` and `bar.topLeftIconsPath`. The fork's `custom.*` object is not adopted: it would force a config migration in every host's `config.json` for one button. Defaults go next to `topLeftIcon` in `modules/common/Config.qml`; `08-bar-popouts` adds `iconPopouts` beside it, which is why this patch comes after `08`.
- Icon names: `LeftSidebarButton.qml` appends `-symbolic` to `topLeftIcon` (and special-cases `distro`). The picker stores the bare name. Built-in icons keep the `-symbolic` suffix. An icon from the custom folder uses its file name as is, with no suffix. `distro` still uses `SystemInfo.distroIcon`.
- Color: the button already colorizes. The fork's "Colorize icon" switch is dropped. `topLeftIconColor` applies always; empty means the current theme color.
- Files: `modules/common/widgets/IconPickerGrid.qml` (new), `FileUtils.folderUrl`, a `CustomIcon.customFolder` property, `LeftSidebarButton.qml`, and a new icon section in `modules/settings/BarConfig.qml` (no icon row exists today; `08-bar-popouts` also edits this file). The fork commit is 179 lines; expect about the same.
- Visibility: the button shows on `aiChatEnabled || translatorEnabled || animeEnabled`, so with all three off the Agents tab is unreachable. Add `|| Config.options.sidebar.agents.enable`.
- The right sidebar's `CustomIcon` (`SidebarRightContent.qml`, `SystemInfo.distroIcon`) is unchanged.

## Not doing

- 1c999a4, kitty font zoom: needs kitty remote control. Low value for the attack surface it adds.
- 91c19a4, bar clock centering: targets a `ClockWidget` structure we do not have.
- 959a5c8, Android quick panel: no reproduction in our tree. Revisit if the stale rows are seen.
- 67bff63, region selector freeze: behavior change with no observed mismatch.
- e3bb865 resource polling: the bar always creates its `Resources` item (`BarContent.qml`, `VerticalBarContent.qml`), so a consumer count would never reach zero. The other hunks of e3bb865 are not ported either.

## Verification

- Stage the patches (`git -C ~/.dotfiles add patches/ii`), run the apply loop from `docs/II-INTEGRATION.md` over all series, then `nixos-rebuild build` (`applyPatches` fails on any stale patch). The build does not load QML, so after switching also check the `ii` quickshell log for QML errors and TypeErrors.
- Notifications: dismiss a notification during its timeout; no TypeError.
- GPU: the About page shows the discrete GPU on tariognatha. The `lspci` fallback runs only when the `glxinfo` Intel match fails; if it does not, the item cannot be observed there and the check is the read of the code path.
- Video wallpaper: run `scripts/ai/gemini-categorize-wallpaper.sh <video>` directly and watch memory. `switchwall.sh` calls it only with `aiStyling` on and a Gemini key set.
- Thumbnails: `rm -rf ~/.cache/thumbnails/<size>`, then open the wallpaper selector; thumbnails appear.
- Screenshot: after a copy, `wl-paste --list-types` shows `image/png`.
- Overview: first, on the unpatched session, drag a window preview and see whether the overview closes; if it does not, drop 18b00f2. Otherwise it stays open with the patch.
- Media: play something with data-URI or raw-path art (for example Telegram); the art shows. Plain http art still shows.
- Icon picker: pick a built-in icon, a custom-folder icon and a color; the left button changes and the choice survives a restart; with AI, translator and anime off and agents on, the button is visible.
- `docs/II-INTEGRATION.md`: one paragraph each for `09-end4pc-fixes` and `10-icon-picker` in "Backported fork fixes", and the series list and the `01-fixes` range sentence updated. `docs/VERIFY.md`: the manual checks that cannot be automated.
