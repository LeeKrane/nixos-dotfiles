# Bar Icon Popouts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clicking the network, Bluetooth, speaker or mic icon in the ii bar opens a per-icon popout instead of the right sidebar.

**Architecture:** A new patch series `patches/ii/08-bar-popouts/` (two patches) against ii, built as commits on the `krane` branch of `~/src/dots-hyprland`. Patch 0001 adds a mute button and master slider to the shared volume dialog content. Patch 0002 extracts Wi-Fi and Bluetooth dialog content, adds `GlobalStates` popout state, a click-target icon component and one popout `PanelWindow` per screen with its own `HyprlandFocusGrab`.

**Tech Stack:** QML (Quickshell, ii shell), `git format-patch`, Nix (`nixpkgs.applyPatches` via `lib/mk-host.nix`).

**Spec:** `docs/superpowers/specs/2026-11-27-bar-icon-popouts-design.md`

## Global Constraints

- Edits to ii live only in `~/src/dots-hyprland` branch `krane`; the exported `.patch` files in `patches/ii/08-bar-popouts/` are the deliverable. No Nix change.
- All QML paths are under `dots/.config/quickshell/ii/` (written `$II` below; `II=~/src/dots-hyprland/dots/.config/quickshell/ii`).
- Config key `bar.iconPopouts`, default `true`. With `false` the bar behaves exactly as upstream.
- Do not touch the line `property bool launchOnStartup: false` in `modules/common/Config.qml` (the `kraneIiPatches` sed matches it).
- Popout card: `WindowDialog.backgroundWidth` (350 px) wide, fixed 600 px high, `ColumnLayout` `spacing: 16`, padding `Appearance.rounding.large`. `gap` is `Appearance.sizes.elevationMargin`.
- Only left click opens a popout. Notification icon and empty indicator space still toggle the right sidebar. Scroll over the indicator area still changes volume.
- Popout window owns its own `HyprlandFocusGrab` (`windows: [popout, barRoot]`); it must not use `GlobalFocusGrab`.
- Exactly two patches: `0001-feat(volume)...` and `0002-feat(bar)...`.
- Repo rules: no code comments (see `~/.claude/CLAUDE.md`), commit subject only, no Claude attribution, work on `main` in `~/.dotfiles`, no push.
- No QML test harness exists; the test-first step does not apply. Verification is build, `qmllint` if shipped, runtime log, and driven checks the agent runs on the live desktop (Task 4 step 7). A human checklist is the last step before cleanup (Task 6).

## Review Focus

- Wi-Fi password typing inside the popout: keyboard focus must reach the `TextField` (card takes `OnDemand` focus). Esc-closes assertion (Task 4 step 7.3) proves focus reaches the card; typing itself is in the Task 6 human checklist.
- Second click on the open icon must close, not close-then-reopen (grab race). Bar window is in the grab; pinned in Task 3 step 6 and Task 4 step 7 assertions 1-2.
- Screen lock / bar close while a popout is open: popout must not reappear after unlock. Pinned by `Connections` in Task 3; the Task 6 human checklist covers it (locking is not driven).
- Bluetooth adapter unplugged while popout open: popout closes, no null-deref in log. Task 6 human checklist; the Task 4 log check covers the rest.
- `bar.iconPopouts` toggled off while a popout is open: closes, bar reverts to sidebar clicks. Pinned by Task 4 step 7.12.

---

### Task 1: Patch 0001 — mute button and master slider in VolumeDialogContent

**Files:**
- Modify: `$II/modules/ii/sidebarRight/volumeMixer/VolumeDialogContent.qml`

**Interfaces:**
- Consumes: `Audio.toggleMute()`, `Audio.toggleMicMute()`, `Audio.sink`, `Audio.source` (services/Audio.qml).
- Produces: `VolumeDialogContent { isSink }` now has a top row (mute button + slider). Task 3's popout embeds it.

- [ ] **Step 1: Prepare the clone**

