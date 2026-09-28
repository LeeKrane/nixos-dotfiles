# Backport end4-pC Fixes into ii — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Carry 8 bug and performance fixes from pctrade/end4-pC into the pinned illogical-impulse Quickshell config as a `git format-patch` series applied at Nix build time.

**Architecture:** Each fix is one commit on the local `krane` branch in a disposable clone of dots-hyprland at the pinned revision. `git format-patch` exports this sub-project's commits into `patches/ii/01-fixes/`. `lib/mk-host.nix` gets a generic loader that applies every `patches/ii/*/` directory in lexical order, and every patch within a directory in lexical order (after the existing cheatsheet patch), through `applyPatches`, producing the `dots-hyprland-patched` source the soymou module copies into `~/.config`.

**Tech Stack:** Nix flakes, home-manager, nixpkgs `applyPatches`, git (`apply`, `format-patch`, `am -3`), Quickshell QML, Python.

**Spec:** `docs/superpowers/specs/2026-09-27-ii-fork-fixes-design.md`

## Global Constraints

- Run every shell block with `bash` (the interactive shell is fish). Use `command cat`, never bare `cat`, in commands you type.
- Pinned dots-hyprland revision: read it with `jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock` (currently `97c5bc651f68092351b24aaa935af708b1e04514`).
- Workspace clone: `~/src/dots-hyprland`, branch `krane`, based on the pinned revision, with `git rerere` enabled. It is disposable; only `patches/ii/01-fixes/*.patch` is committed. The same branch later carries sub-projects 2 to 5, each exported to its own `patches/ii/NN-<name>/` directory (`02-translator`, `03-dock`, `04-agents`, `05-settings`).
- Export command, always exactly: `rm -f ~/.dotfiles/patches/ii/01-fixes/*.patch && git -C ~/src/dots-hyprland format-patch --zero-commit --no-signature --no-numbered -o ~/.dotfiles/patches/ii/01-fixes "$PIN"..krane`. `--zero-commit --no-signature --no-numbered` keeps unchanged patches byte-identical between exports; without `--no-numbered`, subjects become `[PATCH n/m]` once a series has more than one commit. The range `"$PIN"..krane` is only right while the branch holds nothing but this plan's commits; Task 6 tags the end of the series `krane/01-fixes`, and every later export uses the per-directory loop documented there.
- Fork diffs are relative to the ii root. Apply them with `git apply --directory=dots/.config/quickshell/ii`.
- Clone commit messages use this format (from the spec):
  ```
  <subject>

  Backport of pctrade/end4-pC <sha>
  https://github.com/pctrade/end4-pC/commit/<sha>
  Problem: <one or two lines>
  Port: clean | hand-ported (<what was dropped or adapted>)
  Drop when: <concrete condition>
  ```
- Dotfiles repo commit messages: subject line only, no body, no attribution lines. Never push.
- No fork-only features, files or config keys. No public fork.
- `37a9fab`, `204f22f` and `9c7b0e1` are not ported as their own patches (spec, "Dropped during porting"). The pinned background already decodes the wallpaper at its rendered size: `StyledImage` binds `sourceSize` to `width`/`height` times the window's device pixel ratio. `204f22f`'s `configreloaded` routing is part of the `1b51f7a` patch.
- The translator sub-project (`docs/superpowers/specs/2026-09-27-ii-translator-design.md`) adds commits to the same `krane` branch after this plan's commits and exports them to `patches/ii/02-translator/`. Do not reorder or renumber anything to make room for it.

### Checking the built source

Several steps check what Nix actually built. This block prints the patched ii source path for tariognatha:

```bash
cd ~/.dotfiles
gen=$(nix build --no-link --print-out-paths .#nixosConfigurations.tariognatha.config.home-manager.users.krane.home.activationPackage)
iisrc=$(grep -rhoE '/nix/store/[a-z0-9]{32}-dots-hyprland-[a-z-]+' "$gen" | sort -u | head -1)
echo "$iisrc"
```

Before Task 1's wiring the path ends in `-dots-hyprland-cheatsheet-fkeys`; after it, `-dots-hyprland-patched`. A fix is present when the built file equals the clone's file:

```bash
diff -q "$iisrc/dots/.config/quickshell/ii/<file>" ~/src/dots-hyprland/dots/.config/quickshell/ii/<file>
```

(The cheatsheet patch changes only `modules/ii/cheatsheet/`, so every other file matches the clone exactly.)

## Review Focus

1. **Leftover materialyoucolor sed.** If the old `iiPatches` entry survives, it rewrites `3dad196`'s fallback literal and silently turns the dual lookup into a duplicate. Expected: the entry is gone and the built script contains both key names (Task 3, Step 6).
2. **Debounce delaying first paint.** Workspaces and the window title must be correct immediately after qs starts, not 60 ms after the first event (Task 5, Step 8).
3. **Bluetooth false positives.** A device that exports `Battery1` must still show as disconnected once it actually disconnects (Task 4, Step 7).
4. **Missing notifications file.** A fresh host has no `~/.cache/notifications/notifications.json`; qs must start without errors (Task 2, Step 9).

---

### Task 1: Workspace, series wiring and the thumbnail fix

Sets up the clone, exports the first patch (`05b50d9`), and wires `patches/ii/` into `lib/mk-host.nix` with a loader that later sub-projects reuse unchanged.

**Files:**
- Create: `patches/ii/01-fixes/0001-*.patch` (generated)
- Modify: `lib/mk-host.nix` (the `patchedDotfiles` binding and its comment, currently lines 57-69)

**Interfaces:**
- Produces: branch `krane` in `~/src/dots-hyprland`; directory `patches/ii/01-fixes/`; derivation name `dots-hyprland-patched`; the Nix binding `iiSeries` (every patch under `patches/ii/*/`, directories and files each in lexical order). The name avoids `iiPatches`, which already names the sed list in `modules/home/illogical-impulse.nix`.

- [ ] **Step 1: Clone at the pin and create the branch**

```bash
PIN=$(jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock)
git clone https://github.com/end-4/dots-hyprland ~/src/dots-hyprland
git -C ~/src/dots-hyprland switch -c krane "$PIN"
git -C ~/src/dots-hyprland config rerere.enabled true
```

Expected: `Switched to a new branch 'krane'`.

- [ ] **Step 2: Apply and commit `05b50d9`**

