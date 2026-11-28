# Icon Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the left sidebar button's icon, icon color and an optional custom icon folder be chosen in Settings, Bar, and keep the button visible when only the Agents tab is enabled. Exported as the series `patches/ii/10-icon-picker`.

**Architecture:** Two commits on branch `krane` in `~/src/dots-hyprland` (paths under `dots/.config/quickshell/ii/`), tagged `krane/10-icon-picker` and exported by the workflow in `docs/II-INTEGRATION.md`. Commit 1 is the fork's `FileUtils.folderUrl` and `CustomIcon.customFolder` hunks applied with `git am`. Commit 2 hand-ports the rest onto the existing `bar.topLeftIcon` key: new `bar.topLeftIconColor` and `bar.topLeftIconsPath` defaults, the picker grid, the button, the Settings section. The fork's `custom.*` keys are not adopted.

**Tech Stack:** QML (Quickshell, `Qt.labs.folderlistmodel`), git (`am`, `format-patch`), Nix flake (`applyPatches` in `lib/mk-host.nix`), home-manager.

**Spec:** `docs/superpowers/specs/2026-11-28-end4pc-backports-design.md`, section `10-icon-picker` only.

## Global Constraints

- Work on `main` in `~/.dotfiles`; no branch, no worktree, no push anywhere.
- Patch work is commits on `krane` in `~/src/dots-hyprland`. Never use `git am -3` for fork patches (their blobs are not in the clone); the apply loop in Task 0 is the only place `-3` is used.
- No comments in code. No new files beyond `IconPickerGrid.qml` and the exported patch files. Commit messages in the clone: subject, then a body with problem, port and "Drop when ...". Commit message in `~/.dotfiles`: subject line only, no body, no Claude/Anthropic attribution.
- The patch must not touch `property bool launchOnStartup: false` in `Config.qml` (a `kraneIiPatches` sed matches it).
- Icon naming contract: `bar.topLeftIcon` holds a bare built-in name (`spark`, never `spark-symbolic`; the button appends `-symbolic`), or, when `bar.topLeftIconsPath` is set, the icon's file name as is (`mylogo.svg`, no suffix added), or `distro`. `bar.topLeftIconColor` is a color role (`primary`) or empty for the theme color.
- Hosts' `config.json` and `ii-settings.json` need no change (Task 7 states the evidence); runtime verification edits `hosts/tariognatha/illogical-impulse/config.json` through the symlink, and Task 6 Step 8 reverts it.

---

## Task 0: Setup

**Files:** none changed.

**Interfaces:** after this task, branch `krane` in `~/src/dots-hyprland` equals the tag of the last directory in `patches/ii/` (`krane/<dir>`), working tree clean.

- [ ] **Step 1: Check gh**

```sh
gh auth status
```

Expected: logged in to github.com. If not, run `gh auth login` and stop for the user.

- [ ] **Step 2: Update the dotfiles on main**

```sh
git -C ~/.dotfiles switch main
git -C ~/.dotfiles pull --ff-only
git -C ~/.dotfiles status -sb
```

Expected: `## main...origin/main` and no changed files.

- [ ] **Step 3: Ensure the clone exists**

```sh
[ -d ~/src/dots-hyprland/.git ] || git clone https://github.com/end-4/dots-hyprland ~/src/dots-hyprland
```

- [ ] **Step 4: Run the apply loop from docs/II-INTEGRATION.md**

```sh
PIN=$(jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock)
cd ~/src/dots-hyprland
git config rerere.enabled true
git fetch origin
if [ -d .git/rebase-apply ]; then
  echo "an am/rebase is already in progress; resolve it (git am --continue/--skip/--abort) first" >&2
  exit 1
fi
if git rev-parse --verify -q krane >/dev/null; then
  echo "krane already exists; the switch below discards any commits not yet exported" >&2
fi
git switch -C krane "$PIN"
for d in ~/.dotfiles/patches/ii/*/; do
  git am -3 "$d"*.patch || break
  git tag -f "krane/$(basename "$d")"
done
```

Expected: no error. If the "krane already exists" warning printed, first run `git log --oneline krane` before this step and check that every commit above the pin has a subject in `patches/ii/`; if one does not, stop and ask the user. On an `am` conflict: resolve, `git am --continue`, tag, and rerun the loop from the next directory.