```sh
cd ~/src/dots-hyprland
git status --short
git log --oneline -1
git tag -l 'krane/*'
```
Expected: clean tree, branch `krane`, tags `krane/01-fixes` … `krane/07-idle`. If the tree is dirty or the branch is missing, run the "Workflow" apply block in `docs/II-INTEGRATION.md` first.

- [ ] **Step 2: Add the top row**

In `VolumeDialogContent.qml`, insert this as the first child of the root `ColumnLayout`, before `DialogSectionListView`:

```qml
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: -22
        spacing: 8

        RippleButton {
            id: muteButton
            readonly property bool muted: (root.isSink ? Audio.sink?.audio?.muted : Audio.source?.audio?.muted) ?? false
            implicitWidth: 40
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            onClicked: root.isSink ? Audio.toggleMute() : Audio.toggleMicMute()

            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer1
                text: root.isSink ? (muteButton.muted ? "volume_off" : "volume_up") : (muteButton.muted ? "mic_off" : "mic")
            }
        }

        StyledSlider {
            Layout.fillWidth: true
            configuration: StyledSlider.Configuration.M
            value: (root.isSink ? Audio.sink?.audio?.volume : Audio.source?.audio?.volume) ?? 0
            onMoved: {
                const node = root.isSink ? Audio.sink : Audio.source;
                if (node?.audio) node.audio.volume = value;
            }
        }
    }
```

- [ ] **Step 3: Zero the list's top margin**

In the `DialogSectionListView` component at the bottom of the file change `Layout.topMargin: -22` to `Layout.topMargin: 0`.

- [ ] **Step 4: Lint**

```sh
II=~/src/dots-hyprland/dots/.config/quickshell/ii
command -v qmllint || ls "$(dirname "$(readlink -f "$(command -v qs)")")" | grep -i lint
qmllint "$II/modules/ii/sidebarRight/volumeMixer/VolumeDialogContent.qml" 2>&1 | tail -20
```
Expected: no new errors (unresolved-import warnings for `qs.*` are normal). If no `qmllint` ships, note it and rely on Task 4.

- [ ] **Step 5: Commit in the clone**

```sh
cd ~/src/dots-hyprland
git add -A
git commit -m "feat(volume): mute button and master slider in the volume dialog"
```

---

### Task 2: Extract Wi-Fi and Bluetooth dialog content

**Files:**
- Create: `$II/modules/ii/sidebarRight/wifiNetworks/WifiDialogContent.qml`
- Create: `$II/modules/ii/sidebarRight/bluetoothDevices/BluetoothDialogContent.qml`
- Modify: `$II/modules/ii/sidebarRight/wifiNetworks/WifiDialog.qml`
- Modify: `$II/modules/ii/sidebarRight/bluetoothDevices/BluetoothDialog.qml`

**Interfaces:**
- Produces: `WifiDialogContent {}` and `BluetoothDialogContent {}`, each a `ColumnLayout` (`spacing: 16`, fills width and height). Task 3 embeds both.

- [ ] **Step 1: Create `WifiDialogContent.qml`**

```qml
import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    spacing: 16
    Layout.fillWidth: true
    Layout.fillHeight: true

    WindowDialogSeparator {
        visible: !Network.wifiScanning
    }
    StyledIndeterminateProgressBar {
        visible: Network.wifiScanning
        Layout.fillWidth: true
        Layout.topMargin: -8
        Layout.bottomMargin: -8
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large
    }
    ListView {
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.topMargin: -15
        Layout.bottomMargin: -16
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large

        clip: true
        spacing: 0

        model: ScriptModel {
            values: Network.friendlyWifiNetworks
        }
        delegate: WifiNetworkItem {
            required property WifiAccessPoint modelData
            wifiNetwork: modelData
            width: ListView.view.width
        }
    }
}
```
Add `import Quickshell` (for `ScriptModel`), as `WifiDialog.qml` has it.

- [ ] **Step 2: Shrink `WifiDialog.qml`**

Replace everything between `WindowDialogTitle { … }` and the final `WindowDialogSeparator {}` (the first separator, progress bar and `ListView`) with `WifiDialogContent {}`. Keep the title, the trailing separator and the `WindowDialogButtonRow` unchanged.