```bash
cd ~/src/dots-hyprland
curl -sL https://github.com/pctrade/end4-pC/commit/05b50d9.diff | git apply --directory=dots/.config/quickshell/ii
git add -A
git commit -F - <<'EOF'
fix(ThumbnailImage): atomic thumbnail generation via temp file + mv

Backport of pctrade/end4-pC 05b50d9
https://github.com/pctrade/end4-pC/commit/05b50d9
Problem: concurrent magick processes wrote the same cache file, clobbering each other and regenerating thumbnails on every open (up to ~290% CPU).
Port: clean
Drop when: the pinned modules/common/widgets/ThumbnailImage.qml writes thumbnails to a temp file before moving them into place.
EOF
```

Expected: one commit, 1 file changed.

- [ ] **Step 3: Confirm the fix is not in the current build (failing check)**

Run the "Checking the built source" block, then:

```bash
diff -q "$iisrc/dots/.config/quickshell/ii/modules/common/widgets/ThumbnailImage.qml" ~/src/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ThumbnailImage.qml
```

Expected: `Files ... differ`.

- [ ] **Step 4: Export the series**

```bash
PIN=$(jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock)
mkdir -p ~/.dotfiles/patches/ii/01-fixes
rm -f ~/.dotfiles/patches/ii/01-fixes/*.patch && git -C ~/src/dots-hyprland format-patch --zero-commit --no-signature --no-numbered -o ~/.dotfiles/patches/ii/01-fixes "$PIN"..krane
```

Expected: prints `.../patches/ii/01-fixes/0001-fix-ThumbnailImage-atomic-thumbnail-generation-via-t.patch`.

- [ ] **Step 5: Wire the series into `lib/mk-host.nix`**

Replace the current comment and `patchedDotfiles` binding:

```nix
              # dots-hyprland (`inputs.dotfiles` below), not illogical-flake
              # itself: home-modules/dotfiles.nix copies ~/.config from
              # `inputs.dotfiles` at HM activation, so the cheatsheet QML
              # patched here lives in that separate source, not the one
              # `patched` above rewrites. Cheatsheet's number-key collapsing
              # regex matches F-keys containing a "1" digit (F1, F10, F11),
              # mangling their rendered label, and drops F9 entirely (digit
              # 9, no "1"). See patches/illogical-flake-cheatsheet-fkeys.patch.
              patchedDotfiles = inputs.nixpkgs.legacyPackages.${system}.applyPatches {
                name = "dots-hyprland-cheatsheet-fkeys";
                src = inputs.illogical-flake.inputs.dotfiles;
                patches = [ ../patches/illogical-flake-cheatsheet-fkeys.patch ];
              };
```

with:

```nix
              # dots-hyprland (`inputs.dotfiles` below), not illogical-flake
              # itself: home-modules/dotfiles.nix copies ~/.config from
              # `inputs.dotfiles` at HM activation, so everything patched here
              # lives in that separate source, not the one `patched` above
              # rewrites. Two things are patched in:
              # - Cheatsheet's number-key collapsing regex matches F-keys
              #   containing a "1" digit (F1, F10, F11), mangling their
              #   rendered label, and drops F9 entirely (digit 9, no "1").
              #   See patches/illogical-flake-cheatsheet-fkeys.patch.
              # - Changes carried from pctrade/end4-pC and this repo's own ii
              #   work, kept as `git format-patch` series, one directory per
              #   sub-project under patches/ii/ (01-fixes, 02-translator, ...).
              #   Directories apply in lexical order, and the patches in each
              #   directory in lexical (= commit) order. A new sub-project only
              #   adds a directory. See docs/II-INTEGRATION.md
              #   "Backported fork fixes" for the workflow.
              # `lib` is the bare nixpkgs lib for the same reason
              # `applyPatches` is taken from bare nixpkgs above: anything
              # derived from the module's `config` would recurse infinitely.
              iiSeries =
                let
                  lib = inputs.nixpkgs.lib;
                  root = ../patches/ii;
                  sortedNames =
                    pred: dir:
                    lib.sort lib.lessThan (builtins.attrNames (lib.filterAttrs pred (builtins.readDir dir)));
                  patchesIn =
                    dir:
                    map (n: dir + "/${n}") (
                      sortedNames (n: t: t == "regular" && lib.hasSuffix ".patch" n) dir
                    );
                in
                lib.concatMap (d: patchesIn (root + "/${d}")) (sortedNames (n: t: t == "directory") root);
              patchedDotfiles = inputs.nixpkgs.legacyPackages.${system}.applyPatches {
                name = "dots-hyprland-patched";
                src = inputs.illogical-flake.inputs.dotfiles;
                patches = [ ../patches/illogical-flake-cheatsheet-fkeys.patch ] ++ iiSeries;
              };
```

Flakes only see git-tracked files, so stage the new directory before building:

```bash
cd ~/.dotfiles && git add patches/ii/01-fixes lib/mk-host.nix
```

- [ ] **Step 6: Confirm the fix is in the build (passing check)**

Run the "Checking the built source" block. Expected: `$iisrc` ends in `-dots-hyprland-patched`. Then:

```bash
diff -q "$iisrc/dots/.config/quickshell/ii/modules/common/widgets/ThumbnailImage.qml" ~/src/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ThumbnailImage.qml && echo SAME
```

Expected: `SAME`.

- [ ] **Step 7: Dry-build all hosts**

```bash
cd ~/.dotfiles
for h in tariognatha tarmantria taractias; do nixos-rebuild dry-build --flake .#$h || echo "FAIL $h"; done
```

Expected: no `FAIL` lines.

- [ ] **Step 8: Commit**

```bash
cd ~/.dotfiles
git add patches/ii/01-fixes lib/mk-host.nix
git commit -m "Apply backported end4-pC fixes to dots-hyprland, starting with atomic thumbnail writes"
```

---

### Task 2: Notification fixes

Four clean fork commits, all changing `services/Notifications.qml`, applied in this order: `6f1dc5f`, `2cf76f8`, `342a45b`, `eb76c3d`. The last three apply at a +6 line offset caused by `6f1dc5f`; that is expected and is not fuzz.

**Files:**
- Create: `patches/ii/01-fixes/0002-*.patch` … `0005-*.patch` (generated)

**Interfaces:**
- Consumes: branch `krane` and the wiring from Task 1.

- [ ] **Step 1: Apply and commit `6f1dc5f`**