- [ ] **Step 5: Confirm the clone matches patches/ii**

```sh
cd ~/src/dots-hyprland
last=$(basename "$(ls -d ~/.dotfiles/patches/ii/*/ | tail -1)")
for d in ~/.dotfiles/patches/ii/*/; do git rev-parse --verify -q "krane/$(basename "$d")" >/dev/null || echo "missing tag krane/$(basename "$d")"; done
[ "$(git rev-parse krane)" = "$(git rev-parse "krane/$last")" ] && echo "krane at krane/$last"
git status --short
git branch --show-current
```

Expected: no "missing tag" line, `krane at krane/<last dir>` (`08-bar-popouts`, or `09-end4pc-fixes` if that series is already merged), empty status, branch `krane`. Remember `krane/<last dir>` as PREV for Task 3.

---

## Task 1: Fork hunks for the custom icon folder (commit 1)

**Files:**
- Modify (via `git am`): `dots/.config/quickshell/ii/modules/common/functions/FileUtils.qml`, `dots/.config/quickshell/ii/modules/common/widgets/CustomIcon.qml`

**Interfaces:**
- `FileUtils.folderUrl(path: string): string`: file URL of a typed folder path (leading `~` expanded, trailing `/` stripped, `file://` prefix tolerated), `""` for an empty path.
- `CustomIcon.customFolder: string` (default `""`). `CustomIcon.iconFolder` now defaults to `FileUtils.folderUrl(customFolder)` if non-empty, else the built-in `assets/icons` URL.

- [ ] **Step 1: Fetch the fork commit into its own empty directory**

```sh
D=$(mktemp -d)
gh api repos/pctrade/end4-pC/commits/52814a6 -H 'Accept: application/vnd.github.patch' > "$D/52814a6.patch"
wc -l "$D/52814a6.patch"
echo "$D"
```

Expected: about 290 lines. Keep $D in the same shell for the next step, or re-set it to the printed directory.

- [ ] **Step 2: Apply only the files that port cleanly**

The fork's `Config.qml`, `LeftSidebarButton.qml`, `BarConfig.qml` (matched by `*Config.qml`), `SidebarRightContent.qml` and `IconPickerGrid.qml` are ported by hand in Task 2. (This exact command was run against a scratch clone of `krane` at `86d483e3` and applied cleanly.)

```sh
cd ~/src/dots-hyprland
git am --directory=dots/.config/quickshell/ii --exclude='*Config.qml' --exclude='*LeftSidebarButton.qml' --exclude='*SidebarRightContent.qml' --exclude='*IconPickerGrid.qml' "$D/52814a6.patch"
git show --stat --format=%s HEAD
```

Expected: `Applying: Edit Leftsidebar Button added to BarConfig` and exactly two files, `FileUtils.qml` (12 insertions) and `CustomIcon.qml` (3 insertions, 1 deletion). If a third file shows, run `git reset --hard HEAD~1` and fix the `--exclude` globs. If the patch fails on context instead, run `git am --abort` and hand-port: add this function to `FileUtils.qml` right after `trimFileProtocol`'s closing `}`,

```qml
    /**
     * Turns a user typed folder path into a file url, expanding a leading ~
     * @param {string} path
     * @returns {string} file url, or an empty string when the path is empty
     */
    function folderUrl(path) {
        const trimmed = root.trimFileProtocol(path ?? "").trim();
        if (trimmed === "") return "";
        const expanded = trimmed.startsWith("~") ? Quickshell.env("HOME") + trimmed.slice(1) : trimmed;
        return "file://" + expanded.replace(/\/+$/, "");
    }
```

and in `CustomIcon.qml` add `import qs.modules.common.functions` after the `Qt5Compat.GraphicalEffects` import and replace the `property string iconFolder: ...` line with:

```qml
    property string customFolder: ""
    property string iconFolder: FileUtils.folderUrl(root.customFolder) || Qt.resolvedUrl(Quickshell.shellPath("assets/icons"))
```

then `git add -A` and commit; Step 3 amends the message either way.

- [ ] **Step 3: Replace the commit message**