- [ ] **Step 3: Create `BluetoothDialogContent.qml`**

Same shape: root `ColumnLayout { spacing: 16; Layout.fillWidth: true; Layout.fillHeight: true }` holding the first `WindowDialogSeparator`, the `StyledIndeterminateProgressBar` and the `StyledListView` moved verbatim from `BluetoothDialog.qml`. Imports needed: `qs`, `qs.services`, `qs.modules.common`, `qs.modules.common.widgets`, `QtQuick`, `QtQuick.Layouts`, `Quickshell`, `Quickshell.Bluetooth`.

- [ ] **Step 4: Shrink `BluetoothDialog.qml`**

Replace the same span (first separator through the `StyledListView`) with `BluetoothDialogContent {}`.

- [ ] **Step 5: Lint and diff check**

```sh
cd ~/src/dots-hyprland
II=dots/.config/quickshell/ii
qmllint $II/modules/ii/sidebarRight/wifiNetworks/*.qml $II/modules/ii/sidebarRight/bluetoothDevices/*.qml 2>&1 | tail -20
git diff --stat
```
Expected: no new errors; the two dialogs lose roughly the lines the new files gain.

- [ ] **Step 6: WIP commit in the clone**

```sh
git add -A && git commit -m "wip(bar): extract wifi and bluetooth dialog content"
```
Task 5 squashes this and Tasks 3-4 into patch 0002.

---

### Task 3: State, config, settings and popout components

**Files:**
- Modify: `$II/GlobalStates.qml`
- Modify: `$II/modules/common/Config.qml`
- Modify: `$II/modules/settings/BarConfig.qml`
- Create: `$II/modules/ii/bar/BarPopoutIcon.qml`
- Create: `$II/modules/ii/bar/BarPopoutHeader.qml`
- Create: `$II/modules/ii/bar/BarIconPopout.qml`

**Interfaces:**
- Produces:
  - `GlobalStates.barPopout: string` (`""|"network"|"bluetooth"|"speaker"|"mic"`), `GlobalStates.barPopoutScreen: string`, `GlobalStates.barPopoutAnchor: var` (`{x, y, width, height}` in bar-window coordinates).
  - `BarPopoutIcon { popout: string; text: string; color: color; iconSize: real }` — a `MaterialSymbol`-based click target.
  - `BarIconPopout { barWindow: QsWindow }` — one per screen; `barWindow` is the bar's `PanelWindow` (`barRoot`).
  - `BarPopoutHeader { title: string; showSwitch: bool; switchChecked: bool; signal switched(bool); signal detailsClicked() }`.
  - `Config.options.bar.iconPopouts: bool` (default true).

- [ ] **Step 1: Add state**

In `GlobalStates.qml` add after `property bool barOpen: true`:

```qml
    property string barPopout: ""
    property string barPopoutScreen: ""
    property var barPopoutAnchor: ({ x: 0, y: 0, width: 0, height: 0 })
```
and inside the existing `onSidebarRightOpenChanged` handler add, as the first statement:
```qml
        if (GlobalStates.sidebarRightOpen) GlobalStates.barPopout = "";
```
Add a handler that clears on lock and bar close:
```qml
    onScreenLockedChanged: if (screenLocked) barPopout = ""
    onBarOpenChanged: if (!barOpen) barPopout = ""
```

- [ ] **Step 2: Add config key and settings switch**

In `Config.qml`, inside the `bar` `JsonObject`, add next to the other `bool` properties (not near `launchOnStartup`):
```qml
        property bool iconPopouts: true
```
In `BarConfig.qml` add, in the same `ConfigRow { uniform: true }` pattern right after the "Show Background" switch row:
```qml
                ConfigSwitch {
                    buttonIcon: "web_asset"
                    text: Translation.tr("Icon popouts")
                    checked: Config.options.bar.iconPopouts
                    onCheckedChanged: { Config.options.bar.iconPopouts = checked; }
                }
```
Add a handler clearing the popout when disabled, in `GlobalStates.qml`:
```qml
    Connections {
        target: Config.options.bar
        function onIconPopoutsChanged() {
            if (!Config.options.bar.iconPopouts) root.barPopout = "";
        }
    }
```