```bash
cd ~/src/dots-hyprland
curl -sL https://github.com/pctrade/end4-pC/commit/6f1dc5f.diff | git apply --directory=dots/.config/quickshell/ii
git add -A
git commit -F - <<'EOF'
fix(notifications): stop freezing the UI when discarding

Backport of pctrade/end4-pC 6f1dc5f
https://github.com/pctrade/end4-pC/commit/6f1dc5f
Problem: discardNotification() used list.splice(), which emits listChanged per shifted element and re-ran grouping for each, freezing the shell for seconds.
Port: clean
Drop when: the pinned services/Notifications.qml no longer removes notifications with root.list.splice().
EOF
```

- [ ] **Step 2: Apply and commit `2cf76f8`**

```bash
cd ~/src/dots-hyprland
curl -sL https://github.com/pctrade/end4-pC/commit/2cf76f8.diff | git apply --directory=dots/.config/quickshell/ii
git add -A
git commit -F - <<'EOF'
fix(notifications): guard JSON.parse against corrupt notification file

Backport of pctrade/end4-pC 2cf76f8
https://github.com/pctrade/end4-pC/commit/2cf76f8
Problem: a truncated or invalid ~/.cache/notifications/notifications.json made loading throw.
Port: clean
Drop when: the pinned services/Notifications.qml wraps the notifications-file JSON.parse in try/catch.
EOF
```

- [ ] **Step 3: Apply and commit `342a45b`**

```bash
cd ~/src/dots-hyprland
curl -sL https://github.com/pctrade/end4-pC/commit/342a45b.diff | git apply --directory=dots/.config/quickshell/ii
git add -A
git commit -F - <<'EOF'
fix(notifications): guard against null timer in cancelTimeout

Backport of pctrade/end4-pC 342a45b
https://github.com/pctrade/end4-pC/commit/342a45b
Problem: cancelTimeout dereferenced a timer that can already be null, throwing a TypeError.
Port: clean
Drop when: the pinned services/Notifications.qml cancelTimeout checks the timer for null.
EOF
```

- [ ] **Step 4: Apply and commit `eb76c3d`**

```bash
cd ~/src/dots-hyprland
curl -sL https://github.com/pctrade/end4-pC/commit/eb76c3d.diff | git apply --directory=dots/.config/quickshell/ii
git add -A
git commit -F - <<'EOF'
fix(notifications): guard against undefined action in attemptInvokeAction

Backport of pctrade/end4-pC eb76c3d
https://github.com/pctrade/end4-pC/commit/eb76c3d
Problem: attemptInvokeAction threw when the requested action no longer existed on the notification.
Port: clean
Drop when: the pinned services/Notifications.qml attemptInvokeAction checks the action for undefined.
EOF
```

- [ ] **Step 5: Confirm the fixes are not in the current build (failing check)**

Run the "Checking the built source" block, then:

```bash
diff -q "$iisrc/dots/.config/quickshell/ii/services/Notifications.qml" ~/src/dots-hyprland/dots/.config/quickshell/ii/services/Notifications.qml
```

Expected: `Files ... differ`.

- [ ] **Step 6: Export the series**

```bash
PIN=$(jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock)
rm -f ~/.dotfiles/patches/ii/01-fixes/*.patch && git -C ~/src/dots-hyprland format-patch --zero-commit --no-signature --no-numbered -o ~/.dotfiles/patches/ii/01-fixes "$PIN"..krane
cd ~/.dotfiles && git status --short patches/ii/01-fixes
```

Expected: five patch files; `git status` shows `0001-*` unchanged and `0002-*` to `0005-*` new (`??`).

- [ ] **Step 7: Confirm the fixes are in the build (passing check)**

```bash
cd ~/.dotfiles && git add patches/ii/01-fixes
```

Run the "Checking the built source" block, then:

```bash
for f in services/Notifications.qml modules/common/widgets/NotificationGroup.qml; do
  diff -q "$iisrc/dots/.config/quickshell/ii/$f" ~/src/dots-hyprland/dots/.config/quickshell/ii/$f && echo "SAME $f"
done
```

Expected: `SAME` for both files.

- [ ] **Step 8: Commit, one repo commit per fix**

```bash
cd ~/.dotfiles
git reset -q
git add patches/ii/01-fixes/0002-*.patch && git commit -m "Backport end4-pC fix for the UI freeze when discarding notifications"
git add patches/ii/01-fixes/0003-*.patch && git commit -m "Backport end4-pC guard against a corrupt notifications file"
git add patches/ii/01-fixes/0004-*.patch && git commit -m "Backport end4-pC guard against a null notification timer"
git add patches/ii/01-fixes/0005-*.patch && git commit -m "Backport end4-pC guard against an undefined notification action"
```

- [ ] **Step 9: Record the missing-file check for Task 7**

No code here. Task 7, Step 4 removes `~/.cache/notifications/notifications.json` and confirms qs starts cleanly (Review Focus 4).

---

### Task 3: materialyoucolor key name, replacing the sed hack

**Files:**
- Create: `patches/ii/01-fixes/0006-*.patch` (generated)
- Modify: `modules/home/illogical-impulse.nix` (remove the first `iiPatches` entry, the one whose `file` ends in `generate_colors_material.py`)

**Interfaces:**
- Consumes: branch `krane`, wiring from Task 1.

- [ ] **Step 1: Apply and commit `3dad196`**

```bash
cd ~/src/dots-hyprland
curl -sL https://github.com/pctrade/end4-pC/commit/3dad196.diff | git apply --directory=dots/.config/quickshell/ii
git add -A
git commit -F - <<'EOF'
fix(colors): support materialyoucolor >= 3 palette key name

Backport of pctrade/end4-pC 3dad196
https://github.com/pctrade/end4-pC/commit/3dad196
Problem: materialyoucolor 3.x renamed primary_paletteKeyColor to primaryPaletteKeyColor, so switchwall.sh threw KeyError and left material_colors.scss empty.
Port: clean. Replaces the iiPatches sed entry in modules/home/illogical-impulse.nix.
Drop when: the pinned scripts/colors/generate_colors_material.py reads primaryPaletteKeyColor.
EOF
```

- [ ] **Step 2: Export the series**

```bash
PIN=$(jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock)
rm -f ~/.dotfiles/patches/ii/01-fixes/*.patch && git -C ~/src/dots-hyprland format-patch --zero-commit --no-signature --no-numbered -o ~/.dotfiles/patches/ii/01-fixes "$PIN"..krane
```

Expected: six files; `0006-fix-colors-support-materialyoucolor-3-palette-key-na.patch` is new.

- [ ] **Step 3: Show the sed entry still exists (failing check)**

