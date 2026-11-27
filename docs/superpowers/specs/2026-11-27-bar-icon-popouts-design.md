# Bar icon popouts design

Issue: [LeeKrane/nixos-dotfiles#16](https://github.com/LeeKrane/nixos-dotfiles/issues/16), from [pctrade/end4-pC#207](https://github.com/pctrade/end4-pC/issues/207).

## Goal

Clicking a status icon in the ii bar opens a small popout for that icon, instead of the right sidebar. A quick change of network, Bluetooth device, output device or volume then takes one click.

## Requirements

- Network icon opens a Wi-Fi popout. Bluetooth icon opens a Bluetooth popout. Speaker icon opens an audio output popout. Mic icon opens an audio input popout.
- Speaker and mic icons are always visible, not only when muted.
- A popout closes on a click outside it, on Esc, on a second click of the same icon, and on its Details button.
- The notification icon and empty space in the indicator area still toggle the right sidebar. Scrolling over that area still changes volume.
- Config key `bar.iconPopouts`, default `true`. It controls both the popouts and the always-visible speaker and mic icons. With it set to `false`, the bar behaves exactly as upstream.
- Horizontal, vertical and bottom bars all get the feature.
- Only left click opens a popout. Right and middle click do nothing new.

## Decisions

- Popouts use a compact look: no dialog title bar and no Done button. A small header row replaces them.
- Opening a popout starts scanning the way the sidebar dialogs do (`SidebarRightContent.qml` `ToggleDialog.onShownChanged`). The Wi-Fi popout calls `Network.enableWifi()` and `Network.rescanWifi()`. The Bluetooth popout sets `Bluetooth.defaultAdapter.enabled = true` and `discovering = true`, and sets `discovering = false` when it closes or its content switches away.
- The volume dialog content gains a mute button and a master volume slider. Every user of that content gets them: the sidebar volume dialogs, the overlay volume mixer and the new popouts.
- The Wi-Fi and Bluetooth popouts get a power switch in their header. No rescan button: opening the popout scans.
- The popout window is a `PanelWindow` that owns its own `HyprlandFocusGrab` over the popout and its bar window. It does not use the `GlobalFocusGrab` singleton, which adds the bar to the grab only while a focusable window has active focus (`services/GlobalFocusGrab.qml`). The popout takes keyboard focus, so Wi-Fi passwords and Esc work.
- No QML test setup exists, so this work skips the test-first step. Verification uses the build, a static lint where available, the runtime log, and an on-target checklist.

## Patch series

New series `patches/ii/08-bar-popouts/`, two patches. `lib/mk-host.nix` applies every `patches/ii/<dir>/*.patch` in lexical order, so the folder needs no Nix change. The patches are made as commits on the `krane` branch of `~/src/dots-hyprland`, tagged `krane/08-bar-popouts`, and exported with `git format-patch` as `docs/II-INTEGRATION.md` ("Workflow") describes. The series sorts after `05-settings`, so patch 0002 edits `modules/settings/BarConfig.qml` as `05-settings/0011` rewrote it.

### 0001 feat(volume): mute button and master slider in the volume dialog

Edits `modules/ii/sidebarRight/volumeMixer/VolumeDialogContent.qml`.

- New top row, above the app list:
  - A mute toggle button. Its icon is `volume_up`/`volume_off` for `isSink: true` and `mic`/`mic_off` for `isSink: false`. It calls `Audio.toggleMute()` or `Audio.toggleMicMute()`.
  - A `StyledSlider` with `value: Audio.sink?.audio?.volume ?? 0` (or `Audio.source`). It writes the volume back only in `onMoved`, as `QuickSliders.qml` does, so outside changes do not loop.
- The row takes over the list's `Layout.topMargin: -22`, which tucks the first element under the dialog separator. The list gets a top margin of 0, so the row does not overlap it.
- The app list and device dropdown follow, otherwise unchanged.

### 0002 feat(bar): per-icon popouts for status icons

All paths below are under `dots/.config/quickshell/ii/`.

Content extraction:
- `modules/ii/sidebarRight/wifiNetworks/WifiDialogContent.qml` (new): the scan progress bar and the network list moved out of `WifiDialog.qml`.
- `modules/ii/sidebarRight/bluetoothDevices/BluetoothDialogContent.qml` (new): the discovery progress bar and the device list moved out of `BluetoothDialog.qml`.
- Both are a `ColumnLayout` with `spacing: 16`, `Layout.fillWidth: true` and `Layout.fillHeight: true`. They keep the existing negative margins, which assume the `WindowDialog` column (16 px spacing, padding `Appearance.rounding.large`). The popout card provides the same spacing and padding.
- `WifiDialog.qml` and `BluetoothDialog.qml` keep their title, separators and Details/Done row, and embed the new content. The sidebar looks the same as before.

State, in `GlobalStates.qml`:
- `barPopout`: string, one of `""`, `network`, `bluetooth`, `speaker`, `mic`.
- `barPopoutScreen`: name of the screen whose bar opened the popout.
- `barPopoutAnchor`: the clicked icon's centre and size (`x`, `y`, `width`, `height`), mapped into its bar window, used to place the popout.

New components in `modules/ii/bar/`:
- `BarPopoutIcon.qml`: wraps one `MaterialSymbol` with a `MouseArea` and has a `popout` property holding the popout name.
  - The `MouseArea` has `acceptedButtons: Qt.LeftButton`, a pointing-hand cursor and no wheel handler. Right and middle clicks reach the `RippleButton`, whose own `MouseArea` takes all three buttons (`RippleButton.qml`), and scrolling reaches `FocusedScrollMouseArea`.
  - A left click opens the popout if a different one, or none, is open: it sets `barPopout`, `barPopoutScreen` and `barPopoutAnchor`.
  - A left click on the icon whose popout is already open clears `barPopout`. The bar window is inside the popout's grab, so the grab does not clear first and race this toggle.
  - When `Config.options.bar.iconPopouts` is `false`, the `MouseArea` is disabled and the click reaches the sidebar button as upstream. That button toggles the sidebar on release through `root.click()`.
- `BarIconPopout.qml`: one per screen, declared as a child of `barRoot` in both `modules/ii/bar/Bar.qml` and `modules/ii/verticalBar/VerticalBar.qml`.
  - A `PanelWindow` on the overlay layer, `exclusionMode: Ignore`, `WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand`. It is visible only when `barPopout` is set and `barPopoutScreen` is this screen. On open it calls `forceActiveFocus()` on its content, so Esc works without a click inside first.
  - Placement follows the edge logic of `modules/ii/bar/StyledPopup.qml` for `bar.vertical` and `bar.bottom`: the card sits next to the bar, on the side away from the screen edge. Along the bar it is centred on the icon and clamped on-screen: `left = clamp(cx - w / 2, gap, screen.width - w - gap)` for horizontal bars, and the same for `top` on vertical bars. `gap` is `Appearance.sizes.elevationMargin`.
  - The card is `WindowDialog.backgroundWidth` (350 px) wide and a fixed 600 px high, like the sidebar dialogs' `backgroundHeight`. Its `ColumnLayout` has `spacing: 16` and `Appearance.rounding.large` padding, matching `WindowDialog`.
  - The popout owns a `HyprlandFocusGrab` with `windows: [popout, barRoot]`, active while the popout is visible. When the grab clears after a click outside both windows, the popout clears `barPopout`. Esc does the same.
  - Clicks on the bar outside the four icons (workspaces, clock, the sidebar button) stay inside the grab. `BarContent.qml` and `VerticalBarContent.qml` therefore clear `barPopout` in a top-level `TapHandler` with `gesturePolicy: TapHandler.DragThreshold` that ignores taps on `BarPopoutIcon`s, so those clicks close the popout and still do their own job.
  - A `Loader` switches content:
    - `network`: header with the Wi-Fi switch and Details, then `WifiDialogContent`.
    - `bluetooth`: header with the adapter switch and Details, then `BluetoothDialogContent`.
    - `speaker`: header with Details, then `VolumeDialogContent { isSink: true }`.
    - `mic`: header with Details, then `VolumeDialogContent { isSink: false }`.
- `BarPopoutHeader.qml`: a row with a title label, an optional power `StyledSwitch` and a Details icon button.
  - Wi-Fi switch: `checked: Network.wifiEnabled`, toggled with `Network.enableWifi(checked)`.
  - Bluetooth switch: reads and writes `Bluetooth.defaultAdapter.enabled`. `BluetoothStatus.enabled` is read-only.
  - Details runs the same command as the matching sidebar dialog, then clears `barPopout`. Wi-Fi uses `apps.networkEthernet` when `Network.ethernet` is true and `apps.network` otherwise. Bluetooth uses `apps.bluetooth`. Speaker and mic use `apps.volumeMixer`.

Bar edits in `modules/ii/bar/BarContent.qml` and `modules/ii/verticalBar/VerticalBarContent.qml`:
- The network, Bluetooth, speaker and mic symbols become `BarPopoutIcon`s.
- The speaker and mic `Revealer`s use `reveal: Config.options.bar.iconPopouts || <muted>`. The speaker shows `volume_up`, or `volume_off` when muted. The mic shows `mic`, or `mic_off` when muted.
- The notification icon, the outer `FocusedScrollMouseArea` and the sidebar button stay unchanged.

Config and settings:
- `modules/common/Config.qml`: `property bool iconPopouts: true` in the `bar` object. Do not touch the `property bool launchOnStartup: false` line: the `kraneIiPatches` sed matches it.
- `modules/settings/BarConfig.qml`: a `ConfigSwitch` for `bar.iconPopouts`.
- No Nix option. ii writes its whole options tree to `config.json`, so the `Config.qml` default is enough.

## Behaviour

- Only one popout is open at any time. Clicking another icon swaps the content and moves the popout.
- Opening a popout sets `GlobalStates.sidebarRightOpen = false`.
- These events clear `barPopout`:
  - Esc.
  - The focus grab clearing after a click outside.
  - A second click on the open popout's icon.
  - Details.
  - The right sidebar opening.
  - `bar.iconPopouts` changing to `false`.
  - The Bluetooth adapter disappearing while the Bluetooth popout is open.
  - The screen locking (`GlobalStates.screenLocked`) or the bar closing (`barOpen` false). Both unload the bar's `LazyLoader` (`Bar.qml`, `VerticalBar.qml`), and without this the popout would reopen after unlock.
  - A click on the bar outside the four icons.
- Bindings to `Audio`, `Network` and `BluetoothStatus` update the content live. Scrolling over the bar changes volume while the speaker popout is open, and its slider follows.
- No new error handling. Wi-Fi password prompts, failed connections and pairing errors come from the existing `WifiNetworkItem` and `BluetoothDeviceItem`. A missing `apps.*` command fails as it does in the sidebar.

## Documentation

- `docs/II-INTEGRATION.md`: new `### 08-bar-popouts` subsection describing the series, in the style of the existing series subsections.
- `docs/VERIFY.md`: the on-target checklist below.

## Verification

- Build the host's `dots-hyprland-patched` derivation with `nix build`, then run `just check`. A series conflict fails the build.
- Run `qmllint` from the Quickshell package on every new or changed QML file, if the package ships it.
- Live-reload ii from the patched tree. `qs log -c ii` shows no new warnings or errors.
- On-target checklist:
  - Each of the four icons opens its popout next to the icon, on horizontal, vertical and bottom bars.
  - Click outside, Esc, a second click on the icon and Details each close the popout.
  - Typing a Wi-Fi password in the popout works.
  - The Wi-Fi switch, Bluetooth switch, mute buttons and sliders work. Scrolling over the bar moves the speaker popout's slider.
  - The notification icon and empty space still toggle the sidebar.
  - With `bar.iconPopouts` off, the speaker and mic icons appear only when muted, and every click opens the sidebar.
  - The sidebar volume dialogs and the overlay volume mixer show the new mute button and slider. Nothing else in them changes.