- [ ] **Step 3: Create `BarPopoutIcon.qml`**

```qml
import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

MaterialSymbol {
    id: root
    required property string popout
    iconSize: Appearance.font.pixelSize.larger

    MouseArea {
        anchors.fill: parent
        anchors.margins: -4
        enabled: Config.options.bar.iconPopouts
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (GlobalStates.barPopout === root.popout) {
                GlobalStates.barPopout = "";
                return;
            }
            const win = root.QsWindow.window;
            const p = root.mapToItem(null, 0, 0);
            GlobalStates.barPopoutScreen = win.screen.name;
            GlobalStates.barPopoutAnchor = { x: p.x, y: p.y, width: root.width, height: root.height };
            GlobalStates.sidebarRightOpen = false;
            GlobalStates.barPopout = root.popout;
        }
    }
}
```
`root.QsWindow.window` is the bar window; `mapToItem(null, …)` maps into its content item. If `MaterialSymbol` has no `QsWindow` attached type here, use `QsWindow.window` via `import Quickshell` exactly as `StyledPopup.qml` uses `root.QsWindow`.

- [ ] **Step 4: Create `BarPopoutHeader.qml`**

```qml
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    property string title
    property bool showSwitch: false
    property bool switchChecked: false
    signal switched(bool checked)
    signal detailsClicked()

    Layout.fillWidth: true
    spacing: 8

    StyledText {
        Layout.fillWidth: true
        text: root.title
        font.pixelSize: Appearance.font.pixelSize.larger
        color: Appearance.colors.colOnSurfaceVariant
    }
    StyledSwitch {
        visible: root.showSwitch
        checked: root.switchChecked
        onClicked: root.switched(!root.switchChecked)
    }
    DialogButton {
        buttonText: Translation.tr("Details")
        onClicked: root.detailsClicked()
    }
}
```
Verify `DialogButton` and `StyledText` resolve from `qs.modules.common.widgets` (`rg -l "component DialogButton\|^DialogButton\|RippleButton" $II/modules/common/widgets | head`); adjust imports if `DialogButton` lives elsewhere.

- [ ] **Step 5: Create `BarIconPopout.qml`**