```bash
grep -c 'primary_paletteKeyColor' ~/.dotfiles/modules/home/illogical-impulse.nix
```

Expected: a number greater than 0.

- [ ] **Step 4: Remove the sed entry**

In `modules/home/illogical-impulse.nix`, delete this whole list element from `iiPatches` (the comment block and the attribute set):

```nix
    {
      # ii pins dots-hyprland at a revision whose generate_colors_material.py still reads
      # material_colors['primary_paletteKeyColor'], but nixpkgs' python3Packages.materialyoucolor
      # (3.0.4) renamed that key to primaryPaletteKeyColor, so every switchwall.sh run throws
      # KeyError and leaves material_colors.scss (and kitty's generated theme) empty. Remove this
      # once ii's pinned rev or the packaged materialyoucolor version makes the names agree again.
      file = "${config.home.homeDirectory}/.config/quickshell/ii/scripts/colors/generate_colors_material.py";
      sed = "s/primary_paletteKeyColor/primaryPaletteKeyColor/g";
      why = "materialyoucolor 3.0.4 renamed primary_paletteKeyColor to primaryPaletteKeyColor";
    }
```

- [ ] **Step 5: Confirm the sed entry is gone (passing check)**

```bash
grep -c 'primary_paletteKeyColor' ~/.dotfiles/modules/home/illogical-impulse.nix
```

Expected: `0`.

- [ ] **Step 6: Confirm the built script has both key names**

```bash
cd ~/.dotfiles && git add patches/ii/01-fixes modules/home/illogical-impulse.nix
```

Run the "Checking the built source" block, then:

```bash
grep -c "get('primaryPaletteKeyColor')" "$iisrc/dots/.config/quickshell/ii/scripts/colors/generate_colors_material.py"
grep -c "get('primary_paletteKeyColor')" "$iisrc/dots/.config/quickshell/ii/scripts/colors/generate_colors_material.py"
grep -c "paletteKeyColor" "$gen/activate"
```

Expected: `1`, `1`, `0`: both lookups are in the built script, and activation no longer runs the sed.

- [ ] **Step 7: Commit**

```bash
cd ~/.dotfiles
git add patches/ii/01-fixes/0006-*.patch modules/home/illogical-impulse.nix
git commit -m "Replace the materialyoucolor sed hack with the backported end4-pC key-name fix"
```

---

### Task 4: Bluetooth connected state (hand-port of `d116eef`)

**Files:**
- Create: `patches/ii/01-fixes/0007-*.patch` (generated)

**Interfaces:**
- Produces: `BluetoothStatus.isConnected(device): bool` on the `BluetoothStatus` singleton.
- Consumes: Quickshell `BluetoothDevice.connected` and `BluetoothDevice.batteryAvailable` (already used by the pinned `BluetoothDeviceItem.qml:62`).

- [ ] **Step 1: Apply the hand-port**

```bash
cd ~/src/dots-hyprland
git apply --ignore-whitespace <<'EOF'
--- a/dots/.config/quickshell/ii/services/BluetoothStatus.qml
+++ b/dots/.config/quickshell/ii/services/BluetoothStatus.qml
@@ -11,9 +11,18 @@
 
     readonly property bool available: Bluetooth.adapters.values.length > 0
     readonly property bool enabled: Bluetooth.defaultAdapter?.enabled ?? false
-    readonly property BluetoothDevice firstActiveDevice: Bluetooth.defaultAdapter?.devices.values.find(device => device.connected) ?? null
-    readonly property int activeDeviceCount: Bluetooth.defaultAdapter?.devices.values.filter(device => device.connected).length ?? 0
-    readonly property bool connected: Bluetooth.devices.values.some(d => d.connected)
+
+    // BlueZ can leave Device1.Connected false when a device reconnects on its
+    // own, while audio, AVRCP and battery reporting are all live
+    // (https://github.com/bluez/bluez/issues/2485). Battery1 is only exported
+    // while a device is connected, so count it as a connection too.
+    function isConnected(device): bool {
+        return !!device && (device.connected || device.batteryAvailable);
+    }
+
+    readonly property BluetoothDevice firstActiveDevice: Bluetooth.defaultAdapter?.devices.values.find(device => root.isConnected(device)) ?? null
+    readonly property int activeDeviceCount: Bluetooth.defaultAdapter?.devices.values.filter(device => root.isConnected(device)).length ?? 0
+    readonly property bool connected: Bluetooth.devices.values.some(d => root.isConnected(d))
 
     function sortFunction(a, b) {
         // Ones with meaningful names before MAC addresses
@@ -26,9 +35,9 @@
         // Alphabetical by name
         return a.name.localeCompare(b.name);
     }
-    property list<var> connectedDevices: Bluetooth.devices.values.filter(d => d.connected).sort(sortFunction)
-    property list<var> pairedButNotConnectedDevices: Bluetooth.devices.values.filter(d => d.paired && !d.connected).sort(sortFunction)
-    property list<var> unpairedDevices: Bluetooth.devices.values.filter(d => !d.paired && !d.connected).sort(sortFunction)
+    property list<var> connectedDevices: Bluetooth.devices.values.filter(d => root.isConnected(d)).sort(sortFunction)
+    property list<var> pairedButNotConnectedDevices: Bluetooth.devices.values.filter(d => d.paired && !root.isConnected(d)).sort(sortFunction)
+    property list<var> unpairedDevices: Bluetooth.devices.values.filter(d => !d.paired && !root.isConnected(d)).sort(sortFunction)
     property list<var> friendlyDeviceList: [
         ...connectedDevices,
         ...pairedButNotConnectedDevices,
--- a/dots/.config/quickshell/ii/modules/ii/sidebarRight/bluetoothDevices/BluetoothDeviceItem.qml
+++ b/dots/.config/quickshell/ii/modules/ii/sidebarRight/bluetoothDevices/BluetoothDeviceItem.qml
@@ -51,14 +51,14 @@
                     textFormat: Text.PlainText
                 }
                 StyledText {
-                    visible: (root.device?.connected || root.device?.paired) ?? false
+                    visible: (BluetoothStatus.isConnected(root.device) || root.device?.paired) ?? false
                     Layout.fillWidth: true
                     font.pixelSize: Appearance.font.pixelSize.smaller
                     color: Appearance.colors.colSubtext
                     elide: Text.ElideRight
                     text: {
                         if (!root.device?.paired) return "";
-                        let statusText = root.device?.connected ? Translation.tr("Connected") : Translation.tr("Paired");
+                        let statusText = BluetoothStatus.isConnected(root.device) ? Translation.tr("Connected") : Translation.tr("Paired");
                         if (!root.device?.batteryAvailable) return statusText;
                         statusText += ` • ${Math.round(root.device?.battery * 100)}%`;
                         return statusText;
@@ -100,10 +100,10 @@
                 }
             }
             ActionButton {
-                buttonText: root.device?.connected ? Translation.tr("Disconnect") : Translation.tr("Connect")
+                buttonText: BluetoothStatus.isConnected(root.device) ? Translation.tr("Disconnect") : Translation.tr("Connect")
 
                 onClicked: {
-                    if (root.device?.connected) {
+                    if (BluetoothStatus.isConnected(root.device)) {
                         root.device.disconnect();
                     } else {
                         root.device.connect();
EOF
git diff --stat
```