```sh
cd ~/src/dots-hyprland
git commit --amend -q \
  -m 'icon-picker: load icons from a custom folder' \
  -m 'CustomIcon only reads assets/icons, so the left sidebar button cannot show an icon from the user'"'"'s own folder.' \
  -m 'Backport of pctrade/end4-pC 52814a6, FileUtils.folderUrl and CustomIcon.customFolder only. The picker, the Settings section and the button follow in the next commit.' \
  -m 'Drop when the pinned CustomIcon takes a custom icon folder.'
git log -1 --format=%B
git show --stat --format= HEAD
```

Expected: the new message, still two files.

---

## Task 2: Picker, defaults, button, Settings section (commit 2)

**Files:**
- Create: `dots/.config/quickshell/ii/modules/common/widgets/IconPickerGrid.qml`
- Modify: `dots/.config/quickshell/ii/modules/common/Config.qml`
- Modify: `dots/.config/quickshell/ii/modules/ii/bar/LeftSidebarButton.qml`
- Modify: `dots/.config/quickshell/ii/modules/settings/BarConfig.qml`

**Interfaces:**
- `Config.options.bar.topLeftIconColor: string` (default `""`), `Config.options.bar.topLeftIconsPath: string` (default `""`).
- `IconPickerGrid` (`Flow`): props `currentValue`, `customFolder`, `colorName`; signal `selected(string name)` emits the bare name (built-in) or the file name (custom folder).
- `LeftSidebarButton`: `visible` also when `Config.options.sidebar.agents.enable`.

All paths below are relative to `~/src/dots-hyprland/dots/.config/quickshell/ii/`. Use the Edit tool with the exact old and new text.

- [ ] **Step 1: Create `modules/common/widgets/IconPickerGrid.qml`**

```qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Qt.labs.folderlistmodel
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Flow {
    id: root
    property string currentValue: ""
    property string customFolder: ""
    property string colorName: ""
    property real minCellSize: 44
    readonly property bool builtin: FileUtils.folderUrl(customFolder) === ""
    readonly property color iconColor: colorName
        ? (Appearance.colors[`col${colorName.charAt(0).toUpperCase()}${colorName.slice(1)}`] ?? Appearance.colors.colOnLayer0)
        : Appearance.colors.colOnLayer0
    readonly property int columns: Math.max(1, Math.floor((width + spacing) / (minCellSize + spacing)))
    readonly property real cellSize: width > 0 ? (width + spacing) / columns - spacing : minCellSize
    signal selected(string name)

    Layout.fillWidth: true
    spacing: 6

    FolderListModel {
        id: folderModel
        folder: FileUtils.folderUrl(root.customFolder) || "file://" + Quickshell.shellPath("assets/icons")
        nameFilters: ["*.svg", "*.png"]
        showDirs: false
    }

    Repeater {
        model: folderModel
        delegate: Item {
            id: cell
            required property string fileName
            readonly property string iconName: root.builtin ? fileName.replace(/-symbolic\.(svg|png)$/, "") : fileName
            readonly property bool isSelected: root.currentValue === iconName
            implicitWidth: root.cellSize
            implicitHeight: root.cellSize

            Rectangle {
                anchors.fill: parent
                radius: cell.isSelected ? Appearance.rounding.normal : Appearance.rounding.small
                color: cell.isSelected ? Appearance.colors.colSecondaryContainer : (mouseArea.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)
                border.width: cell.isSelected ? 2 : 0
                border.color: Appearance.colors.colPrimary

                Behavior on radius {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            CustomIcon {
                anchors.centerIn: parent
                width: root.cellSize * 0.5
                height: root.cellSize * 0.5
                source: cell.fileName
                customFolder: root.customFolder
                colorize: true
                color: root.iconColor
            }

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selected(cell.iconName)

                StyledToolTip {
                    extraVisibleCondition: false
                    alternativeVisibleCondition: mouseArea.containsMouse
                    text: cell.fileName.replace(/(-symbolic)?\.(svg|png)$/, "")
                }
            }
        }
    }
}
```

- [ ] **Step 2: `modules/common/Config.qml`, add the two defaults after `topLeftIcon`**

Old (unique; line 269 at the current tip):

```qml
                property string topLeftIcon: "spark" // Options: "distro" or any icon name in ~/.config/quickshell/ii/assets/icons
```

New:

```qml
                property string topLeftIcon: "spark" // Options: "distro" or any icon name in ~/.config/quickshell/ii/assets/icons
                property string topLeftIconColor: ""
                property string topLeftIconsPath: ""
```

- [ ] **Step 3: `modules/ii/bar/LeftSidebarButton.qml`, three edits**