```qml
import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.wifiNetworks
import qs.modules.ii.sidebarRight.bluetoothDevices
import qs.modules.ii.sidebarRight.volumeMixer
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Wayland

Scope {
    id: root
    required property var barWindow
    readonly property string screenName: barWindow.screen.name
    readonly property bool open: GlobalStates.barPopout !== "" && GlobalStates.barPopoutScreen === screenName
    readonly property real gap: Appearance.sizes.elevationMargin
    readonly property bool vertical: Config.options.bar.vertical
    readonly property bool atBottomOrRight: Config.options.bar.bottom
    readonly property var anchorRect: GlobalStates.barPopoutAnchor
    readonly property real cardWidth: 350
    readonly property real cardHeight: 600

    function close() { GlobalStates.barPopout = ""; }
    function openDetails(command) {
        Quickshell.execDetached(["bash", "-c", command]);
        close();
    }

    onOpenChanged: {
        if (GlobalStates.barPopout !== "bluetooth" && Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = false;
    }

    Connections {
        target: GlobalStates
        function onBarPopoutChanged() {
            const p = GlobalStates.barPopout;
            if (!root.open) return;
            if (p === "network") {
                Network.enableWifi();
                Network.rescanWifi();
            }
            if (p === "bluetooth" && Bluetooth.defaultAdapter) {
                Bluetooth.defaultAdapter.enabled = true;
                Bluetooth.defaultAdapter.discovering = true;
            } else if (Bluetooth.defaultAdapter) {
                Bluetooth.defaultAdapter.discovering = false;
            }
        }
    }

    Connections {
        target: Bluetooth
        function onDefaultAdapterChanged() {
            if (!Bluetooth.defaultAdapter && GlobalStates.barPopout === "bluetooth") root.close();
        }
    }

    LazyLoader {
        active: root.open

        PanelWindow {
            id: popup
            screen: root.barWindow.screen
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:barPopout"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            anchors { top: true; bottom: true; left: true; right: true }
            mask: Region { item: card }

            HyprlandFocusGrab {
                windows: [popup, root.barWindow]
                active: popup.visible
                onCleared: root.close()
            }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.close()
                Component.onCompleted: forceActiveFocus()

                StyledRectangularShadow { target: card }

                Rectangle {
                    id: card
                    width: root.cardWidth
                    height: root.cardHeight
                    radius: Appearance.rounding.windowRounding
                    color: Appearance.m3colors.m3surfaceContainerHigh

                    readonly property real cx: root.anchorRect.x + root.anchorRect.width / 2
                    readonly property real cy: root.anchorRect.y + root.anchorRect.height / 2
                    readonly property real barSize: root.vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight

                    x: root.vertical
                        ? (root.atBottomOrRight ? popup.width - barSize - width - root.gap : barSize + root.gap)
                        : Math.max(root.gap, Math.min(cx - width / 2, popup.width - width - root.gap))
                    y: root.vertical
                        ? Math.max(root.gap, Math.min(cy - height / 2, popup.height - height - root.gap))
                        : (root.atBottomOrRight ? popup.height - barSize - height - root.gap : barSize + root.gap)

                    ColumnLayout {
                        anchors {
                            fill: parent
                            margins: Appearance.rounding.large
                        }
                        spacing: 16

                        Loader {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            sourceComponent: ({
                                network: networkComp,
                                bluetooth: bluetoothComp,
                                speaker: speakerComp,
                                mic: micComp
                            })[GlobalStates.barPopout]
                        }
                    }
                }
            }
        }
    }

    Component {
        id: networkComp
        ColumnLayout {
            spacing: 16
            BarPopoutHeader {
                title: Translation.tr("Wi-Fi")
                showSwitch: true
                switchChecked: Network.wifiEnabled
                onSwitched: checked => Network.enableWifi(checked)
                onDetailsClicked: root.openDetails(Network.ethernet ? Config.options.apps.networkEthernet : Config.options.apps.network)
            }
            WifiDialogContent {}
        }
    }
    Component {
        id: bluetoothComp
        ColumnLayout {
            spacing: 16
            BarPopoutHeader {
                title: Translation.tr("Bluetooth")
                showSwitch: true
                switchChecked: Bluetooth.defaultAdapter?.enabled ?? false
                onSwitched: checked => { if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = checked; }
                onDetailsClicked: root.openDetails(Config.options.apps.bluetooth)
            }
            BluetoothDialogContent {}
        }
    }
    Component {
        id: speakerComp
        ColumnLayout {
            spacing: 16
            BarPopoutHeader {
                title: Translation.tr("Audio output")
                onDetailsClicked: root.openDetails(Config.options.apps.volumeMixer)
            }
            VolumeDialogContent { isSink: true }
        }
    }
    Component {
        id: micComp
        ColumnLayout {
            spacing: 16
            BarPopoutHeader {
                title: Translation.tr("Audio input")
                onDetailsClicked: root.openDetails(Config.options.apps.volumeMixer)
            }
            VolumeDialogContent { isSink: false }
        }
    }
}
```
Check these names against the tree before the first run, and fix to what exists (one `rg` each): `Appearance.rounding.windowRounding`, `Appearance.m3colors.m3surfaceContainerHigh`, `Appearance.sizes.verticalBarWidth`, `StyledRectangularShadow`, `Network.wifiEnabled`, `Config.options.apps.volumeMixer`, and the QML module paths of the three dialog-content directories (`qmldir`-less dirs import by relative path; if the other `modules/ii/*` files import siblings by directory, mirror them).

- [ ] **Step 6: Lint**

```sh
cd ~/src/dots-hyprland
qmllint dots/.config/quickshell/ii/modules/ii/bar/BarPopout*.qml dots/.config/quickshell/ii/modules/ii/bar/BarIconPopout.qml dots/.config/quickshell/ii/GlobalStates.qml 2>&1 | tail -30
```
Expected: no errors beyond unresolved-import noise.