Expected: `2 files changed, 19 insertions(+), 10 deletions(-)`.

- [ ] **Step 2: Confirm no `.connected` reads remain outside the helper**

```bash
grep -n '\.connected\b' ~/src/dots-hyprland/dots/.config/quickshell/ii/services/BluetoothStatus.qml ~/src/dots-hyprland/dots/.config/quickshell/ii/modules/ii/sidebarRight/bluetoothDevices/BluetoothDeviceItem.qml
```

Expected: exactly one match, inside `isConnected` (`device.connected || device.batteryAvailable`). The `\b` keeps `...connectedDevices` out of the count.

- [ ] **Step 3: Commit in the clone**

```bash
cd ~/src/dots-hyprland
git add -A
git commit -F - <<'EOF'
fix(bluetooth): count devices BlueZ fails to mark as connected

Backport of pctrade/end4-pC d116eef
https://github.com/pctrade/end4-pC/commit/d116eef
Problem: after a headset reconnects on its own, BlueZ 5.87 can leave Device1.Connected false while audio streams (bluez/bluez#2485), so ii showed it as disconnected.
Port: hand-ported. Same rule (connected or Battery1 exported) as one BluetoothStatus.isConnected() helper used by every connected read in BluetoothStatus.qml and BluetoothDeviceItem.qml; kept the pin's split between defaultAdapter.devices and Bluetooth.devices.
Drop when: bluez/bluez#2485 is fixed in the packaged BlueZ, or the pinned services/BluetoothStatus.qml treats batteryAvailable as connected.
EOF
```

- [ ] **Step 4: Confirm the fix is not in the current build (failing check)**

Run the "Checking the built source" block, then:

```bash
grep -c 'function isConnected' "$iisrc/dots/.config/quickshell/ii/services/BluetoothStatus.qml"
```

Expected: `0`.

- [ ] **Step 5: Export the series**

```bash
PIN=$(jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock)
rm -f ~/.dotfiles/patches/ii/01-fixes/*.patch && git -C ~/src/dots-hyprland format-patch --zero-commit --no-signature --no-numbered -o ~/.dotfiles/patches/ii/01-fixes "$PIN"..krane
```

- [ ] **Step 6: Confirm the fix is in the build (passing check)**

```bash
cd ~/.dotfiles && git add patches/ii/01-fixes
```

Run the "Checking the built source" block, then:

```bash
for f in services/BluetoothStatus.qml modules/ii/sidebarRight/bluetoothDevices/BluetoothDeviceItem.qml; do
  diff -q "$iisrc/dots/.config/quickshell/ii/$f" ~/src/dots-hyprland/dots/.config/quickshell/ii/$f && echo "SAME $f"
done
```

Expected: `SAME` for both.

- [ ] **Step 7: Record the false-positive check for Task 7**

No code here. Task 7, Step 6 powers the headset off and confirms ii shows it as `Paired`, not `Connected`, within 10 s (Review Focus 3).

- [ ] **Step 8: Commit**

```bash
cd ~/.dotfiles
git add patches/ii/01-fixes/0007-*.patch
git commit -m "Backport end4-pC workaround for BlueZ not marking reconnected devices as connected"
```

---

### Task 5: Hyprland IPC debounce (hand-port of `1b51f7a`, with `configreloaded` routing)

**Files:**
- Create: `patches/ii/01-fixes/0008-*.patch` (generated)

**Interfaces:**
- Produces: `HyprlandData.queueUpdate(clients, workspaces, monitors, layers)`; `updateWindowList`, `updateLayers`, `updateMonitors`, `updateWorkspaces`, `updateAll` keep their names and now queue work instead of running it.
- Consumes: the pinned `HyprlandData.qml` processes `getClients`, `getMonitors`, `getLayers`, `getWorkspaces`, `getActiveWorkspace`.

- [ ] **Step 1: Apply the debounce and routing**