Edit 3a. Old:

```qml
import qs.modules.common.widgets
```

New:

```qml
import qs.modules.common.widgets
import qs.modules.common.functions
```

Edit 3b (visibility with the Agents tab, icon state). Old:

```qml
    property bool animeEnabled: Config.options.policies.weeb !== 0
    visible: aiChatEnabled || translatorEnabled || animeEnabled
```

New:

```qml
    property bool animeEnabled: Config.options.policies.weeb !== 0
    property bool agentsEnabled: Config.options.sidebar.agents.enable
    visible: aiChatEnabled || translatorEnabled || animeEnabled || agentsEnabled

    readonly property string iconName: Config.options.bar.topLeftIcon
    readonly property bool customFolderIcon: FileUtils.folderUrl(Config.options.bar.topLeftIconsPath) !== ""
    readonly property color iconColor: {
        const name = Config.options.bar.topLeftIconColor;
        return name ? (Appearance.colors[`col${name.charAt(0).toUpperCase()}${name.slice(1)}`] ?? Appearance.colors.colOnLayer0) : Appearance.colors.colOnLayer0;
    }
```

Edit 3c (the icon). Old:

```qml
        source: Config.options.bar.topLeftIcon == 'distro' ? SystemInfo.distroIcon : ${Config.options.bar.topLeftIcon}-symbolic`
        colorize: true
        color: Appearance.colors.colOnLayer0
```

New:

```qml
        source: root.iconName == 'distro' ? SystemInfo.distroIcon : (root.customFolderIcon ? root.iconName : `${root.iconName}-symbolic`)
        customFolder: root.iconName == 'distro' ? "" : Config.options.bar.topLeftIconsPath
        colorize: true
        color: root.iconColor