- [ ] **Step 7: WIP commit**

```sh
git add -A && git commit -m "wip(bar): popout state, config and components"
```

---

### Task 4: Wire the bars, then verify on target

**Files:**
- Modify: `$II/modules/ii/bar/Bar.qml`
- Modify: `$II/modules/ii/verticalBar/VerticalBar.qml`
- Modify: `$II/modules/ii/bar/BarContent.qml`
- Modify: `$II/modules/ii/verticalBar/VerticalBarContent.qml`

**Interfaces:**
- Consumes: everything Task 3 produces.

- [ ] **Step 1: Declare the popout per screen**

In `Bar.qml`, inside `PanelWindow { id: barRoot … }` after the `Component.onDestruction` block add:
```qml
                BarIconPopout {
                    barWindow: barRoot
                }
```
Do the same in `VerticalBar.qml` (its window id is also `barRoot`; confirm with `rg "id: barRoot" $II/modules/ii/verticalBar/VerticalBar.qml`).

- [ ] **Step 2: Horizontal bar icons**

In `BarContent.qml` (`indicatorsRowLayout`):
- Speaker `Revealer`: `reveal: Config.options.bar.iconPopouts || (Audio.sink?.audio?.muted ?? false)`; its symbol becomes `BarPopoutIcon { popout: "speaker"; text: (Audio.sink?.audio?.muted ?? false) ? "volume_off" : "volume_up"; color: rightSidebarButton.colText }`.
- Mic `Revealer`: same with `Audio.source`, `popout: "mic"`, `mic_off`/`mic`.
- Network `MaterialSymbol` → `BarPopoutIcon { popout: "network"; text: Network.materialSymbol; color: rightSidebarButton.colText }`.
- Bluetooth `MaterialSymbol` → `BarPopoutIcon { popout: "bluetooth"; …same props and `visible`/`Layout.leftMargin`… }`.

- [ ] **Step 3: Vertical bar icons**

Same four replacements in `VerticalBarContent.qml` (`indicatorsColumnLayout`), keeping its `vertical: true` revealers and `Layout.topMargin`/`bottomMargin` lines.

- [ ] **Step 4: Close on a bar click outside the icons**

In both `BarContent.qml` and `VerticalBarContent.qml`, add as a top-level child of the root item:
```qml
    TapHandler {
        gesturePolicy: TapHandler.DragThreshold
        onTapped: GlobalStates.barPopout = ""
    }
```
In `BarPopoutIcon.qml` give the `MouseArea` `preventStealing: true` and `onPressed: mouse => mouse.accepted = true`, so a tap on an icon never reaches this handler. Confirm on target (step 7): a click on an icon toggles its popout and does not close-then-reopen it.

- [ ] **Step 5: Lint, then build the host**

```sh
cd ~/src/dots-hyprland
qmllint dots/.config/quickshell/ii/modules/ii/bar/*.qml dots/.config/quickshell/ii/modules/ii/verticalBar/*.qml 2>&1 | tail -30
git add -A && git commit -m "wip(bar): wire popouts into both bars"
```

- [ ] **Step 6: Live reload and tool check**

```sh
command -v hyprctl grim ydotool wpctl jq || echo "MISSING TOOL"
pgrep -a ydotoold || echo "ydotoold not running"
cd ~/src/dots-hyprland/dots/.config/quickshell && qs -p ii -d
qs log -c ii | tail -40
```
Expected: no new warnings or errors. Missing tools: add them to a throwaway shell with `nix shell nixpkgs#grim nixpkgs#ydotool nixpkgs#wl-clipboard` (do not change the dotfiles); if `ydotoold` is not running, start it from that shell. If input injection cannot work at all, report that and stop; do not skip the checks. Fix any QML errors before moving on, amending the last WIP commit.

- [ ] **Step 7: Driven verification (agent runs it, no human input)**