```bash
cd ~/src/dots-hyprland
git apply --ignore-whitespace <<'EOF'
--- a/dots/.config/quickshell/ii/services/HyprlandData.qml
+++ b/dots/.config/quickshell/ii/services/HyprlandData.qml
@@ -46,28 +46,71 @@
 
     // Internals
 
+    // Coalesce bursts of raw Hyprland events (e.g. dragging a window fires
+    // dozens of "movewindow" events per second) into a single round of
+    // hyprctl queries, and only re-run the queries an event can actually
+    // affect instead of all five on every event.
+    property bool _pendingClients: false
+    property bool _pendingMonitors: false
+    property bool _pendingLayers: false
+    property bool _pendingWorkspaces: false
+
+    Timer {
+        id: eventDebounceTimer
+        interval: 60
+        repeat: false
+        onTriggered: {
+            if (root._pendingClients) {
+                getClients.running = false;
+                getClients.running = true;
+                root._pendingClients = false;
+            }
+            if (root._pendingMonitors) {
+                getMonitors.running = false;
+                getMonitors.running = true;
+                root._pendingMonitors = false;
+            }
+            if (root._pendingLayers) {
+                getLayers.running = false;
+                getLayers.running = true;
+                root._pendingLayers = false;
+            }
+            if (root._pendingWorkspaces) {
+                getWorkspaces.running = false;
+                getWorkspaces.running = true;
+                getActiveWorkspace.running = false;
+                getActiveWorkspace.running = true;
+                root._pendingWorkspaces = false;
+            }
+        }
+    }
+
+    function queueUpdate(clients = false, workspaces = false, monitors = false, layers = false) {
+        if (clients) root._pendingClients = true;
+        if (workspaces) root._pendingWorkspaces = true;
+        if (monitors) root._pendingMonitors = true;
+        if (layers) root._pendingLayers = true;
+        eventDebounceTimer.restart();
+    }
+
     function updateWindowList() {
-        getClients.running = true;
+        queueUpdate(true, false, false, false);
     }
 
     function updateLayers() {
-        getLayers.running = true;
+        queueUpdate(false, false, false, true);
     }
 
     function updateMonitors() {
-        getMonitors.running = true;
+        queueUpdate(false, false, true, false);
     }
 
     function updateWorkspaces() {
-        getWorkspaces.running = true;
-        getActiveWorkspace.running = true;
+        queueUpdate(false, true, false, false);
     }
 
     function updateAll() {
-        updateWindowList();
-        updateMonitors();
-        updateLayers();
-        updateWorkspaces();
+        queueUpdate(true, true, true, true);
     }
 
     function biggestWindowForWorkspace(workspaceId) {
@@ -80,7 +123,11 @@
     }
 
     Component.onCompleted: {
-        updateAll();
+        getClients.running = true;
+        getMonitors.running = true;
+        getLayers.running = true;
+        getWorkspaces.running = true;
+        getActiveWorkspace.running = true;
     }
 
     Connections {
@@ -88,7 +135,33 @@
 
         function onRawEvent(event) {
             // console.log("Hyprland raw event:", event.name);
-            if (["openlayer", "closelayer", "screencast"].includes(event.name)) return;
-            updateAll()
+            const name = event.name;
+            if (["screencast", "submap", "activelayout"].includes(name)) return;
+
+            if (name === "openlayer" || name === "closelayer") {
+                root.queueUpdate(false, false, false, true);
+            } else if (name.startsWith("moveworkspace")) {
+                // Background.qml filters its window list by win.monitor, so a
+                // workspace moving to another monitor needs fresh clients too.
+                root.queueUpdate(true, true, true, false);
+            } else if (name.startsWith("workspace") || name.startsWith("createworkspace") || name.startsWith("destroyworkspace") || name === "renameworkspace") {
+                root.queueUpdate(false, true, true, false);
+            } else if (name.startsWith("openwindow") || name.startsWith("closewindow") || name.startsWith("movewindow")) {
+                root.queueUpdate(true, true, false, false);
+            } else if (name.startsWith("window") || name.startsWith("activewindow") || name === "changefloatingmode" || name === "pin" || name === "urgent" || name === "minimized") {
+                root.queueUpdate(true, false, false, false);
+            } else if (name === "fullscreen") {
+                root.queueUpdate(true, true, false, false);
+            } else if (name.startsWith("monitor")) {
+                // monitoradded[v2]/monitorremoved[v2]: hotplug can also
+                // reshuffle which clients report which monitor.
+                root.queueUpdate(true, true, true, false);
+            } else if (name === "focusedmon") {
+                root.queueUpdate(false, true, true, false);
+            } else if (name.startsWith("activespecial")) {
+                root.queueUpdate(false, true, true, false);
+            } else {
+                root.queueUpdate(true, true, false, false);
+            }
         }
     }
EOF
```

- [ ] **Step 2: Add the `configreloaded` branch**

```bash
cd ~/src/dots-hyprland
git apply --ignore-whitespace <<'EOF'
--- a/dots/.config/quickshell/ii/services/HyprlandData.qml
+++ b/dots/.config/quickshell/ii/services/HyprlandData.qml
@@ -160,6 +160,11 @@
                 root.queueUpdate(false, true, true, false);
             } else if (name.startsWith("activespecial")) {
                 root.queueUpdate(false, true, true, false);
+            } else if (name === "configreloaded") {
+                // A Hyprland config reload can add/remove monitors or change
+                // their layout, which also reshuffles workspace-monitor
+                // bindings.
+                root.queueUpdate(false, true, true, false);
             } else {
                 root.queueUpdate(true, true, false, false);
             }
EOF
grep -c 'configreloaded' dots/.config/quickshell/ii/services/HyprlandData.qml
```

Expected: `1`.

- [ ] **Step 3: Confirm no other file calls the removed immediate-run behavior**

`updateAll()` and friends now queue instead of running. Check callers still behave:

```bash
grep -rn 'HyprlandData\.update' ~/src/dots-hyprland/dots/.config/quickshell/ii --include=*.qml
```

Expected: no output (at the pin, only `HyprlandData.qml` itself calls these functions). If a caller shows up and reads the data synchronously right after the call, stop and report it instead of committing.

- [ ] **Step 4: Commit in the clone**

```bash
cd ~/src/dots-hyprland
git add -A
git commit -F - <<'EOF'
perf(hyprland): debounce raw events and selectively route IPC queries

Backport of pctrade/end4-pC 1b51f7a, plus the intent of 204f22f
https://github.com/pctrade/end4-pC/commit/1b51f7a
https://github.com/pctrade/end4-pC/commit/204f22f
Problem: every raw Hyprland event ran all five hyprctl queries; dragging a window fires dozens of events per second.
Port: hand-ported. Dropped the fork's WM.compositor guards (no compositor abstraction at the pin). Added a configreloaded branch that refreshes monitors and workspaces; 204f22f itself only changes a fork-only settings component. Widened the fork's routing so workspace and activespecial events also refresh monitors, fullscreen refreshes workspaces, and openlayer/closelayer refresh layers, since consumers read those. Also refreshes clients on moveworkspace and monitor hotplug, and matches Hyprland's minimized event name.
Drop when: the pinned services/HyprlandData.qml debounces onRawEvent.
EOF
```

- [ ] **Step 5: Confirm the fix is not in the current build (failing check)**

Run the "Checking the built source" block, then:

```bash
grep -c 'eventDebounceTimer' "$iisrc/dots/.config/quickshell/ii/services/HyprlandData.qml"
```

Expected: `0`.

- [ ] **Step 6: Export the series**

```bash
PIN=$(jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock)
rm -f ~/.dotfiles/patches/ii/01-fixes/*.patch && git -C ~/src/dots-hyprland format-patch --zero-commit --no-signature --no-numbered -o ~/.dotfiles/patches/ii/01-fixes "$PIN"..krane
```

- [ ] **Step 7: Confirm the fix is in the build (passing check)**

```bash
cd ~/.dotfiles && git add patches/ii/01-fixes
```

Run the "Checking the built source" block, then:

```bash
diff -q "$iisrc/dots/.config/quickshell/ii/services/HyprlandData.qml" ~/src/dots-hyprland/dots/.config/quickshell/ii/services/HyprlandData.qml && echo SAME
```

Expected: `SAME`.