```

- [ ] **Step 4: `modules/settings/BarConfig.qml`, insert the section before Notifications**

Old (unique; the line after it is `shape: MaterialShape.Shape.Bun`):

```qml
        ContentSection {
            icon: "notifications"
```

New:

```qml
        ContentSection {
            icon: "right_panel_open"
            shape: MaterialShape.Shape.Pentagon
            title: Translation.tr("Left sidebar button")

            GroupedList {
                IconPickerGrid {
                    customFolder: Config.options.bar.topLeftIconsPath
                    currentValue: Config.options.bar.topLeftIcon
                    colorName: Config.options.bar.topLeftIconColor
                    onSelected: name => { Config.options.bar.topLeftIcon = name }
                }
                ConfigTextArea {
                    id: iconsPathField
                    Layout.fillWidth: true
                    buttonIcon: "folder_open"
                    text: Translation.tr("Custom icons folder")
                    placeholderText: Translation.tr("Leave empty to use the built-in icons, e.g. ~/Pictures/icons")
                    value: Config.options.bar.topLeftIconsPath
                    onValueChanged: iconsPathDebounce.restart()

                    Timer {
                        id: iconsPathDebounce
                        interval: 600
                        onTriggered: Config.options.bar.topLeftIconsPath = iconsPathField.value
                    }
                }
                ColorSelectionArray {
                    icon: "palette"
                    text: Translation.tr("Icon color")
                    options: ["onLayer0", "primary", "secondary", "tertiary", "onPrimaryContainer", "onSecondaryContainer", "onTertiaryContainer"]
                    currentValue: Config.options.bar.topLeftIconColor
                    onSelected: newValue => { Config.options.bar.topLeftIconColor = newValue }
                }
            }
        }

        ContentSection {
            icon: "notifications"
```

- [ ] **Step 5: Check the diff**

```sh
cd ~/src/dots-hyprland
git status --short
git diff --stat
git diff | grep -c launchOnStartup
```

Expected: four changed files (`Config.qml` +2, `IconPickerGrid.qml` new, 80 lines, `LeftSidebarButton.qml` +13 -3, `BarConfig.qml` +37), and `0` from the grep.

- [ ] **Step 6: Commit**

```sh
cd ~/src/dots-hyprland
git add -A
git commit -q \
  -m 'feat(bar): choose the left sidebar button icon, color and icon folder' \
  -m 'The left sidebar button icon could only be changed by editing config.json, it had no color setting, and with AI, translator and anime off the button hid itself, which left the Agents tab unreachable.' \
  -m 'Port of pctrade/end4-pC 52814a6 onto bar.topLeftIcon: new bar.topLeftIconColor and bar.topLeftIconsPath, IconPickerGrid and a Left sidebar button section in Settings, Bar. The fork keeps these under custom.* and has a colorize switch; neither is adopted. The picker stores the bare name, the button appends -symbolic for built-in icons only, an icon from the custom folder keeps its file name. The button also shows when sidebar.agents.enable is on.' \
  -m 'Drop when the pinned ii has an icon picker for the left sidebar button.'
git log --oneline -3
```

Expected: the new commit on top of the Task 1 commit.

---

## Task 3: Tag, export, stage

**Files:**
- Create: `~/.dotfiles/patches/ii/10-icon-picker/0001-*.patch`, `0002-*.patch`

**Interfaces:** tag `krane/10-icon-picker` on the Task 2 commit; the export loop recreates every series from the tags.

- [ ] **Step 1: Tag the last commit**

```sh
cd ~/src/dots-hyprland
git tag -f krane/10-icon-picker
mkdir -p ~/.dotfiles/patches/ii/10-icon-picker
```

- [ ] **Step 2: Export every series (loop from docs/II-INTEGRATION.md)**

```sh
cd ~/src/dots-hyprland
if [ -d .git/rebase-apply ]; then
  echo "an am/rebase is still in progress; finish it before exporting" >&2
  exit 1
fi
PIN=${PIN:-$(jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock)}
prev="$PIN"
for d in ~/.dotfiles/patches/ii/*/; do
  n=$(basename "$d")
  if ! git rev-parse --verify -q "krane/$n" >/dev/null; then
    echo "tag krane/$n is missing; tag the sub-project's last commit before exporting" >&2
    break
  fi
  rm -f "$d"*.patch
  git format-patch --zero-commit --no-signature --no-numbered -o "$d" "$prev..krane/$n"
  prev="krane/$n"
done
```

Expected: no "missing" line.

- [ ] **Step 3: Check that only the new series changed**

```sh
git -C ~/.dotfiles status --short patches/ii
ls ~/.dotfiles/patches/ii/10-icon-picker
git -C ~/src/dots-hyprland diff PREV..krane/10-icon-picker | grep -c launchOnStartup
```

Replace PREV with the tag from Task 0 Step 5 (`krane/08-bar-popouts` or `krane/09-end4pc-fixes`). Expected: `status` lists only `?? patches/ii/10-icon-picker/`; two files, `0001-icon-picker-load-icons-from-a-custom-folder.patch` and `0002-feat-bar-choose-the-left-sidebar-button-icon-color-and-icon-folder.patch` (git may cut the second name shorter); `0` from the grep. A modified old patch file means a tag is out of sync with `patches/ii`: stop and ask.

- [ ] **Step 4: Stage**

```sh
git -C ~/.dotfiles add patches/ii
git -C ~/.dotfiles status --short
```

Expected: two `A` lines under `patches/ii/10-icon-picker/`.

---

## Task 4: Docs

**Files:**
- Modify: `~/.dotfiles/docs/II-INTEGRATION.md`
- Modify: `~/.dotfiles/docs/VERIFY.md`

**Interfaces:** none.

- [ ] **Step 1: II-INTEGRATION.md, series list**

In "Backported fork fixes", first paragraph, find the sentence listing the series (``01-fixes`, `02-translator`, ...`). Edit it so that `10-icon-picker` is its last entry. With `09-end4pc-fixes` not yet in it, old:

```
`06-notifications`
and `07-idle`.
```

New:

```
`06-notifications`,
`07-idle`, `08-bar-popouts` and `10-icon-picker`.
```

If the sentence already ends with `... `08-bar-popouts` and `09-end4pc-fixes`.` (the 09 plan ran first), make it `... `08-bar-popouts`, `09-end4pc-fixes` and `10-icon-picker`.`.

- [ ] **Step 2: II-INTEGRATION.md, series paragraph**

Insert before the line `### Workflow` (after the last `### `NN-...`` section), one blank line each side:

```markdown
### `10-icon-picker`

Settings, Bar, "Left sidebar button" picks the icon of the left sidebar button, its color and an optional folder of icons. The keys sit under `bar` in `config.json`: `topLeftIcon` (a bare built-in name, to which the button appends `-symbolic`; the file name as is for an icon from the custom folder; or `distro` for the OS logo), `topLeftIconColor` (a color role such as `primary`; empty is the theme color) and `topLeftIconsPath` (a folder of `.svg` and `.png` files, `~` allowed; empty is `assets/icons`). Changing the folder does not migrate `topLeftIcon`: pick the icon again. The button also shows when only the Agents tab is enabled. Drop when pinned ii has an icon picker for this button.
```

- [ ] **Step 3: VERIFY.md, on-target checks**

Append to the end of `docs/VERIFY.md` (after the last on-target section), one blank line before it:

```markdown
### Left sidebar icon picker

- Settings > Bar > "Left sidebar button" lists the built-in icons and highlights the current one.
- Picking an icon and a color changes the bar button at once and survives a shell restart.
- A folder of `.svg` or `.png` files in "Custom icons folder" replaces the grid; picking one shows it on the button. Emptying the field blanks the button until a built-in icon is picked again.
- With AI, translator and anime off and Agents on, the button is visible; with Agents off too it is hidden.
```

- [ ] **Step 4: Check**

```sh
git -C ~/.dotfiles diff --stat -- docs
grep -n "10-icon-picker" ~/.dotfiles/docs/II-INTEGRATION.md
```

Expected: both docs changed; at least two matches (list and heading).

---

## Task 5: Build

**Files:** none.

**Interfaces:** `applyPatches` fails the build on a stale patch.

- [ ] **Step 1: Build tariognatha with the staged patches**

```sh
cd "$(mktemp -d)" && nixos-rebuild build --flake ~/.dotfiles#tariognatha
```

Expected: exit 0, a `result` symlink in the temporary directory. On a patch error naming a file, fix the commit in `~/src/dots-hyprland` (`git commit --amend` or a rebase), move the tags, rerun Task 3 and this step.

---

## Task 6: Runtime verification on tariognatha

**Files:**
- Test state: `hosts/tariognatha/illogical-impulse/config.json` (through `~/.config/illogical-impulse`), `~/Pictures/icons/`

**Interfaces:** none.

- [ ] **Step 1: Switch twice**

```sh
sudo nixos-rebuild switch --flake ~/.dotfiles#tariognatha
sudo nixos-rebuild switch --flake ~/.dotfiles#tariognatha
grep -c topLeftIconsPath ~/.config/quickshell/ii/modules/common/Config.qml
```

Expected: both succeed; `1`.

- [ ] **Step 2: Restart the shell and read the log**

Press `CTRL + SUPER + R` (Shell: Restart widgets), wait 5 s, then:

```sh
qs log -c ii | grep -iE "TypeError|ReferenceError|IconPickerGrid|CustomIcon|LeftSidebarButton|BarConfig"
```

Expected: no output.

- [ ] **Step 3: Built-in icon**

`SUPER + I`, Bar, "Left sidebar button". Expected: a grid of 25 icons (`spark` highlighted), tooltips without `-symbolic`. Click `nixos`. Expected: the bar button shows the NixOS logo at once; then:

```sh
jq -c '.bar | {topLeftIcon, topLeftIconColor, topLeftIconsPath}' ~/.config/illogical-impulse/config.json
```

Expected: `topLeftIcon` is `"nixos"` (no `-symbolic`); the other two are `""` or `null` (unset).

- [ ] **Step 4: Color**

Click the `primary` swatch under "Icon color". Expected: the bar icon and the grid icons take the primary color; the jq command prints `"topLeftIconColor":"primary"`.

- [ ] **Step 5: Custom folder icon**

```sh
mkdir -p ~/Pictures/icons
cp ~/.config/quickshell/ii/assets/icons/github-symbolic.svg ~/Pictures/icons/mylogo.svg
```

Type `~/Pictures/icons` in "Custom icons folder", wait 1 s. Expected: the grid shows only one icon, `mylogo`. Click it. Expected: the bar button shows the GitHub glyph in the primary color; jq prints `"topLeftIcon":"mylogo.svg"` and `"topLeftIconsPath":"~/Pictures/icons"`.

- [ ] **Step 6: Persistence**

Press `CTRL + SUPER + R`, wait 5 s. Expected: same GitHub glyph, same color. Then clear the folder field. Expected: the built-in grid returns and the button is blank (`mylogo.svg-symbolic` does not exist); click `spark`: the button shows the spark icon again.

- [ ] **Step 7: Visibility with the Agents tab**

tariognatha already has `policies.ai` and `policies.weeb` at `0`. Turn the translator off and keep Agents on:

```sh
bash -c 'f=~/.config/illogical-impulse/config.json; jq --indent 4 ".sidebar.translator.enable = false | .sidebar.agents.enable = true" "$f" > "$f.tmp" && mv "$f.tmp" "$f"'
```

Expected: the button stays visible. Then:

```sh
bash -c 'f=~/.config/illogical-impulse/config.json; jq --indent 4 ".sidebar.agents.enable = false" "$f" > "$f.tmp" && mv "$f.tmp" "$f"'
```

Expected: the button disappears. Step 8 restores both settings.

- [ ] **Step 8: Restore test state**

```sh
git -C ~/.dotfiles diff --stat -- hosts
git -C ~/.dotfiles checkout -- hosts/tariognatha/illogical-impulse/config.json
rm -r ~/Pictures/icons/mylogo.svg
rmdir ~/Pictures/icons 2>/dev/null
git -C ~/.dotfiles status --short
```

Expected: the diff shows only `hosts/tariognatha/illogical-impulse/config.json`; afterwards `status` lists only `patches/ii/10-icon-picker/` and the two docs. If the diff showed other hosts or unrelated hunks, restore only the keys changed in this task instead of the whole file.

---

## Task 7: ii-settings and host config check

**Files:** none changed.

**Interfaces:** answers "does the settings port or a host file need the new keys?": no.

- [ ] **Step 1: Confirm the settings port does not enumerate bar keys**

```sh
cd ~/.dotfiles
grep -nE 'bar|topLeft' modules/home/desktop/ii-settings.nix pkgs/krane-ii-settings/schema.json
grep -rn topLeftIcon hosts
```

Expected: the first grep prints nothing (`ii-settings.nix` and `schema.json` only name `hyprland` keys, `idle` fields and `monitor` fields; they read `hosts/<host>/ii-settings.json`, never the shell options in `config.json`). The second prints only `"topLeftIcon": "spark"` in the three hosts' `config.json`. No change is needed: ii takes the `Config.qml` default for a key absent from `config.json` (docs/II-INTEGRATION.md's 02-translator note relies on the same behaviour) and writes the new keys itself when the picker is used. If the first grep prints anything, stop and add the keys where it points.

---

## Task 8: Commit in ~/.dotfiles

**Files:**
- Commit: `patches/ii/10-icon-picker/`, `docs/II-INTEGRATION.md`, `docs/VERIFY.md`

**Interfaces:** none.

- [ ] **Step 1: Check what is staged**

```sh
git -C ~/.dotfiles add patches/ii docs/II-INTEGRATION.md docs/VERIFY.md
git -C ~/.dotfiles status --short
```

Expected: only those paths (the plan and spec are not added).

- [ ] **Step 2: Commit on main**

```sh
git -C ~/.dotfiles commit -m 'Add icon-picker patch series'
git -C ~/.dotfiles log -1 --format=%s
```

Expected: `Add icon-picker patch series`; no body, no attribution. No push.

---

## Task 9: Remove the spec and plan (after verification, final review and the user's approval)

**Files:**
- Delete: `docs/superpowers/plans/2026-11-28-icon-picker.md`
- Delete: `docs/superpowers/specs/2026-11-28-end4pc-backports-design.md` (only if no other plan still uses it)

**Interfaces:** none.

- [ ] **Step 1: Ask for approval**

Run only after Tasks 5 and 6 passed and the final review pass is done. Ask the user to approve deleting the plan and spec; stop if not approved.

- [ ] **Step 2: Delete and commit**

The spec also covers `09-end4pc-fixes`: keep it while another plan names it.

```sh
cd ~/.dotfiles
grep -l 2026-11-28-end4pc-backports-design docs/superpowers/plans/* | grep -v icon-picker
```

If this prints nothing:

```sh
git rm docs/superpowers/plans/2026-11-28-icon-picker.md docs/superpowers/specs/2026-11-28-end4pc-backports-design.md
git commit -m 'Remove icon picker spec and plan'
```

Otherwise:

```sh
git rm docs/superpowers/plans/2026-11-28-icon-picker.md
git commit -m 'Remove icon picker plan'
```

Expected: clean `git status`. No push.