The agent drives the live desktop. Save state first and restore it at the end, even on failure:
```sh
CFG=~/.config/illogical-impulse/config.json
cp "$CFG" /tmp/ii-config.bak
OUT0=$(wpctl get-volume @DEFAULT_AUDIO_SINK@); MUTE0=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@)
```
Helpers (define once in the shell session):
```sh
popout_open() { hyprctl layers -j | jq -e '[.. | objects | select(.namespace? == "quickshell:barPopout")] | length > 0' >/dev/null; }
shot() { grim -o "$(hyprctl monitors -j | jq -r '.[0].name')" "/tmp/ii-$1.png"; }
click() { hyprctl dispatch movecursor "$1" "$2"; sleep 0.2; ydotool click 0xC0; sleep 0.5; }
key_esc() { ydotool key 1:1 1:0; sleep 0.5; }
```
Locate the four icons: take `shot bar`, `Read` the PNG, and note each icon's centre (x, y) in layout coordinates, using `hyprctl monitors -j` for scale and offset. Repeat the whole sequence below for three bar layouts, switching by editing `CFG` with `jq` (`bar.vertical`, `bar.bottom`; ii reloads the file live): horizontal top, horizontal bottom, vertical. Re-locate icons after each switch.

For each layout and each of the four icons, assert and fail the task on any miss:
1. `click` the icon; `popout_open` is true; `shot` and `Read` it: the card sits next to the bar, fully on screen, beside the clicked icon.
2. `click` the same icon again; `popout_open` is false (closes, does not reopen).
3. Open, then `key_esc`; `popout_open` is false (proves keyboard focus reached the card).
4. Open, then `click` empty desktop space far from the bar; `popout_open` is false.
5. Open, then `click` a different icon; `popout_open` is true and the screenshot shows the other content.
6. Open, then `click` a bar spot outside the four icons (clock or workspaces); `popout_open` is false.
7. Open the speaker popout, `ydotool mousemove --wheel -- 0 -1` over the indicator area, and compare `wpctl get-volume @DEFAULT_AUDIO_SINK@` before and after: volume moved, the card stays open and its slider follows (screenshot).
8. Speaker and mic popouts: `click` the mute button; `wpctl get-volume` shows `[MUTED]`; `click` again to unmute. `click` the slider at about 30 % of its width; `wpctl get-volume` is within 0.05 of 0.30 (the slider does not fight the change).
9. Network and Bluetooth popouts: screenshot shows the list and the header switch. Do not toggle the switches (the session could lose its network).
10. Details: with `apps.volumeMixer` temporarily set to `touch /tmp/ii-details-ok` in `CFG`, open the speaker popout, `click` Details; the file exists and `popout_open` is false. Restore the key after.
11. Sidebar: `click` an empty indicator-area spot and the notification icon area; `GlobalStates.sidebarRightOpen` effects show in a screenshot (right sidebar visible) and any open popout closed. Opening a popout with the sidebar open closes the sidebar.
12. `jq '.bar.iconPopouts = false' ` into `CFG`: the speaker and mic icons disappear unless muted; `click` on the network icon opens the sidebar, not a popout (`popout_open` false). Toggle `iconPopouts` back to `true` while a popout is open (open it first): it closes.
13. Sidebar and overlay: open the sidebar volume dialog and the overlay volume mixer; screenshots show the new mute button and slider and nothing else changed.

After the sequence: `qs log -c ii | tail -60` shows no new warnings or errors. Then restore:
```sh
cp /tmp/ii-config.bak "$CFG"
```
and unmute whatever step 8 muted. On any failed assertion: fix the QML, amend the WIP commit, reload and rerun the failed layout from the start. Report each assertion with pass/fail and the screenshot paths in `/tmp/ii-*.png`.

Not driven (left to the human checklist in Task 6): typing a Wi-Fi password, the Wi-Fi and Bluetooth power switches, screen lock/unlock with a popout open, unplugging the Bluetooth adapter, and visual judgement beyond what the agent read from screenshots.

---

### Task 5: Export the patches, document, build

**Files:**
- Create: `patches/ii/08-bar-popouts/0001-*.patch`, `0002-*.patch` (generated)
- Modify: `docs/II-INTEGRATION.md`
- Modify: `docs/VERIFY.md`