- [ ] **Step 8: Record the first-paint check for Task 7**

No code here. Task 7, Step 7 restarts qs and confirms workspaces and the window title are correct at once, before any event (Review Focus 2).

- [ ] **Step 9: Commit**

```bash
cd ~/.dotfiles
git add patches/ii/01-fixes/0008-*.patch
git commit -m "Backport end4-pC debounce for Hyprland IPC events"
```

---

### Task 6: Documentation

**Files:**
- Modify: `docs/II-INTEGRATION.md` (remove the materialyoucolor bullet, lines 210-215 under `## Patched files`; add a new `##` section after the whole `## Patched files` section, directly before `## Verifying on the target`)

- [ ] **Step 1: Remove the materialyoucolor bullet**

Delete this bullet from the `## Patched files` list:

```markdown
- `~/.config/quickshell/ii/scripts/colors/generate_colors_material.py`:
  `s/primary_paletteKeyColor/primaryPaletteKeyColor/g`. ii's pinned rev
  reads the old `materialyoucolor` key name; nixpkgs' packaged
  `materialyoucolor` (3.0.4) renamed it, so unpatched `switchwall.sh`
  throws `KeyError` and leaves `material_colors.scss` empty. Remove once
  the pinned rev or the packaged version makes the names agree again.
```

- [ ] **Step 2: Add the "Backported fork fixes" section**

Insert directly before `## Verifying on the target`, after the whole `## Patched files` section (its `kraneIiHyprReload` paragraph and `### Preserved files` stay above the new section):

````markdown
## Backported fork fixes

