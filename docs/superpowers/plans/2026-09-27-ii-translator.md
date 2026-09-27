# Restyle and Enable the ii Translator — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give ii's left-sidebar Translator tab the pctrade/end4-pC layout (input, centred source/swap/target row, output, wallpaper-tinted surfaces) without the fork's defects, and turn the tab on by default for hosts where ii has never run.

**Architecture:** Three commits on the local `krane` branch in `~/src/dots-hyprland`, after sub-project 1's commits (tag `krane/01-fixes`), exported with `git format-patch` into `patches/ii/02-translator/`. The `iiSeries` loader that sub-project 1 added to `lib/mk-host.nix` applies every `patches/ii/*/` directory in lexical order, so nothing in Nix changes. Existing hosts get the tab through ii's own settings toggle, never through Nix.

**Tech Stack:** Nix flakes, nixpkgs `applyPatches`, git (`apply`, `format-patch`, `am -3`), Quickshell QML (Qt 6), translate-shell (`trans`), `qmllint`, `jq`.

**Spec:** `docs/superpowers/specs/2026-09-27-ii-translator-design.md` (delivery mechanism from `docs/superpowers/specs/2026-09-27-ii-fork-fixes-design.md`; workflow from `docs/superpowers/plans/2026-09-27-ii-fork-fixes.md`, assumed executed).

## Global Constraints

- Run every shell block with `bash` (the interactive shell is fish). Use `command cat`, never bare `cat`, in commands you type. Scratch directories: `mktemp -d -p $XDG_RUNTIME_DIR`.
- Pinned dots-hyprland revision: `jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock` (currently `97c5bc651f68092351b24aaa935af708b1e04514`).
- Workspace clone: `~/src/dots-hyprland`, branch `krane`, `git rerere` enabled, set up by sub-project 1. This plan adds commits after tag `krane/01-fixes`; it never rewrites earlier commits.
- Export command for this sub-project, always exactly: `rm -f ~/.dotfiles/patches/ii/02-translator/*.patch && git -C ~/src/dots-hyprland format-patch --zero-commit --no-signature -o ~/.dotfiles/patches/ii/02-translator krane/01-fixes..krane`. Task 4 tags the end of the series `krane/02-translator`, after which the range equals the spec's `krane/01-fixes..krane/02-translator`.
- Fork diffs are relative to the ii root; apply them with `git apply --directory=dots/.config/quickshell/ii`. Diffs written in this plan use full repo paths and apply with plain `git apply`.
- Clone commit messages use sub-project 1's trailer format (`Backport of`, URL, `Problem:`, `Port:`, `Drop when:`); `Port: new` patches omit the `Backport of` and URL lines.
- Dotfiles repo commit messages: subject line only, no body, no attribution lines. Never push. One repo commit per patch file, plus one for the docs.
- Only `modules/ii/sidebarLeft/Translator.qml`, `modules/ii/sidebarLeft/translator/TextCanvas.qml`, `modules/ii/sidebarLeft/translator/LanguageSelectorButton.qml` and one default in `modules/common/Config.qml` change. No fork-only files, config keys or bar changes. `9f63cce` (hardcoded Bing) is not ported.
- `config.json` stays ii-owned: no Nix code, activation script or build step writes it. The only edits to it in this plan are the user's own one-time toggle (GUI or the documented `jq` command) and a backed-up, restored test edit.
- Upstream code comments stay; the fork's comment stripping is not copied.
- If a check in this plan runs after sub-project 5 has landed, `~/.config/illogical-impulse` is a symlink into this repo (`hosts/<host>/illogical-impulse/`) and `config.json` is a tracked file. Restore every test edit exactly, never stage `config.json` (the user commits it after a privacy review), and check `git -C ~/.dotfiles status --short hosts/` before any repo commit.

### Checking the built source

Same block as sub-project 1. It prints the patched ii source path for tariognatha:

```bash
cd ~/.dotfiles
gen=$(nix build --no-link --print-out-paths .#nixosConfigurations.tariognatha.config.home-manager.users.krane.home.activationPackage)
iisrc=$(grep -rhoE '/nix/store/[a-z0-9]{32}-dots-hyprland-[a-z-]+' "$gen" | sort -u | head -1)
echo "$iisrc"
```

Expected: the path ends in `-dots-hyprland-patched`. A change is present when the built file equals the clone's file:

```bash
diff -q "$iisrc/dots/.config/quickshell/ii/<file>" ~/src/dots-hyprland/dots/.config/quickshell/ii/<file>
```

Flakes only see git-tracked files: `git add` a new patch file before running this block.

### QML syntax check

No QML test harness exists for ii, and `qmllint` cannot resolve the `qs.*` imports outside Quickshell: it prints unresolved-import warnings for every ii file, so neither its warnings nor its exit status are a usable gate. Its `[syntax]` diagnostics still work (a deliberate syntax error yields one `[syntax]` line), so this is the static gate after every QML edit:

```bash
cd ~/src/dots-hyprland/dots/.config/quickshell/ii
for f in modules/ii/sidebarLeft/Translator.qml modules/ii/sidebarLeft/translator/TextCanvas.qml modules/ii/sidebarLeft/translator/LanguageSelectorButton.qml modules/common/Config.qml; do
  echo "$(qmllint --bare "$f" 2>&1 | grep -c '\[syntax\]') $f"
done
```

Expected: every line starts with `0`.

## Assumed decisions

The spec's open questions, each taken at its recommended default:

1. **Existing hosts are enabled through the GUI** (Settings, Interface, "Enable translator") or the documented `jq` command. No activation script. A switch alone does not show the tab on tariognatha or tarmantria. Task 2 does the one-time toggle on tariognatha because the scrolling check must run before export; Task 5 does it on tarmantria.
2. **The `engine` config key is not wired** into the `trans` command. Google (translate-shell's default) stays.
3. **Target language stays `auto`** (English from the locale).
4. **The fixes to the fork's design are included**: no `buttonColor` shadow, per-pill hover tokens, scrolling inside each box.
5. **No detected-language display** on the source pill.

Choices this plan makes where the spec leaves room:

6. **Caret following uses `ensureVisible()` on `cursorRectangleChanged`, not the `TextArea.flickable` attachment** (the spec now says the same). The input `StyledTextArea` is created by a `Loader` that must stay in `TextCanvas` (the output shares the same component), and the attachment reparents the text area out of the `Loader` into the `Flickable`'s content item. One `StyledFlickable` holding both loaders, with the standard Qt "keep the cursor visible" function, gives the same behaviour without that reparenting. The spec's error-handling section allows fixing the scrolling pattern in the restyle commit; the Task 2 runtime check is the gate.
7. **`966162c`'s `Translator.qml` hunk (row spacing `Appearance.spacing.small` to `4`) is dropped.** It edits the swap-button row from `4da3e83` that `c7aaeb5` replaces; only its `TextCanvas.qml` hunk is ported, as patch 1.
8. **`TextCanvas.containerColor` defaults to `colLayer2`** (the fork used `colPrimaryContainer`), matching `LanguageSelectorButton`'s neutral fallback. Both call sites set it, so nothing visible changes.
9. **Pill text and the swap icon keep the fork's colours** (`colOnLayer2`, `colOnLayer1`). The readability acceptance check decides whether that holds; a failure there is reported, not fixed in this plan.

## Review Focus

1. **Swap while the source is `auto`.** Swapping makes the target `auto` and the source the old target. Expected: `trans` still returns a translation (target `auto` resolves to English) and no error appears (Task 5, Step 4).
2. **Typing at the end of a long input.** `contentHeight` can lag the caret by one layout pass. Expected: the caret stays visible on every keystroke, including the one that adds a new wrapped line (Task 2, Step 8).
3. **Clearing after scrolling.** Scroll to the bottom of a long input, press clear. Expected: the view returns to the top and the placeholder is visible, not a blank scrolled-away box (Task 2, Step 8).
4. **Long language names.** The pills show the names `trans -list-languages` prints; the longest is "Português Brasileiro" (20 characters) and the sidebar is 460 px wide. Expected: with both pills set to it, the swap button and both pills stay fully visible (Task 5, Step 5).
5. **Mouse wheel over the text.** With `interactions.scrolling.fasterTouchpadScroll` at its default `false`, `StyledFlickable`'s wheel `MouseArea` is hidden and the `Flickable`'s own wheel handling applies; the text area does not accept wheel events, so they must reach the flickable. Expected: wheel and touchpad scrolling work over the text in both boxes (Task 2, Step 8).
6. **Mouse drag inside the input.** The `StyledTextArea` now sits inside an interactive `Flickable`, which can take a vertical mouse drag for itself. Expected: dragging over text in the input selects it rather than scrolling the box (Task 2, Step 8). If the flickable steals the drag, that is a check failure to fix in the restyle commit (for example with the `TextArea.flickable` attachment the spec named).

---

### Task 1: Null-safe character counter (`966162c`, translator hunk)

**Files:**
- Create: `patches/ii/02-translator/0001-*.patch` (generated)
- Clone: `dots/.config/quickshell/ii/modules/ii/sidebarLeft/translator/TextCanvas.qml` (status-row `Loader`, pin lines 70-79)

**Interfaces:**
- Consumes: branch `krane` at tag `krane/01-fixes`; the `iiSeries` loader in `lib/mk-host.nix`.
- Produces: directory `patches/ii/02-translator/`; `TextCanvas.qml` status-row counter reading `inputLoader.item?.text.length ?? 0` inside a `StyledText`. Task 2's expected `TextCanvas.qml` hash assumes this change.

- [ ] **Step 1: Preflight the clone**

```bash
PIN=$(jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock)
cd ~/src/dots-hyprland
git switch krane
git status --porcelain
test "$(git rev-parse krane)" = "$(git rev-parse krane/01-fixes)" && echo AT_TAG
git diff --quiet "$PIN" krane -- dots/.config/quickshell/ii/modules/ii/sidebarLeft dots/.config/quickshell/ii/modules/common/Config.qml && echo FILES_AT_PIN
ls ~/.dotfiles/patches/ii
```

Expected: no `git status` output, `AT_TAG`, `FILES_AT_PIN`, and only `01-fixes` listed. If `AT_TAG` is missing, stop: something was committed after sub-project 1 and the export range would pick it up.

- [ ] **Step 2: Confirm the fix is not in the current build (failing check)**

Run the "Checking the built source" block, then:

```bash
grep -c 'inputLoader.item.text.length' "$iisrc/dots/.config/quickshell/ii/modules/ii/sidebarLeft/translator/TextCanvas.qml"
```

Expected: `1` (the unguarded read).

- [ ] **Step 3: Apply only the `TextCanvas.qml` hunk**

```bash
cd ~/src/dots-hyprland
curl -sL https://github.com/pctrade/end4-pC/commit/966162c.diff \
  | awk '/^diff --git/{p=($0 ~ /sidebarLeft\/translator\/TextCanvas\.qml/)} p' \
  | git apply --directory=dots/.config/quickshell/ii
git diff --stat
git diff | grep '^[-+] '
```

Expected: `TextCanvas.qml | 4 ++--` and exactly these changed lines:

```
-                sourceComponent: Text {
-                    text: Translation.tr("%1 characters").arg(inputLoader.item.text.length)
+                sourceComponent: StyledText {
+                    text: Translation.tr("%1 characters").arg(inputLoader.item?.text.length ?? 0)
```

- [ ] **Step 4: Syntax check**

Run the "QML syntax check" block. Expected: all `0`.

- [ ] **Step 5: Commit in the clone**

```bash
cd ~/src/dots-hyprland
git add -A
git commit -F - <<'EOF'
Translator: null-safe character counter

Backport of pctrade/end4-pC 966162c (translator hunk)
https://github.com/pctrade/end4-pC/commit/966162c
Problem: the input box's character counter read inputLoader.item.text while the Loader item can still be null, throwing a TypeError, and used a plain Text, so it ignored the shell font.
Port: clean. Only the TextCanvas.qml hunk. Dropped the bar, sidebarRight and WallpaperBrowser hunks, and the Translator.qml spacing hunk (it edits the 4da3e83 swap row that the restyle patch replaces).
Drop when: the pinned modules/ii/sidebarLeft/translator/TextCanvas.qml counter reads inputLoader.item?.text.
EOF
```

- [ ] **Step 6: Export the series**

```bash
mkdir -p ~/.dotfiles/patches/ii/02-translator
rm -f ~/.dotfiles/patches/ii/02-translator/*.patch && git -C ~/src/dots-hyprland format-patch --zero-commit --no-signature -o ~/.dotfiles/patches/ii/02-translator krane/01-fixes..krane
```

Expected: prints `.../patches/ii/02-translator/0001-Translator-null-safe-character-counter.patch`.

- [ ] **Step 7: Confirm the fix is in the build (passing check)**

```bash
cd ~/.dotfiles && git add patches/ii/02-translator
```

Run the "Checking the built source" block, then:

```bash
diff -q "$iisrc/dots/.config/quickshell/ii/modules/ii/sidebarLeft/translator/TextCanvas.qml" ~/src/dots-hyprland/dots/.config/quickshell/ii/modules/ii/sidebarLeft/translator/TextCanvas.qml && echo SAME
```

Expected: `SAME`. This also proves the unchanged `iiSeries` loader picked up the new directory.

- [ ] **Step 8: Commit**

```bash
cd ~/.dotfiles
git add patches/ii/02-translator/0001-*.patch
git commit -m "Backport end4-pC null-safe character counter for the ii translator"
```

---

### Task 2: Restyle with swap button (`4da3e83` + `c7aaeb5` + `6868389`, hand-ported)

One squashed patch. Compared with the fork it keeps upstream's comments, drops the `buttonColor` property (the call sites set `colBackground`/`colBackgroundHover` instead), gives each pill its own `…ContainerHover` token, and wraps each box's text in a `StyledFlickable` above the status row, with `clip: true` on the box and caret following in the input.

**Files:**
- Create: `patches/ii/02-translator/0002-*.patch` (generated)
- Clone: `modules/ii/sidebarLeft/Translator.qml` (new `swapLanguages()` after `showLanguageSelectorDialog`, pin lines 37-40; the main `ColumnLayout`, pin lines 103-220)
- Clone: `modules/ii/sidebarLeft/translator/LanguageSelectorButton.qml` (pin lines 12-15)
- Clone: `modules/ii/sidebarLeft/translator/TextCanvas.qml` (pin lines 13-63)

**Interfaces:**
- Consumes: Task 1's counter change (the expected `TextCanvas.qml` hash in Step 3 includes it). Pinned `RippleButton` properties `colBackground`, `colBackgroundHover`, `buttonRadius`, and its computed `buttonColor` (`modules/common/widgets/RippleButton.qml:26-38`); `GroupButton` `colBackground`/`colBackgroundHover`/`buttonRadius`; `Appearance.colors.colPrimaryContainer`, `colPrimaryContainerHover`, `colSecondaryContainer`, `colSecondaryContainerHover`, `colTertiaryContainer`, `colTertiaryContainerHover`; `Appearance.rounding.full`; `ColorUtils.transparentize(color, percentage)`; `StyledFlickable`.
- Produces: `Translator.swapLanguages()` (swaps `sourceLanguage`/`targetLanguage`, saves both to `Config.options.language.translator`, restarts `translateTimer`); `TextCanvas.containerColor: color` (default `Appearance.colors.colLayer2`); `TextCanvas.ensureVisible(r: rect, margin: real)`; element ids `swapButton`, `textFlickable`, `textColumn`. Existing ids (`inputCanvas`, `outputCanvas`, `sourceLanguageButton`, `targetLanguageButton`, `inputLoader`, `outputLoader`, `copyButton`, `searchButton`, `pasteButton`, `deleteButton`) keep their names.

- [ ] **Step 1: Confirm the restyle is not in the current build (failing check)**

Run the "Checking the built source" block, then:

```bash
grep -c 'swapLanguages' "$iisrc/dots/.config/quickshell/ii/modules/ii/sidebarLeft/Translator.qml"
```

Expected: `0`.

- [ ] **Step 2: Extract the diff from this plan**

The diff below was generated against the pin plus Task 1 and checked with `git apply --check`. Three of its lines end in whitespace that is part of the pinned source (`}    `, `inputLoader.item.text : `, `Item { Layout.fillHeight: true } `), and `git apply` rejects the diff if that whitespace is lost, even with `--ignore-whitespace`. Do not retype or copy-paste it; extract it byte-for-byte:

```bash
W=$(mktemp -d -p $XDG_RUNTIME_DIR)
awk -v m='<!-- extract: restyle.diff -->' '$0==m{f=1;next} f&&/^```diff$/{p=1;next} p&&/^```$/{exit} p' \
  ~/.dotfiles/docs/superpowers/plans/2026-09-27-ii-translator.md > "$W/restyle.diff"
sha256sum "$W/restyle.diff"
echo "$W"
```

Expected: `db4569f08765d56a10e26c5558c4a2ee8681f08b016b502fe3a6e79d5edcc75c`. Keep `$W` for Step 3.

<!-- extract: restyle.diff -->
```diff
diff --git a/dots/.config/quickshell/ii/modules/ii/sidebarLeft/Translator.qml b/dots/.config/quickshell/ii/modules/ii/sidebarLeft/Translator.qml
index bbb2ac2..98803d1 100644
--- a/dots/.config/quickshell/ii/modules/ii/sidebarLeft/Translator.qml
+++ b/dots/.config/quickshell/ii/modules/ii/sidebarLeft/Translator.qml
@@ -39,6 +39,18 @@ Item {
         root.showLanguageSelector = true
     }
 
+    function swapLanguages() {
+        let temp = root.targetLanguage;
+        root.targetLanguage = root.sourceLanguage;
+        root.sourceLanguage = temp;
+
+        // Save to config
+        Config.options.language.translator.targetLanguage = root.targetLanguage;
+        Config.options.language.translator.sourceLanguage = root.sourceLanguage;
+
+        translateTimer.restart(); // Restart translation after swap
+    }
+
     onFocusChanged: (focus) => {
         if (focus) {
             root.inputField.forceActiveFocus()
@@ -105,82 +117,12 @@ Item {
             fill: parent
             margins: root.padding
         }
-
-        StyledFlickable {
-            Layout.fillWidth: true
-            Layout.fillHeight: true
-            contentHeight: contentColumn.implicitHeight
-
-            ColumnLayout {
-                id: contentColumn
-                anchors.fill: parent
-
-                LanguageSelectorButton { // Target language button
-                    id: targetLanguageButton
-                    displayText: root.targetLanguage
-                    onClicked: {
-                        root.showLanguageSelectorDialog(true);
-                    }
-                }
-
-                TextCanvas { // Content translation
-                    id: outputCanvas
-                    isInput: false
-                    placeholderText: Translation.tr("Translation goes here...")
-                    property bool hasTranslation: (root.translatedText.trim().length > 0)
-                    text: hasTranslation ? root.translatedText : ""
-                    GroupButton {
-                        id: copyButton
-                        baseWidth: height
-                        buttonRadius: Appearance.rounding.small
-                        enabled: outputCanvas.displayedText.trim().length > 0
-                        contentItem: MaterialSymbol {
-                            anchors.centerIn: parent
-                            horizontalAlignment: Text.AlignHCenter
-                            iconSize: Appearance.font.pixelSize.larger
-                            text: "content_copy"
-                            color: copyButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
-                        }
-                        onClicked: {
-                            Quickshell.clipboardText = outputCanvas.displayedText
-                        }
-                    }
-                    GroupButton {
-                        id: searchButton
-                        baseWidth: height
-                        buttonRadius: Appearance.rounding.small
-                        enabled: outputCanvas.displayedText.trim().length > 0
-                        contentItem: MaterialSymbol {
-                            anchors.centerIn: parent
-                            horizontalAlignment: Text.AlignHCenter
-                            iconSize: Appearance.font.pixelSize.larger
-                            text: "travel_explore"
-                            color: searchButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
-                        }
-                        onClicked: {
-                            let url = Config.options.search.engineBaseUrl + outputCanvas.displayedText;
-                            for (let site of Config.options.search.excludedSites) {
-                                url += ` -site:${site}`;
-                            }
-                            Qt.openUrlExternally(url);
-                        }
-                    }
-                }
-
-            }    
-        }
-
-        LanguageSelectorButton { // Source language button
-            id: sourceLanguageButton
-            displayText: root.sourceLanguage
-            onClicked: {
-                root.showLanguageSelectorDialog(false);
-            }
-        }
+        spacing: 10
 
         TextCanvas { // Content input
             id: inputCanvas
             isInput: true
+            containerColor: ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 0.8)
             placeholderText: Translation.tr("Enter text to translate...")
             onInputTextChanged: {
                 translateTimer.restart();
@@ -217,6 +159,98 @@ Item {
                 }
             }
         }
+
+        RowLayout { // Language row: source, swap, target
+            Layout.fillWidth: true
+            spacing: 20
+
+            Item { Layout.fillWidth: true }
+
+            LanguageSelectorButton { // Source language button
+                id: sourceLanguageButton
+                displayText: root.sourceLanguage
+                colBackground: Appearance.colors.colSecondaryContainer
+                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
+                onClicked: {
+                    root.showLanguageSelectorDialog(false);
+                }
+            }
+
+            GroupButton { // Swap languages button
+                id: swapButton
+                Layout.preferredWidth: height
+                colBackground: Appearance.colors.colTertiaryContainer
+                colBackgroundHover: Appearance.colors.colTertiaryContainerHover
+                buttonRadius: Appearance.rounding.full
+                contentItem: MaterialSymbol {
+                    anchors.centerIn: parent
+                    horizontalAlignment: Text.AlignHCenter
+                    iconSize: Appearance.font.pixelSize.larger
+                    text: "autorenew"
+                    color: Appearance.colors.colOnLayer1
+                }
+                onClicked: {
+                    root.swapLanguages();
+                }
+            }
+
+            LanguageSelectorButton { // Target language button
+                id: targetLanguageButton
+                displayText: root.targetLanguage
+                colBackground: Appearance.colors.colPrimaryContainer
+                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
+                onClicked: {
+                    root.showLanguageSelectorDialog(true);
+                }
+            }
+
+            Item { Layout.fillWidth: true }
+        }
+
+        TextCanvas { // Content translation
+            id: outputCanvas
+            isInput: false
+            containerColor: ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 0.8)
+            placeholderText: Translation.tr("Translation goes here...")
+            property bool hasTranslation: (root.translatedText.trim().length > 0)
+            text: hasTranslation ? root.translatedText : ""
+            GroupButton {
+                id: copyButton
+                baseWidth: height
+                buttonRadius: Appearance.rounding.small
+                enabled: outputCanvas.displayedText.trim().length > 0
+                contentItem: MaterialSymbol {
+                    anchors.centerIn: parent
+                    horizontalAlignment: Text.AlignHCenter
+                    iconSize: Appearance.font.pixelSize.larger
+                    text: "content_copy"
+                    color: copyButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
+                }
+                onClicked: {
+                    Quickshell.clipboardText = outputCanvas.displayedText
+                }
+            }
+            GroupButton {
+                id: searchButton
+                baseWidth: height
+                buttonRadius: Appearance.rounding.small
+                enabled: outputCanvas.displayedText.trim().length > 0
+                contentItem: MaterialSymbol {
+                    anchors.centerIn: parent
+                    horizontalAlignment: Text.AlignHCenter
+                    iconSize: Appearance.font.pixelSize.larger
+                    text: "travel_explore"
+                    color: searchButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
+                }
+                onClicked: {
+                    let url = Config.options.search.engineBaseUrl + outputCanvas.displayedText;
+                    for (let site of Config.options.search.excludedSites) {
+                        url += ` -site:${site}`;
+                    }
+                    Qt.openUrlExternally(url);
+                }
+            }
+        }
     }
 
     Loader {
diff --git a/dots/.config/quickshell/ii/modules/ii/sidebarLeft/translator/LanguageSelectorButton.qml b/dots/.config/quickshell/ii/modules/ii/sidebarLeft/translator/LanguageSelectorButton.qml
index f23e3b8..54d829f 100644
--- a/dots/.config/quickshell/ii/modules/ii/sidebarLeft/translator/LanguageSelectorButton.qml
+++ b/dots/.config/quickshell/ii/modules/ii/sidebarLeft/translator/LanguageSelectorButton.qml
@@ -9,10 +9,15 @@ import QtQuick.Layouts
 RippleButton {
     id: root
     property string displayText: ""
+    // Fallback surface; Translator.qml sets colBackground and
+    // colBackgroundHover per pill. Do not add a `buttonColor` property here:
+    // RippleButton already has one (the hover/toggled/disabled blend the
+    // background binds to), and redeclaring it would drop that feedback.
     colBackground: Appearance.colors.colLayer2
+    buttonRadius: Appearance.rounding.full
 
-    implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
-    implicitHeight: contentItem.implicitHeight + verticalPadding * 2
+    implicitWidth: contentItem.implicitWidth + horizontalPadding * 2 + 10
+    implicitHeight: contentItem.implicitHeight + verticalPadding * 2 + 20
 
     contentItem: Item {
         anchors.centerIn: parent
diff --git a/dots/.config/quickshell/ii/modules/ii/sidebarLeft/translator/TextCanvas.qml b/dots/.config/quickshell/ii/modules/ii/sidebarLeft/translator/TextCanvas.qml
index 07af7a8..ca10275 100644
--- a/dots/.config/quickshell/ii/modules/ii/sidebarLeft/translator/TextCanvas.qml
+++ b/dots/.config/quickshell/ii/modules/ii/sidebarLeft/translator/TextCanvas.qml
@@ -11,57 +11,89 @@ Rectangle {
     property bool isInput: true // true for input, false for output
     property string placeholderText
     property string text: ""
+    property color containerColor: Appearance.colors.colLayer2
     property var inputTextArea: isInput ? inputLoader.item : undefined
     readonly property string displayedText: isInput ? inputLoader.item.text : 
         root.text.length > 0 ? outputLoader.item.text : ""
     default property alias actionButtons: actions.data
     Layout.fillWidth: true
-    implicitHeight: Math.max(150, inputColumn.implicitHeight)
-    color: Appearance.colors.colLayer2
+    Layout.fillHeight: true
+    color: containerColor
     radius: Appearance.rounding.normal
+    clip: true
 
     signal inputTextChanged(); // Signal emitted when text changes
 
+    // Scroll textFlickable so the caret rectangle `r` (text area coordinates)
+    // is visible, keeping `margin` px of the text area's padding around it.
+    function ensureVisible(r, margin) {
+        const f = textFlickable;
+        if (f.height <= 0) return;
+        let y = f.contentY;
+        if (r.y - margin < y)
+            y = r.y - margin;
+        else if (r.y + r.height + margin > y + f.height)
+            y = r.y + r.height + margin - f.height;
+        // No upper clamp: contentHeight can lag one layout pass behind the
+        // caret while typing at the end, and Flickable fixes contentY up to
+        // its bounds when contentHeight changes.
+        f.contentY = Math.max(0, y);
+    }
+
     ColumnLayout {
         id: inputColumn
         anchors.fill: parent
         spacing: 0
 
-        Loader {
-            id: inputLoader
-            active: root.isInput
-            visible: root.isInput
+        StyledFlickable { // Text area; scrolls so the status row stays in view
+            id: textFlickable
             Layout.fillWidth: true
-            sourceComponent: StyledTextArea { // Input area
-                id: inputTextArea
-                placeholderText: root.placeholderText
-                wrapMode: TextEdit.Wrap
-                textFormat: TextEdit.PlainText
-                font.pixelSize: Appearance.font.pixelSize.small
-                color: Appearance.colors.colOnLayer1
-                padding: 15
-                background: null
-                onTextChanged: root.inputTextChanged()
-            }
-        }
+            Layout.fillHeight: true
+            clip: true
+            contentWidth: width
+            contentHeight: textColumn.implicitHeight
 
-        Loader {
-            id: outputLoader
-            active: !root.isInput
-            visible: !root.isInput
-            Layout.fillWidth: true
-            sourceComponent: StyledText { // Output area
-                id: outputTextArea
-                padding: 15
-                wrapMode: Text.Wrap
-                font.pixelSize: Appearance.font.pixelSize.small
-                color: root.text.length > 0 ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
-                text: root.text.length > 0 ? root.text : root.placeholderText
+            ColumnLayout {
+                id: textColumn
+                width: textFlickable.width
+                spacing: 0
+
+                Loader {
+                    id: inputLoader
+                    active: root.isInput
+                    visible: root.isInput
+                    Layout.fillWidth: true
+                    sourceComponent: StyledTextArea { // Input area
+                        id: inputTextArea
+                        placeholderText: root.placeholderText
+                        wrapMode: TextEdit.Wrap
+                        textFormat: TextEdit.PlainText
+                        font.pixelSize: Appearance.font.pixelSize.small
+                        color: Appearance.colors.colOnLayer1
+                        padding: 15
+                        background: null
+                        onTextChanged: root.inputTextChanged()
+                        onCursorRectangleChanged: root.ensureVisible(cursorRectangle, padding)
+                    }
+                }
+
+                Loader {
+                    id: outputLoader
+                    active: !root.isInput
+                    visible: !root.isInput
+                    Layout.fillWidth: true
+                    sourceComponent: StyledText { // Output area
+                        id: outputTextArea
+                        padding: 15
+                        wrapMode: Text.Wrap
+                        font.pixelSize: Appearance.font.pixelSize.small
+                        color: root.text.length > 0 ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
+                        text: root.text.length > 0 ? root.text : root.placeholderText
+                    }
+                }
             }
         }
 
-        Item { Layout.fillHeight: true } 
-
         RowLayout { // Status row
             Layout.fillWidth: true
             Layout.margins: 10
```

- [ ] **Step 3: Apply the diff**

```bash
cd ~/src/dots-hyprland
git apply --check -v "$W/restyle.diff" && git apply "$W/restyle.diff"
git diff --stat
cd dots/.config/quickshell/ii && sha256sum modules/ii/sidebarLeft/Translator.qml modules/ii/sidebarLeft/translator/LanguageSelectorButton.qml modules/ii/sidebarLeft/translator/TextCanvas.qml
```

Expected: three files changed, 177 insertions, 106 deletions, and:

```
40ae353452538a81298981cb8dde4be6cf82197ef0e753b90a991455f5c5e584  modules/ii/sidebarLeft/Translator.qml
fb84a1179e6e9e6b7314ef83827a8d3ea07f813227c33d9a4108033bc11afb8b  modules/ii/sidebarLeft/translator/LanguageSelectorButton.qml
5447560f3fef68f4c8ea105caff80f015ca2a7c9ecb3e5e4fd10c16657ce712d  modules/ii/sidebarLeft/translator/TextCanvas.qml
```

- [ ] **Step 4: Check the port's defect fixes are in place**

```bash
cd ~/src/dots-hyprland/dots/.config/quickshell/ii/modules/ii/sidebarLeft
grep -c 'property color buttonColor' translator/LanguageSelectorButton.qml Translator.qml
grep -n 'colBackgroundHover' Translator.qml
grep -n 'clip: true\|StyledFlickable\|ensureVisible' translator/TextCanvas.qml
grep -c '// Content input\|// Content translation\|// Save to config' Translator.qml
```

Expected: both `buttonColor` counts `0`; three `colBackgroundHover` lines using `colSecondaryContainerHover`, `colTertiaryContainerHover` and `colPrimaryContainerHover` (one per pill and the swap button, no two alike); `clip: true` twice (box and flickable), one `StyledFlickable`, and `ensureVisible` defined once and called once; comment count `5` or more (upstream comments kept).

- [ ] **Step 5: Syntax check**

Run the "QML syntax check" block. Expected: all `0`.

- [ ] **Step 6: Commit in the clone**

```bash
cd ~/src/dots-hyprland
git add -A
git commit -F - <<'EOF'
Translator: restyle with swap button

Backport of pctrade/end4-pC 4da3e83, c7aaeb5, 6868389 (translator hunks)
https://github.com/pctrade/end4-pC/commit/c7aaeb5a58a7c4c965d9e692877ace415b4171bb
Problem: user wants the fork's translator layout
Port: hand-ported (squashed; dropped bar hunks and comment stripping; removed
  buttonColor shadow; per-pill hover tokens; added scrolling)
Drop when: never (feature, not a fix); revisit if upstream restyles Translator.qml
EOF
```

- [ ] **Step 7: Install the three files and enable the tab on tariognatha**

The spec requires the long-text check to pass before this patch is exported. Copy the clone's files over the installed ones (the next switch recopies them from the build), and do the one-time toggle (assumed decision 1). Either click Settings, Interface, "Enable translator", or:

```bash
src=~/src/dots-hyprland/dots/.config/quickshell/ii/modules/ii/sidebarLeft
dst=~/.config/quickshell/ii/modules/ii/sidebarLeft
qs log -c ii > $XDG_RUNTIME_DIR/qs-before.log 2>&1 || true   # baseline first: Quickshell live-reloads changed QML into this log
install -m 644 "$src/Translator.qml" "$dst/Translator.qml"
install -m 644 "$src/translator/TextCanvas.qml" "$src/translator/LanguageSelectorButton.qml" "$dst/translator/"
f=~/.config/illogical-impulse/config.json
jq '.sidebar.translator.enable = true' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
pkill -f '[q]s-wrapped -c ii'; hyprctl dispatch exec 'qs -c ii'
sleep 5; qs log -c ii > $XDG_RUNTIME_DIR/qs-after.log 2>&1 || true
grep -iE 'buttonColor|Translator|TextCanvas|LanguageSelectorButton' $XDG_RUNTIME_DIR/qs-after.log
```

Expected: the grep prints nothing. Open the left sidebar: a Translator tab follows Intelligence.

- [ ] **Step 8: Long-text, caret, clear and wheel checks (gate for export)**

```bash
s=$(for i in $(seq 30); do printf 'Le renard brun rapide saute par-dessus le chien paresseux. '; done)
printf %s "${s:0:1500}" | wl-copy
```

In the Translator tab:

1. Press paste. Expected: the text stays inside the tinted input box, which scrolls to show the rest; the character count reads `1500 characters`; paste and clear stay visible at the bottom of the box. After about 300 ms the output fills with English and scrolls inside its box; copy and search stay visible.
2. Click at the end of the input and type about three lines of text, watching each keystroke, including the one that wraps to a new line. Expected: the caret never leaves the visible area (Review Focus 2).
3. Scroll each box with the mouse wheel and with the touchpad. Expected: both scroll (Review Focus 5).
4. Press copy, then `wl-paste | head -c 80`. Expected: English text. Press search: a browser tab opens with the translation.
5. Scroll the input to the bottom and press clear. Expected: the placeholder "Enter text to translate..." is visible at the top of the box, the counter reads `0 characters`, and the output shows "Translation goes here..." (Review Focus 3).
6. Paste again, then drag with the mouse across two lines of the input. Expected: the text is selected and the box does not scroll with the drag (Review Focus 6).

Then:

```bash
qs log -c ii > $XDG_RUNTIME_DIR/qs-after.log 2>&1 || true
grep -iE 'error|warn|binding loop' $XDG_RUNTIME_DIR/qs-before.log | sort -u > $XDG_RUNTIME_DIR/qs-before.err
grep -iE 'error|warn|binding loop' $XDG_RUNTIME_DIR/qs-after.log | sort -u > $XDG_RUNTIME_DIR/qs-after.err
comm -13 $XDG_RUNTIME_DIR/qs-before.err $XDG_RUNTIME_DIR/qs-after.err
```

Expected: `comm` prints nothing. If any check fails, fix `TextCanvas.qml` or `Translator.qml` in the clone, rerun Steps 4, 5 and 7 to 8, and fold the fix into the commit with `git -C ~/src/dots-hyprland commit -a --amend --no-edit`. The Step 3 hashes then no longer match; that is expected. Do not export until all six pass. Delete the four `$XDG_RUNTIME_DIR/qs-*` files afterwards.

- [ ] **Step 9: Export the series**

```bash
rm -f ~/.dotfiles/patches/ii/02-translator/*.patch && git -C ~/src/dots-hyprland format-patch --zero-commit --no-signature -o ~/.dotfiles/patches/ii/02-translator krane/01-fixes..krane
cd ~/.dotfiles && git status --short patches/ii/02-translator
```

Expected: two files; `0001-*` unchanged, `0002-Translator-restyle-with-swap-button.patch` new.

- [ ] **Step 10: Confirm the restyle is in the build (passing check)**

```bash
cd ~/.dotfiles && git add patches/ii/02-translator
```

Run the "Checking the built source" block, then:

```bash
for f in modules/ii/sidebarLeft/Translator.qml modules/ii/sidebarLeft/translator/TextCanvas.qml modules/ii/sidebarLeft/translator/LanguageSelectorButton.qml; do
  diff -q "$iisrc/dots/.config/quickshell/ii/$f" ~/src/dots-hyprland/dots/.config/quickshell/ii/$f && echo "SAME $f"
done
```

Expected: `SAME` for all three.

- [ ] **Step 11: Commit**

```bash
cd ~/.dotfiles
git add patches/ii/02-translator/0002-*.patch
git commit -m "Restyle the ii translator with the end4-pC layout and a swap button"
```

---

### Task 3: Enable the translator by default

`property bool enable: false` occurs many times in `Config.qml`, so this is a patch in the series (it fails the build if the context moves), not an `iiPatches` sed entry.

**Files:**
- Create: `patches/ii/02-translator/0003-*.patch` (generated)
- Clone: `modules/common/Config.qml:501` (inside `sidebar.translator`)

**Interfaces:**
- Consumes: pinned `Config.options.sidebar.translator.enable`, read by `SidebarLeftContent.qml:16`, `bar/LeftSidebarButton.qml:13` and the settings toggle in `settings/InterfaceConfig.qml:484-486`.
- Produces: default `true` for that key.

- [ ] **Step 1: Confirm the default is `false` in the current build (failing check)**

Run the "Checking the built source" block, then:

```bash
grep -n -A1 'property JsonObject translator: JsonObject {' "$iisrc/dots/.config/quickshell/ii/modules/common/Config.qml" | grep 'enable'
```

Expected: `...property bool enable: false`.

- [ ] **Step 2: Extract and apply the diff**

This diff has no trailing whitespace, but extract it the same way for consistency:

```bash
W=$(mktemp -d -p $XDG_RUNTIME_DIR)
awk -v m='<!-- extract: config.diff -->' '$0==m{f=1;next} f&&/^```diff$/{p=1;next} p&&/^```$/{exit} p' \
  ~/.dotfiles/docs/superpowers/plans/2026-09-27-ii-translator.md > "$W/config.diff"
sha256sum "$W/config.diff"
cd ~/src/dots-hyprland
git apply --check -v "$W/config.diff" && git apply "$W/config.diff"
sha256sum dots/.config/quickshell/ii/modules/common/Config.qml
```

Expected: diff hash `f774713473dc64b4f8f2c3604d785f9a019bac9ef7213447a4512035ab9a87ed`; file hash `898d9a795591c4edbc7aefe7cfc9b3f3ba3ba1d192841f67002984d8d351a9c3`.

<!-- extract: config.diff -->
```diff
diff --git a/dots/.config/quickshell/ii/modules/common/Config.qml b/dots/.config/quickshell/ii/modules/common/Config.qml
index 5fcd1bb..30e8743 100644
--- a/dots/.config/quickshell/ii/modules/common/Config.qml
+++ b/dots/.config/quickshell/ii/modules/common/Config.qml
@@ -498,7 +498,7 @@ Singleton {
             property JsonObject sidebar: JsonObject {
                 property bool keepRightSidebarLoaded: true
                 property JsonObject translator: JsonObject {
-                    property bool enable: false
+                    property bool enable: true
                     property int delay: 300 // Delay before sending request. Reduces (potential) rate limits and lag.
                 }
                 property JsonObject ai: JsonObject {
```

- [ ] **Step 3: Syntax check**

Run the "QML syntax check" block. Expected: all `0`.

- [ ] **Step 4: Commit in the clone**

```bash
cd ~/src/dots-hyprland
git add -A
git commit -F - <<'EOF'
Translator: enable by default

Problem: the Translator tab only exists when sidebar.translator.enable is true, and the pinned default is false, so a new host needs a manual toggle before the tab appears.
Port: new
Drop when: upstream defaults sidebar.translator.enable to true
EOF
```

- [ ] **Step 5: Export the series**

```bash
rm -f ~/.dotfiles/patches/ii/02-translator/*.patch && git -C ~/src/dots-hyprland format-patch --zero-commit --no-signature -o ~/.dotfiles/patches/ii/02-translator krane/01-fixes..krane
cd ~/.dotfiles && git status --short patches/ii/02-translator
```

Expected: three files; `0001-*` and `0002-*` unchanged, `0003-Translator-enable-by-default.patch` new.

- [ ] **Step 6: Confirm the default is `true` in the build (passing check)**

```bash
cd ~/.dotfiles && git add patches/ii/02-translator
```

Run the "Checking the built source" block, then:

```bash
diff -q "$iisrc/dots/.config/quickshell/ii/modules/common/Config.qml" ~/src/dots-hyprland/dots/.config/quickshell/ii/modules/common/Config.qml && echo SAME
grep -n -A1 'property JsonObject translator: JsonObject {' "$iisrc/dots/.config/quickshell/ii/modules/common/Config.qml" | grep 'enable'
grep -c 'swapLanguages' "$iisrc/dots/.config/quickshell/ii/modules/ii/sidebarLeft/Translator.qml"
```

Expected: `SAME`; `...property bool enable: true`; a count of `2` (the function and the swap button's call; build check 1 from the spec: both changes present together).

- [ ] **Step 7: Commit**

```bash
cd ~/.dotfiles
git add patches/ii/02-translator/0003-*.patch
git commit -m "Enable the ii translator by default on fresh hosts"
```

---

### Task 4: Tag, re-apply check, dry-builds and documentation

**Files:**
- Modify: `docs/II-INTEGRATION.md` (insert a `### Translator (02-translator)` subsection inside `## Backported fork fixes`, directly before `### Workflow`)

**Interfaces:**
- Consumes: the three patches from Tasks 1-3; the `## Backported fork fixes` section and `### Workflow` loop written by sub-project 1's Task 6.
- Produces: tag `krane/02-translator` in the clone (clone-only, recreated by the workflow loop).

- [ ] **Step 1: Tag the end of the series**

```bash
cd ~/src/dots-hyprland
git tag -f krane/02-translator krane
git log --oneline krane/01-fixes..krane/02-translator
```

Expected: exactly three commits, oldest last: `Translator: enable by default`, `Translator: restyle with swap button`, `Translator: null-safe character counter`.

- [ ] **Step 2: Check that the documented workflow reproduces the branch**

```bash
PIN=$(jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock)
cd ~/src/dots-hyprland
git switch -C krane-check "$PIN"
for d in ~/.dotfiles/patches/ii/*/; do git am -3 "$d"*.patch || break; done
git diff --stat krane krane-check
git switch krane && git branch -D krane-check
```

Expected: `git am` applies every patch in `01-fixes` and all three in `02-translator`; `git diff --stat` prints nothing.

- [ ] **Step 3: Check the export is stable**

```bash
prev=krane/01-fixes; n=02-translator
rm -f ~/.dotfiles/patches/ii/$n/*.patch
git -C ~/src/dots-hyprland format-patch --zero-commit --no-signature -o ~/.dotfiles/patches/ii/$n "$prev..krane/$n"
cd ~/.dotfiles && git status --short patches/ii
```

Expected: `git status` prints nothing (the tagged-range export is byte-identical to the committed files).

- [ ] **Step 4: Dry-build all hosts**

```bash
cd ~/.dotfiles
for h in tariognatha tarmantria taractias; do nixos-rebuild dry-build --flake .#$h || echo "FAIL $h"; done
```

Expected: no `FAIL` lines.

- [ ] **Step 5: Add the documentation subsection**

In `docs/II-INTEGRATION.md`, directly before the `### Workflow` heading inside `## Backported fork fixes`, insert:

````markdown
### Translator (`02-translator`)

The left sidebar's Translator tab, restyled after the fork (input box,
centred source/swap/target row, output box, surfaces tinted from the
wallpaper palette), plus two fixes the fork lacked: pill hover feedback and
scrolling inside each box.

| Patch | Fork commit | Port | Drop when |
|---|---|---|---|
| `0001` null-safe character counter | `966162c` (`TextCanvas.qml` hunk) | clean | pinned `TextCanvas.qml` counter reads `inputLoader.item?.text` |
| `0002` restyle with swap button | `4da3e83` + `c7aaeb5` + `6868389` (translator hunks) | hand-ported | never; revisit if upstream restyles `Translator.qml` |
| `0003` enable by default | none | new | upstream defaults `sidebar.translator.enable` to `true` |

The `0003` default only reaches hosts whose `config.json` has no
`sidebar.translator.enable` key yet (a fresh host). ii saves its whole
options tree, so a host where ii has already run holds an explicit `false`:
turn the translator on once in Settings, Interface, "Enable translator", or
from a terminal (ii applies it live):

```sh
f=~/.config/illogical-impulse/config.json
jq '.sidebar.translator.enable = true' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
```

Not ported: `9f63cce`, which hardcodes `trans -e bing`; Bing rejects the
default `auto` source and target.
````

- [ ] **Step 6: Check the doc renders in place**

```bash
cd ~/.dotfiles
grep -n '^## Backported fork fixes\|^### Translator (`02-translator`)\|^### Workflow' docs/II-INTEGRATION.md
```

Expected: three lines in that order.

- [ ] **Step 7: Commit**

```bash
cd ~/.dotfiles
git add docs/II-INTEGRATION.md
git commit -m "Document the ii translator patch series and how to enable it"
```

---

### Task 5: Switch and runtime acceptance checks

Manual checks from the spec. Record each result (pass, fail, not run and why) in the task report. A failed check means fixing the commit in the clone, not patching around it here: edit the files, `git -C ~/src/dots-hyprland commit -a --fixup=<commit>`, `git -C ~/src/dots-hyprland rebase --autosquash krane/01-fixes` (no `-i` needed since git 2.44), then `git -C ~/src/dots-hyprland tag -f krane/02-translator krane`, export with Task 4, Step 3, and commit the changed patch files.

**Files:** none changed unless a check fails.

- [ ] **Step 1: Switch tariognatha and compare logs**

```bash
qs log -c ii > $XDG_RUNTIME_DIR/qs-before.log 2>&1 || true
cd ~/.dotfiles && sudo nixos-rebuild switch --flake .#tariognatha
pkill -f '[q]s-wrapped -c ii'; hyprctl dispatch exec 'qs -c ii'
sleep 5; qs log -c ii > $XDG_RUNTIME_DIR/qs-after.log 2>&1 || true
grep -iE 'error|warn|TypeError|ReferenceError' $XDG_RUNTIME_DIR/qs-after.log | sort -u > $XDG_RUNTIME_DIR/qs-after.err
grep -iE 'error|warn|TypeError|ReferenceError' $XDG_RUNTIME_DIR/qs-before.log | sort -u > $XDG_RUNTIME_DIR/qs-before.err
comm -13 $XDG_RUNTIME_DIR/qs-before.err $XDG_RUNTIME_DIR/qs-after.err
grep -iE 'buttonColor|Translator|TextCanvas|LanguageSelectorButton' $XDG_RUNTIME_DIR/qs-after.log
jq .sidebar.translator.enable ~/.config/illogical-impulse/config.json
```

Expected: `comm` and the second `grep` print nothing; `jq` prints `true` (the Task 2 toggle survived the switch). Delete the four `$XDG_RUNTIME_DIR/qs-*` files afterwards.

- [ ] **Step 2: Layout and palette (tariognatha DP-2 and DP-1)**

Open the left sidebar on each monitor. Expected: input box on top, then a centred row with source pill, round swap button and target pill, then the output box. The input box and source pill are secondary-container tinted, the swap button tertiary, the output box and target pill primary. Change the wallpaper through ii's selector: all tints follow.

- [ ] **Step 3: Translation**

Record the current `TypeError` count:

```bash
qs log -c ii 2>&1 | grep -c TypeError > $XDG_RUNTIME_DIR/qs-typeerror.count
```

Clear the input and type `Bonjour le monde`. Expected: after about 300 ms the output shows "Hello world". Clear the input: the counter reads `0 characters`, and:

```bash
echo "$(command cat $XDG_RUNTIME_DIR/qs-typeerror.count) -> $(qs log -c ii 2>&1 | grep -c TypeError)"; rm $XDG_RUNTIME_DIR/qs-typeerror.count
```

Expected: both numbers equal (no new `TypeError`).

- [ ] **Step 4: Language selection, swap and persistence**

Pick source `Français`, target `Deutsch` from the pills, type `Bonjour le monde`. Expected: German output. Press swap: the pills swap, the output re-translates. Restart qs and run:

```bash
pkill -f '[q]s-wrapped -c ii'; hyprctl dispatch exec 'qs -c ii'; sleep 5
jq .language.translator ~/.config/illogical-impulse/config.json
```

Expected: `sourceLanguage` and `targetLanguage` hold the swapped choices and the pills show them. Then set source to `auto` and press swap (Review Focus 1). Expected: target shows `auto`, the source shows the old target, a translation still appears, and the log gains no error. Set both back to `auto` afterwards.

- [ ] **Step 5: Hover and long language names**

Hover each pill and the swap button. Expected: each changes visibly on hover (each uses its own `…ContainerHover` token). Then set both pills to `Português Brasileiro` (Review Focus 4). Expected: both pills and the swap button are fully visible within the sidebar. If they are not, record it as a fail with a screenshot and report it; do not change the layout in this task. Set both back to `auto`.

- [ ] **Step 6: Readability (tariognatha DP-2)**

On one light and one dark wallpaper, read the pill labels and both boxes' text. Expected: easy to read against the 20% tints. A failure is reported (assumed decision 9), not fixed here.

- [ ] **Step 7: tarmantria**

```bash
cd ~/.dotfiles && sudo nixos-rebuild switch --flake .#tarmantria
```

Restart qs, then toggle Settings, Interface, "Enable translator" on. Expected: the Translator tab appears after Intelligence without restarting qs. Run Step 1's log comparison, Step 2 (one monitor), Step 3, and Task 2, Step 8 checks 1 to 6 (the spec runs the long-text check, including copy, search, paste and clear, on both hosts).

- [ ] **Step 8: Missing-key default (tarmantria)**

```bash
f=~/.config/illogical-impulse/config.json
command cp "$f" ~/config.json.bak
pkill -f '[q]s-wrapped -c ii'; sleep 1   # stop qs first so the running instance cannot reload and rewrite the old value
jq 'del(.sidebar.translator.enable)' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
hyprctl dispatch exec 'qs -c ii'; sleep 5
jq '.sidebar.translator.enable' "$f"
```

Expected: the Translator tab is present; `jq` prints `null` (ii writes `config.json` only after an option changes, so the key is not back yet) or `true`, never `false`. Restore:

```bash
command mv ~/config.json.bak ~/.config/illogical-impulse/config.json
```

- [ ] **Step 9: taractias**

Skip until its hardware is verified (`hosts/taractias/default.nix`); record it as not run. Task 4, Step 4 already dry-built it.

- [ ] **Step 10: Report**

List each check with pass, fail or not run. No commit unless a check failed and a patch was re-exported.