**Interfaces:**
- Consumes: Task 1 commit and Tasks 2-4 WIP commits in the clone.

- [ ] **Step 1: Squash and tag**

```sh
cd ~/src/dots-hyprland
git log --oneline krane/07-idle..krane
git reset --soft HEAD~3
git commit -m "feat(bar): per-icon popouts for status icons"
git tag -f krane/08-bar-popouts
git log --oneline krane/07-idle..krane
```
Expected final log: exactly two commits, `feat(volume)…` then `feat(bar)…`. If the first log shows a different count (the volume commit is first, then 3 WIPs), adjust `HEAD~N` to the number of WIP commits.

- [ ] **Step 2: Export all series**

Run the "export every series again" block from the Workflow section of `docs/II-INTEGRATION.md`, then:
```sh
cd ~/.dotfiles
ls patches/ii/08-bar-popouts
git status --short patches/ii
```
Expected: two new patch files and no modified existing patches (other series re-export byte-identical).

- [ ] **Step 3: Document**

`docs/II-INTEGRATION.md`: add after the `### 07-idle` subsection:
```markdown
### `08-bar-popouts`

Clicking the network, Bluetooth, speaker or mic bar icon opens a popout for that
icon instead of the right sidebar. `0001`: the volume dialog content gets a
mute button and a master slider, so the sidebar dialogs, the overlay mixer and
the popouts share them. `0002`: Wi-Fi and Bluetooth dialog content move into
their own files, a per-screen popout window with its own focus grab
(`BarIconPopout.qml`) is added, and `bar.iconPopouts` (default `true`)
controls it and keeps the speaker and mic icons always visible. With it off the
bar behaves as upstream.
```
`docs/VERIFY.md`: add the Task 6 checklist as a new section "Bar icon popouts", following the file's existing list style.

- [ ] **Step 4: Build and check**

```sh
cd ~/.dotfiles
git add patches/ii docs
host=$(hostname)
nix build ".#nixosConfigurations.$host.config.system.build.toplevel" --no-link 2>&1 | tail -20
just check 2>&1 | tail -20
```
Expected: build succeeds (a series conflict fails `applyPatches`), `just check` passes. If the build target name differs, take it from the `justfile`.

- [ ] **Step 5: Commit**

```sh
git commit -m "Add bar icon popouts patch series"
```

---

### Task 6: Human checklist, then cleanup

**Files:**
- Delete: `docs/superpowers/plans/2026-11-27-bar-icon-popouts.md`, `docs/superpowers/specs/2026-11-27-bar-icon-popouts-design.md`

- [ ] **Step 1: Rebuild the system and hand over the checklist**

The agent runs `nixos-rebuild` (or the repo's `just` switch recipe) only if the user has asked for it; otherwise it tells the user the patched ii is live-reloaded from `~/src/dots-hyprland`. Then it prints this checklist and waits:

- Each of the four icons opens its popout next to the icon, on your real bar layout.
- Typing a Wi-Fi password in the Wi-Fi popout works.
- The Wi-Fi and Bluetooth power switches work.
- Lock the screen with a popout open; after unlock it stays closed.
- Click outside, Esc, a second click on the icon and Details each close a popout.
- Mute buttons and sliders work; scrolling over the bar moves the speaker slider.
- The notification icon and empty indicator space still toggle the right sidebar.
- With Settings > Bar > Icon popouts off, speaker and mic icons appear only when muted and every click opens the sidebar.
- The sidebar volume dialogs and the overlay mixer show the new mute button and slider, nothing else changed.
- The look (card size, spacing, shadow, corners) fits the rest of the shell.

Do not proceed until the user reports the result. Failures go back to the clone: fix, re-export (Task 5 steps 1-5), re-run the affected driven checks.

- [ ] **Step 2: Final cleanup (only after the user confirms the checklist and the final review pass)**

After the user's approval, delete the plan and the spec, then:
```sh
git add -A && git commit -m "Remove bar icon popouts spec and plan"
```