`patches/ii/` holds one `git format-patch` series per sub-project:
`01-fixes` (fixes from [pctrade/end4-pC](https://github.com/pctrade/end4-pC)),
then `02-translator`, `03-dock`, `04-agents` and `05-settings` as they land.
`lib/mk-host.nix` applies them with `applyPatches`, after the cheatsheet
patch, to build the `dots-hyprland-patched` source the soymou module copies:
directories in lexical order, and the files in each directory in lexical
order, which is commit order. The table below covers `01-fixes`. Each patch's commit message records the fork
commit, the problem, how it was ported and when to drop it.

| Patch | Fork commit | Port | Drop when |
|---|---|---|---|
| `0001` thumbnail temp file + `mv` | `05b50d9` | clean | pinned `ThumbnailImage.qml` writes via a temp file |
| `0002` notification discard freeze | `6f1dc5f` | clean | pinned `Notifications.qml` no longer uses `list.splice()` to discard |
| `0003` corrupt notifications file | `2cf76f8` | clean | pinned `Notifications.qml` wraps the file `JSON.parse` in try/catch |
| `0004` null notification timer | `342a45b` | clean | pinned `cancelTimeout` checks for null |
| `0005` undefined notification action | `eb76c3d` | clean | pinned `attemptInvokeAction` checks for undefined |
| `0006` materialyoucolor key name | `3dad196` | clean | pinned `generate_colors_material.py` reads `primaryPaletteKeyColor` |
| `0007` BlueZ connected state | `d116eef` | hand-ported | bluez#2485 fixed, or pinned `BluetoothStatus.qml` counts `batteryAvailable` |
| `0008` Hyprland IPC debounce | `1b51f7a` (+ `204f22f` intent) | hand-ported, routing widened | pinned `HyprlandData.qml` debounces `onRawEvent` |

Not portable: `37a9fab` (optimizes CPU-temperature and disk readers that the
pinned `ResourceUsage.qml` does not have), `204f22f` as its own patch (it
changes only a fork-only settings component) and `9c7b0e1` (the pinned
`Background.qml` wallpaper is a `StyledImage`, which already decodes at the
rendered size times the device pixel ratio; the fork's other hunks touch
fork-only files or a fork-only config key).

### Workflow

The clone at `~/src/dots-hyprland` is a disposable workspace; the patch files
are the source of truth. One local branch, `krane`, holds every sub-project's
commits in order. A lightweight tag `krane/<dir>` (for example
`krane/01-fixes`) marks the last commit of each sub-project; the tags exist
only in the clone and are recreated by the apply loop. `git rerere` records
each conflict resolution so the next pin bump replays it.

```sh
PIN=$(jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock)
git clone https://github.com/end-4/dots-hyprland ~/src/dots-hyprland   # once
cd ~/src/dots-hyprland
git config rerere.enabled true
git fetch origin
git switch -C krane "$PIN"
# apply every series in order and tag the end of each
for d in ~/.dotfiles/patches/ii/*/; do
  git am -3 "$d"*.patch || break   # on a conflict: resolve, `git am --continue`, tag, resume from the next directory
  git tag -f "krane/$(basename "$d")"
done
# add, edit or drop commits with ordinary git commands, then move any tag
# whose commit was rewritten (tags do not follow a rebase)
# export every series again
prev="$PIN"
for d in ~/.dotfiles/patches/ii/*/; do
  n=$(basename "$d")
  rm -f "$d"*.patch
  git format-patch --zero-commit --no-signature --no-numbered -o "$d" "$prev..krane/$n"
  prev="krane/$n"
done
```

A new sub-project creates its `patches/ii/NN-<name>/` directory and tags its
last commit `krane/NN-<name>` before exporting. Nothing in `lib/mk-host.nix`
changes.

On a pin bump, run `nix flake update dots-hyprland` first, then the same
steps. `git am -3` stops at a conflict; resolve it with git's tools and run
`git am --continue`. A patch that no longer applies otherwise fails the
`applyPatches` build, and `nixos-rebuild` names the file.

To remove one fix, drop its commit (`git am --skip` while re-applying, or
`git rebase -i` afterwards) and export again. Deleting a patch file directly
only works when no later patch changes the same file.

### When to stop using patches

Stay with patch series (decided in the settings spec,
`docs/superpowers/specs/2026-09-27-ii-settings-design.md`). Re-evaluate a
private fork of dots-hyprland as the flake input if:

- a pin bump needs more than 5 hand-resolved conflict hunks, or more than one
  sitting; or
- the user sets up a private remote that every host and the docker check can
  already reach; or
- upstream ii ships its own rewrite of settings that overlaps the settings
  port.
````

- [ ] **Step 3: Check the workflow block against reality**

```bash
PIN=$(jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock)
cd ~/src/dots-hyprland
git tag -f krane/01-fixes krane
git switch -C krane-check "$PIN"
for d in ~/.dotfiles/patches/ii/*/; do git am -3 "$d"*.patch || break; done
git diff --stat krane krane-check
git switch krane && git branch -D krane-check
prev="$PIN"
for d in ~/.dotfiles/patches/ii/*/; do
  n=$(basename "$d")
  rm -f "$d"*.patch
  git format-patch --zero-commit --no-signature --no-numbered -o "$d" "$prev..krane/$n"
  prev="krane/$n"
done
git -C ~/.dotfiles status --short patches/ii
```

Expected: `git am` applies all 8 patches; `git diff --stat` prints nothing; the
export loop rewrites the 8 files and `git status` prints nothing (the
documented loop reproduces the committed series byte for byte).
The tag `krane/01-fixes` stays; later sub-projects export relative to it.

- [ ] **Step 4: Commit**

```bash
cd ~/.dotfiles
git add docs/II-INTEGRATION.md
git commit -m "Document the backported end4-pC fix series and its workflow"
```

---

### Task 7: Switch and runtime acceptance checks

Manual checks from the spec. Record each result (pass, fail, not run and why) in the task report. A failed check means dropping that fix's commit in the clone (`git -C ~/src/dots-hyprland rebase --onto "$C^" "$C" krane`, with `C` the fix's commit), moving the tag (`git tag -f krane/01-fixes krane`), exporting with the loop from Task 6, and committing the removal; do not patch around it here.

**Files:** none changed unless a fix is dropped.

- [ ] **Step 1: Switch tariognatha and capture the baseline log**

Before switching, save the current log for comparison:

```bash
qs log -c ii > $XDG_RUNTIME_DIR/qs-before.log 2>&1 || true
cd ~/.dotfiles && sudo nixos-rebuild switch --flake .#tariognatha
```

- [ ] **Step 2: Restart qs and compare logs**

```bash
pkill -f '[q]s-wrapped -c ii'; hyprctl dispatch exec 'qs -c ii'
sleep 5; qs log -c ii > $XDG_RUNTIME_DIR/qs-after.log 2>&1 || true
grep -iE 'error|warn|TypeError|ReferenceError' $XDG_RUNTIME_DIR/qs-after.log | sort -u > $XDG_RUNTIME_DIR/qs-after.err
grep -iE 'error|warn|TypeError|ReferenceError' $XDG_RUNTIME_DIR/qs-before.log | sort -u > $XDG_RUNTIME_DIR/qs-before.err
comm -13 $XDG_RUNTIME_DIR/qs-before.err $XDG_RUNTIME_DIR/qs-after.err
```

Expected: no output (no new errors or warnings). Delete the four `$XDG_RUNTIME_DIR/qs-*` files afterwards.

- [ ] **Step 3: Colors (`3dad196`)**

Change the wallpaper through ii's wallpaper selector. Then:

```bash
test -s ~/.local/state/quickshell/user/generated/material_colors.scss && echo OK
```

Expected: `OK`, and kitty and Neovim recolor.

- [ ] **Step 4: Notifications (`6f1dc5f`, `2cf76f8`, `342a45b`, `eb76c3d`)**

```bash
for i in $(seq 12); do notify-send -a test "n$i" "body $i"; done
```

Swipe the `test` group away: the rest slide up with no visible freeze. Then:

```bash
command cp ~/.cache/notifications/notifications.json ~/notifications.json.bak
printf '{"broken' > ~/.cache/notifications/notifications.json
pkill -f '[q]s-wrapped -c ii'; hyprctl dispatch exec 'qs -c ii'; sleep 5
qs log -c ii | grep -iE 'TypeError|SyntaxError' | tail -3
rm ~/.cache/notifications/notifications.json
pkill -f '[q]s-wrapped -c ii'; hyprctl dispatch exec 'qs -c ii'; sleep 5
qs log -c ii | grep -iE 'TypeError|SyntaxError' | tail -3
command mv ~/notifications.json.bak ~/.cache/notifications/notifications.json
notify-send -a test -A ok=OK "action test" "click OK"; notify-send -a test "plain" "dismiss me"
```

Expected: qs starts in both cases and the log shows a handled parse message at most, no uncaught `SyntaxError` or `TypeError`. Clicking `OK` and dismissing the plain notification log no `TypeError`.

- [ ] **Step 5: Thumbnails (`05b50d9`)**

```bash
rm -rf ~/.cache/thumbnails/{normal,large,x-large,xx-large}
```

Open ii's wallpaper selector (at the pin, the only user of `ThumbnailImage`), wait for thumbnails, close it, open it again while running:

```bash
for i in $(seq 20); do pgrep -c magick; sleep 0.2; done | sort -u
```

Expected: during the second open the output is only `0`.

- [ ] **Step 6: Bluetooth (`d116eef`)**

Connect the JBL headset and play audio. Find its path and check BlueZ:

```bash
busctl tree org.bluez | grep dev_
busctl get-property org.bluez /org/bluez/hci0/dev_XX_XX_XX_XX_XX_XX org.bluez.Device1 Connected
```

(Replace the path with the one from the first command.) Expected: ii shows the headset as `Connected` whether BlueZ reports `true` or `false`. Then power the headset off: within 10 s ii shows it as `Paired`, not `Connected`.

- [ ] **Step 7: Hyprland debounce and hotplug (`1b51f7a`)**

First paint: restart qs; workspaces and the active window title are correct at once.

Routing: switch to an empty workspace; the bar's active-window text changes at once. Toggle a special workspace; the bar's special-workspace indicator follows.

Event load: in the clone, temporarily add `console.log("hyprland refresh")` as the first line of `eventDebounceTimer.onTriggered`, copy that one file over the installed one, restart qs, drag a window for 10 s, then:

```bash
qs log -c ii | grep -c 'hyprland refresh'
```

Expected: far fewer refreshes than 10 s of events (roughly one per 60 ms at most, and none while the window is still). Afterwards `git -C ~/src/dots-hyprland checkout -- .` and switch again to restore the built file.

Hotplug: unplug DP-1, wait, plug it back, then run `hyprctl reload`. Expected: the bar leaves and returns and workspaces stay on the right monitors, with no qs restart.

- [ ] **Step 8: Laptops**

On tarmantria: `sudo nixos-rebuild switch --flake .#tarmantria`, then Steps 2, 3 and 4. Run the hotplug part of Step 7 if an external monitor is available; otherwise record it as not run. taractias: skip until its hardware is verified (`hosts/taractias/default.nix`), and record that.

- [ ] **Step 9: Report**

List each check with pass, fail or not run. No commit unless a fix was dropped.
