# End4-pC Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `patches/ii/09-end4pc-fixes` series: ten fixes from pctrade/end4-pC since `dc2ca26`, one commit each on the `krane` branch of `~/src/dots-hyprland`, exported into `~/.dotfiles/patches/ii/09-end4pc-fixes/`.

**Architecture:** The patch files are the source of truth; `~/src/dots-hyprland` is a disposable workspace. Each fix is a commit on branch `krane` (paths under `dots/.config/quickshell/ii/`), built on the tip of `08-bar-popouts`. A fork commit is fetched with `gh api` and applied with `git am --directory` (no `-3`: the fork's blobs are not in the clone), or hand-ported when its context does not exist here. `lib/mk-host.nix` applies every series with `applyPatches`; nothing in Nix changes.

**Tech Stack:** git (`am`, `format-patch`, `rerere`), gh, QML (Quickshell), bash, NixOS (`nixos-rebuild`).

**Spec:** `docs/superpowers/specs/2026-11-28-end4pc-backports-design.md`, section "`09-end4pc-fixes`" only. `10-icon-picker` and `11-lock` have their own plans.

## Global Constraints

- Work on `main` in `~/.dotfiles`; no branch, no worktree, no push anywhere.
- Patch work is commits on `krane` in `~/src/dots-hyprland`. Never `git am -3`. Never rebase an existing series.
- Commit messages in the clone follow the existing series: `type(scope): subject`, then a body of `Backport of pctrade/end4-pC <sha>`, the commit URL, `Problem:`, `Port:` and `Drop when:` lines, no blank lines inside the body, no Claude or Anthropic attribution.
- Commit message in `~/.dotfiles`: subject line only, no body.
- No comments in code you write (the apply rows keep whatever the fork commit contains).
- A patch must not change `property bool launchOnStartup: false` in `Config.qml` (sed rule in "Backported fork fixes", `docs/II-INTEGRATION.md`). None of these items touches it.
- A hand-port edits the file, then `git add` and `git commit` in the clone, so the series stays one commit per item.
- Run on tariognatha (NixOS, NVIDIA dGPU, two monitors): the overview and thumbnails need a real session.
- Do not `nixos-rebuild switch` before Task 9 step 1: the overview gate needs the unpatched running session.

---

### Task 0: Setup

**Files:** none changed in `~/.dotfiles` (read only).

- [ ] **Step 1: Update `~/.dotfiles` and check the series directories**

```sh
git -C ~/.dotfiles switch main && git -C ~/.dotfiles pull --ff-only
git -C ~/.dotfiles status --short
ls ~/.dotfiles/patches/ii
```

Expected: status prints nothing; the listing ends at `08-bar-popouts` (then `LICENSE`). If `09-end4pc-fixes` already exists, stop: this plan was already executed. If `10-*` or `11-*` exists, stop and ask: `09` must be built before them, so their commits would end up before it on `krane`.

- [ ] **Step 2: Authenticate gh and make sure the clone exists**

```sh
gh auth status
[ -d ~/src/dots-hyprland/.git ] || git clone https://github.com/end-4/dots-hyprland ~/src/dots-hyprland
```

Expected: `Logged in to github.com`. If not, run `gh auth login` first.

- [ ] **Step 3: Run the apply loop from `docs/II-INTEGRATION.md` ("Workflow")**

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

Expected: no "already in progress" message; if the "krane already exists" warning shows, confirm `git log --oneline "$PIN"..krane` holds nothing that is not in `patches/ii/` before continuing. The loop ends with `Applying: feat(bar): per-icon popouts for status icons` and tags `krane/01-fixes` to `krane/08-bar-popouts`. On a conflict: resolve, `git am --continue`, tag, resume from the next directory.

- [ ] **Step 4: Confirm the clone is clean and on the right tip**

```sh
cd ~/src/dots-hyprland
git status --short
git branch --show-current
git tag -l 'krane/*'
git rev-parse HEAD krane/08-bar-popouts
git log -1 --format='%an <%ae>' krane/08-bar-popouts
```

Expected: status empty; branch `krane`; seven tags `krane/01-fixes` to `krane/08-bar-popouts` (no `03`); the two hashes are equal.

- [ ] **Step 5: Use the existing patches' author for the new commits**

```sh
cd ~/src/dots-hyprland
git config user.name "$(git log -1 --format=%an krane/08-bar-popouts)"
git config user.email "$(git log -1 --format=%ae krane/08-bar-popouts)"
```

- [ ] **Step 6: Fetch the fork commits that are applied**

```sh
mkdir -p /tmp/e4pc
for s in 584cd9e ebeef46 061b321 5f1b4b4 18737b3 6de2c5f; do
  gh api repos/pctrade/end4-pC/commits/$s -H 'Accept: application/vnd.github.patch' > /tmp/e4pc/$s.patch
done
grep -c '^Subject' /tmp/e4pc/*.patch
```

Expected: `1` for each of the six files. (`e3bb865`, `a25766e`, `18b00f2` and `d6c8d5d` are hand-ported or reimplemented below; fetch them only for reference: `gh api repos/pctrade/end4-pC/commits/<sha> -H 'Accept: application/vnd.github.patch'`.)

---

### Task 1: 584cd9e, guard NotifTimer against a removed notification

**Files:** Modify `dots/.config/quickshell/ii/services/Notifications.qml`

**Interfaces:** none (internal `NotifTimer.onTriggered`).

- [ ] **Step 1: Apply the fork patch (offset of 1 line)**

```sh
git -C ~/src/dots-hyprland am --directory=dots/.config/quickshell/ii /tmp/e4pc/584cd9e.patch
git -C ~/src/dots-hyprland show --stat HEAD
```

Expected: `Applying: fix(notifications): don't dereference a notification that is already gone`; stat shows `services/Notifications.qml | 5 +++++` only, under `dots/.config/quickshell/ii/`.

- [ ] **Step 2: Fallback if `git am` fails**

Run `git -C ~/src/dots-hyprland am --abort`, then in `dots/.config/quickshell/ii/services/Notifications.qml` replace

```qml
            const index = root.list.findIndex((notif) => notif.notificationId === notificationId);
            const notifObject = root.list[index];
```

with

```qml
            const index = root.list.findIndex((notif) => notif.notificationId === notificationId);
            if (index === -1) {
                destroy();
                return;
            }
            const notifObject = root.list[index];
```

Then `git -C ~/src/dots-hyprland add dots/.config/quickshell/ii/services/Notifications.qml` and `git -C ~/src/dots-hyprland commit -m x` (the message is rewritten in step 3).

- [ ] **Step 3: Set the commit message**

```sh
git -C ~/src/dots-hyprland commit --amend --reset-author -m 'fix(notifications): destroy a notification timer whose notification is gone

Backport of pctrade/end4-pC 584cd9e
https://github.com/pctrade/end4-pC/commit/584cd9e
Problem: NotifTimer fires after its notification was dismissed or discarded; findIndex returns -1 and notifObject.isTransient throws a TypeError, which also skips destroy().
Port: clean (offset)
Drop when: the pinned NotifTimer.onTriggered returns when its notification is no longer in the list.'
```

- [ ] **Step 4: Verify**

```sh
git -C ~/src/dots-hyprland log -1 --format='%an%n%s' && git -C ~/src/dots-hyprland status --short
```

Expected: the author of the earlier patches, the new subject, empty status.

---

### Task 2: ebeef46, discrete GPU in the lspci fallback

**Files:** Modify `dots/.config/quickshell/ii/services/SystemInfo.qml`

- [ ] **Step 1: Apply the fork patch (offset of about -9 lines)**

```sh
git -C ~/src/dots-hyprland am --directory=dots/.config/quickshell/ii /tmp/e4pc/ebeef46.patch
git -C ~/src/dots-hyprland show --stat HEAD
```

Expected: `Applying: fix(system-info): prefer the discrete GPU over the iGPU`; stat shows `services/SystemInfo.qml | 8 ++++++--`.

- [ ] **Step 2: Fallback if `git am` fails**

Run `git -C ~/src/dots-hyprland am --abort`, then in `services/SystemInfo.qml` (`getGpu` process) replace

```qml
                gpu=$(lspci | grep -iE 'vga|3d|display' | head -1 | sed -E '
                    s/.*: //;
                    s/\\(rev [0-9a-f]+\\)//;
```

with

```qml
                gpus=$(lspci | grep -iE 'vga|3d|display')
                line=$(echo "$gpus" | grep -vi 'Intel Corporation' | head -1)
                [ -z "$line" ] && line=$(echo "$gpus" | head -1)
                gpu=$(echo "$line" | sed -E '
                    s/.*: //;
                    s/ *\\(rev [0-9a-f]+\\)//;
```

Then `git add` the file and `git commit -m x`.

- [ ] **Step 3: Set the commit message**

```sh
git -C ~/src/dots-hyprland commit --amend --reset-author -m 'fix(system-info): prefer the discrete GPU in the lspci fallback

Backport of pctrade/end4-pC ebeef46
https://github.com/pctrade/end4-pC/commit/ebeef46
Problem: the lspci fallback took the first display controller, usually the iGPU, and the space left before "(rev xx)" stopped the bracket extraction from matching.
Port: clean (offset)
Drop when: the pinned getGpu picks a non-Intel controller first and strips the space before "(rev xx)".'
```

- [ ] **Step 4: Verify**

```sh
git -C ~/src/dots-hyprland status --short; git -C ~/src/dots-hyprland log -1 --format=%s
```

Expected: empty status, the new subject.

---

### Task 3: 061b321, case-insensitive model lookup

**Files:** Modify `dots/.config/quickshell/ii/services/Ai.qml`

- [ ] **Step 1: Apply the fork patch (offset of about -71 lines)**

```sh
git -C ~/src/dots-hyprland am --directory=dots/.config/quickshell/ii /tmp/e4pc/061b321.patch
git -C ~/src/dots-hyprland show --stat HEAD
```

Expected: `Applying: Fixed selection of local ollama models`; stat shows `services/Ai.qml | 6 ++++--`.

- [ ] **Step 2: Fallback if `git am` fails**

Run `git -C ~/src/dots-hyprland am --abort`, then in `services/Ai.qml` (`setModel`) replace

```qml
        modelId = modelId.toLowerCase()
        if (modelList.indexOf(modelId) !== -1) {
```

with

```qml
        const matchedModelId = modelList.find(id => id.toLowerCase() === modelId.toLowerCase())
        if (matchedModelId !== undefined) {
            modelId = matchedModelId
```

Then `git add` the file and `git commit -m x`.

- [ ] **Step 3: Set the commit message**

```sh
git -C ~/src/dots-hyprland commit --amend --reset-author -m 'fix(ai): find a model id case-insensitively and keep the real id

Backport of pctrade/end4-pC 061b321
https://github.com/pctrade/end4-pC/commit/061b321
Problem: setModel lowercased the requested id, so a model whose id has uppercase letters (local ollama models) was never found.
Port: clean (offset)
Drop when: the pinned setModel matches ids case-insensitively without rewriting the stored id.'
```

- [ ] **Step 4: Verify**

```sh
git -C ~/src/dots-hyprland status --short; git -C ~/src/dots-hyprland log -1 --format=%s
```

Expected: empty status, the new subject.

---

### Task 4: 5f1b4b4, one video frame for wallpaper categorisation

**Files:** Modify `dots/.config/quickshell/ii/scripts/ai/gemini-categorize-wallpaper.sh`

- [ ] **Step 1: Apply the fork patch (no offset)**

```sh
git -C ~/src/dots-hyprland am --directory=dots/.config/quickshell/ii /tmp/e4pc/5f1b4b4.patch
git -C ~/src/dots-hyprland show --stat HEAD
```

Expected: `Applying: fix(ai): only decode the first frame of video wallpapers`; stat shows the script with 9 insertions and 1 deletion.

- [ ] **Step 2: Fallback if `git am` fails**

Run `git -C ~/src/dots-hyprland am --abort`, then in the script replace

```sh
magick "$SOURCE_IMG_PATH" -resize 200x -quality 50 "$RESIZED_IMG_PATH"
```

with

```sh
case "${SOURCE_IMG_PATH,,}" in
    *.mp4|*.webm|*.mkv|*.avi|*.mov)
        ffmpeg -y -loglevel error -i "$SOURCE_IMG_PATH" -frames:v 1 -vf scale=200:-2 -q:v 10 "$RESIZED_IMG_PATH"
        ;;
    *)
        magick "$SOURCE_IMG_PATH[0]" -resize 200x -quality 50 "$RESIZED_IMG_PATH"
        ;;
esac
```

Then `git add` the file (mode stays 100755) and `git commit -m x`.

- [ ] **Step 3: Set the commit message**

```sh
git -C ~/src/dots-hyprland commit --amend --reset-author -m 'fix(ai): decode one frame of a video wallpaper

Backport of pctrade/end4-pC 5f1b4b4
https://github.com/pctrade/end4-pC/commit/5f1b4b4
Problem: magick on a video decodes every frame (12.9 GB of RAM, over 10 minutes), once per wallpaper switch while aiStyling is on; an animated GIF produced wallpaper-0.jpg, -1.jpg, ...
Port: clean
Drop when: the pinned gemini-categorize-wallpaper.sh grabs a single frame of a video and uses [0] for images.'
```

- [ ] **Step 4: Verify**

```sh
git -C ~/src/dots-hyprland status --short; git -C ~/src/dots-hyprland ls-files -s -- dots/.config/quickshell/ii/scripts/ai/gemini-categorize-wallpaper.sh
```

Expected: empty status; mode `100755`.

---

### Task 5: e3bb865 (icon hunk only), `schedule` notification icon

**Files:** Modify `dots/.config/quickshell/ii/modules/common/functions/NotificationUtils.qml`

The fork commit `e3bb865` ("sf") mixes many unrelated changes; the spec ports only this hunk (the resource-polling hunks are explicitly not ported). Hand-port.

- [ ] **Step 1: Edit the line**

In `modules/common/functions/NotificationUtils.qml` replace

```qml
            'time': 'scheduleb',
```

with

```qml
            'time': 'schedule',
```

- [ ] **Step 2: Commit**

```sh
cd ~/src/dots-hyprland
git diff --stat
git add dots/.config/quickshell/ii/modules/common/functions/NotificationUtils.qml
git commit -m 'fix(notifications): use the schedule icon for time notifications

Backport of pctrade/end4-pC e3bb865 (icon hunk only)
https://github.com/pctrade/end4-pC/commit/e3bb865
Problem: the time notification icon was the nonexistent Material symbol "scheduleb".
Port: hand-port, one line; the other hunks of the fork commit are not ported
Drop when: the pinned NotificationUtils maps "time" to "schedule".'
git show --stat HEAD
```

Expected: one file, 1 insertion and 1 deletion.

---

### Task 6: 18737b3, player de-duplication and MPRIS fallback

**Files:** Modify `modules/ii/mediaControls/MediaControls.qml`, `services/MprisController.qml` (excluded: `modules/ii/sidebarRight/SidebarRightContent.qml`, its pattern is absent here).

- [ ] **Step 1: Apply with the exclude (the exclude path needs the full prefix, `--directory` is applied first)**

```sh
git -C ~/src/dots-hyprland am --directory=dots/.config/quickshell/ii --exclude=dots/.config/quickshell/ii/modules/ii/sidebarRight/SidebarRightContent.qml /tmp/e4pc/18737b3.patch
git -C ~/src/dots-hyprland show --stat HEAD
```

Expected: `Skipped patch '...SidebarRightContent.qml'`; stat lists `MediaControls.qml` and `MprisController.qml`, 2 insertions and 2 deletions, nothing else.

- [ ] **Step 2: Fallback if `git am` fails**

Run `git -C ~/src/dots-hyprland am --abort` if an am is in progress. In `modules/ii/mediaControls/MediaControls.qml` replace

```qml
(p1.position - p2.position <= 2 && p1.length - p2.length <= 2)
```

with

```qml
(Math.abs(p1.position - p2.position) <= 2 && Math.abs(p1.length - p2.length) <= 2)
```

In `services/MprisController.qml` replace (tab-indented in the file)

```qml
						if (player.playbackState.isPlaying) {
```

with

```qml
						if (player.isPlaying) {
```

Then `git add` both files and `git commit -m x`.

- [ ] **Step 3: Set the commit message**

```sh
git -C ~/src/dots-hyprland commit --amend --reset-author -m 'fix(media): compare player position and length by absolute difference

Backport of pctrade/end4-pC 18737b3
https://github.com/pctrade/end4-pC/commit/18737b3
Problem: filterDuplicatePlayers tested p1 - p2 <= 2, true whenever p1 is behind p2, so unrelated players were grouped by order; MprisController read player.playbackState.isPlaying, which the enum does not have, so its fallback never picked a player.
Port: SidebarRightContent.qml not ported (pattern absent here)
Drop when: the pinned filterDuplicatePlayers uses Math.abs and MprisController uses player.isPlaying.'
git -C ~/src/dots-hyprland status --short
```

Expected: empty status.

---

### Task 7: a25766e, create the thumbnail cache directory

**Files:** Modify `dots/.config/quickshell/ii/modules/common/widgets/ThumbnailImage.qml`

The fork hunk's context does not exist here (`05-settings/0022` rewrote the one-liner), so hand-port. Do not run `git am`.

- [ ] **Step 1: Edit the script line**

In the `thumbnailGeneration` process replace the line

```qml
                `[ -f "$2" ] && exit 0 || { tmp="$2.$$.tmp.png"; magick "$1" -resize ${maxSize}x${maxSize} "$tmp" && mv "$tmp" "$2" && exit 1; exit 2; }`,
```

with

```qml
                `[ -f "$2" ] && exit 0 || { mkdir -p "$(dirname "$2")" && tmp="$2.$$.tmp.png" && magick "$1" -resize ${maxSize}x${maxSize} "$tmp" && mv "$tmp" "$2" && exit 1; exit 2; }`,
```

Here `$1` is the source and `$2` the destination. The backticks and trailing comma belong to the line.

- [ ] **Step 2: Check the generation script against a fresh directory**

```sh
d=$(mktemp -d)
src=$(ls ~/Pictures/Wallpapers/* 2>/dev/null | head -1)
bash -c '[ -f "$2" ] && exit 0 || { mkdir -p "$(dirname "$2")" && tmp="$2.$$.tmp.png" && magick "$1" -resize 64x64 "$tmp" && mv "$tmp" "$2" && exit 1; exit 2; }' _ "$src" "$d/new/sub/t.png"; echo "exit=$?"; ls "$d/new/sub"
rm -rf "$d"
```

Expected: `exit=1` and `t.png` listed. This needs `$src` to be an image; if `~/Pictures/Wallpapers` is empty, set `src` to any image file.

- [ ] **Step 3: Commit**

```sh
cd ~/src/dots-hyprland
git add dots/.config/quickshell/ii/modules/common/widgets/ThumbnailImage.qml
git commit -m 'fix(thumbnails): create the thumbnail cache directory before generating into it

Backport of pctrade/end4-pC a25766e
https://github.com/pctrade/end4-pC/commit/a25766e
Problem: nothing creates genericCache/thumbnails/<size>, so magick cannot open its temp file, the script exits 2 and the thumbnail never renders.
Port: hand-port onto the 05-settings/0022 one-liner ($1 source, $2 destination); the chain is && throughout
Drop when: the pinned ThumbnailImage.qml creates the thumbnail directory before writing into it.'
git show --stat HEAD
```

Expected: one file, 1 insertion and 1 deletion.

---

### Task 8: 6de2c5f, `image/png` for the screenshot clipboard

**Files:** Modify `modules/common/utils/ScreenshotAction.qml`, `modules/ii/overlay/recorder/Recorder.qml` (excluded: `modules/ii/regionSelector/RegionSelector.qml`, its grim line is absent here).

- [ ] **Step 1: Apply with the exclude**

```sh
git -C ~/src/dots-hyprland am --directory=dots/.config/quickshell/ii --exclude=dots/.config/quickshell/ii/modules/ii/regionSelector/RegionSelector.qml /tmp/e4pc/6de2c5f.patch
git -C ~/src/dots-hyprland show --stat HEAD
```

Expected: `Skipped patch '...RegionSelector.qml'`; stat lists `ScreenshotAction.qml` (3 changed lines) and `Recorder.qml` (1 changed line).

- [ ] **Step 2: Fallback if `git am` fails**

Run `git -C ~/src/dots-hyprland am --abort` if an am is in progress. In `modules/common/utils/ScreenshotAction.qml` make three replacements.

```qml
        const cropToStdout = `${cropBase} -`
```

becomes

```qml
        const cropToStdout = `${cropBase} PNG:-`
```

```qml
                    return ["bash", "-c", `${cropToStdout} | wl-copy && ${cleanup}`]
```

becomes

```qml
                    return ["bash", "-c", `${cropToStdout} | wl-copy --type image/png && ${cleanup}`]
```

```qml
                    ${cropToStdout} | tee >(wl-copy) > "$savePath" && \
```

becomes

```qml
                    ${cropToStdout} | tee >(wl-copy --type image/png) > "$savePath" && \
```

In `modules/ii/overlay/recorder/Recorder.qml` replace `"grim - | wl-copy"` with `"grim - | wl-copy --type image/png"`. Then `git add` both files and `git commit -m x`.

- [ ] **Step 3: Set the commit message**

```sh
git -C ~/src/dots-hyprland commit --amend --reset-author -m 'fix(screenshot): copy screenshots to the clipboard as image/png

Backport of pctrade/end4-pC 6de2c5f
https://github.com/pctrade/end4-pC/commit/6de2c5f
Problem: magick wrote the crop to stdout without a format and wl-copy got no MIME type, so clipboard-aware apps did not recognise the image and pasting failed on Wayland.
Port: RegionSelector.qml not ported (its grim line is absent here)
Drop when: the pinned ScreenshotAction.qml and Recorder.qml force PNG:- and wl-copy --type image/png.'
git -C ~/src/dots-hyprland status --short
```

Expected: empty status.

---

### Task 9: 18b00f2 (drag half), keep the overview open during a window drag

**Files:** Modify `dots/.config/quickshell/ii/modules/ii/overview/Overview.qml`

The proxy-mask half of the fork commit is not ported: our `columnLayout` has no open-animation scale, and there is no clipboard-popover `Region`.

- [ ] **Step 1: Gate, on the unpatched running session (before any `nixos-rebuild switch`)**

Open the overview (`SUPER`), drag a window preview to another workspace and release, then drag one and release it on empty space around the grid. Note whether the overview closes during or at the end of a drag.

Outcomes: (a) it stays open throughout: the bug is not reproduced. **Skip steps 2 to 4 of this task, commit nothing, and drop 18b00f2 from the later text** (the overview clause in the `09` paragraph of Task 12 step 3, the Overview bullet of Task 12 step 4, Task 13 step 12, and one commit in Task 11's counts). (b) It closes: continue.

- [ ] **Step 2: Declare the dragging flag and use it in the mask**

In `modules/ii/overview/Overview.qml` replace

```qml
        color: "transparent"

        mask: Region {
            item: GlobalStates.overviewOpen ? columnLayout : null
        }
```

with

```qml
        color: "transparent"

        readonly property bool windowDragging: (overviewLoader.item?.draggingFromWorkspace ?? -1) !== -1
        mask: Region {
            item: GlobalStates.overviewOpen ? (panelWindow.windowDragging ? fullscreenMask : columnLayout) : null
        }
```

- [ ] **Step 3: Add the fullscreen mask item**

Replace

```qml
        function setSearchingText(text) {
            searchWidget.setSearchingText(text);
            searchWidget.focusFirstItem();
        }

        Column {
            id: columnLayout
```

with

```qml
        function setSearchingText(text) {
            searchWidget.setSearchingText(text);
            searchWidget.focusFirstItem();
        }

        Item {
            id: fullscreenMask
            anchors.fill: parent
        }

        Column {
            id: columnLayout
```

`draggingFromWorkspace` is the `OverviewWidget.qml` property (`-1` when idle) set while a window preview is dragged; `overviewLoader` is declared later in the same file.

- [ ] **Step 4: Commit**

```sh
cd ~/src/dots-hyprland
git diff --stat
git add dots/.config/quickshell/ii/modules/ii/overview/Overview.qml
git commit -m 'fix(overview): keep the overview open while a window preview is dragged

Backport of pctrade/end4-pC 18b00f2 (drag half)
https://github.com/pctrade/end4-pC/commit/18b00f2
Problem: dragging a window preview moves the pointer outside the input mask, Hyprland ends the focus grab and the overview closes.
Port: hand-port; mask the whole screen while draggingFromWorkspace is set; the proxy-mask half is not ported (columnLayout is not scaled here)
Drop when: the pinned Overview.qml masks the whole screen during a window drag.'
git show --stat HEAD
```

Expected: one file, 7 insertions and 1 deletion.

---

### Task 10: d6c8d5d, data-URI and raw-path album art

**Files:** Modify `dots/.config/quickshell/ii/modules/ii/mediaControls/PlayerControl.qml`

The fork commit does not touch this file (it patches `Player.qml` and others that do not exist here), so this is a reimplementation. `bar/Media.qml` and `lock/LockSurface.qml` have no art code to change. The optional null guards in `MprisController.qml` are not needed: its `artUrl` already uses `?? ""`.

- [ ] **Step 1: Make `artUrl` never undefined**

Replace

```qml
    property var artUrl: player?.trackArtUrl
```

with

```qml
    property var artUrl: player?.trackArtUrl ?? ""
```

- [ ] **Step 2: Use local art directly**

Replace

```qml
    property string displayedArtFilePath: root.downloaded ? Qt.resolvedUrl(artFilePath) : ""
```

with

```qml
    readonly property bool artIsRemote: /^https?:\/\//.test(artUrl)
    property string displayedArtFilePath: {
        if (artUrl.length === 0) return ""
        if (artUrl.startsWith("data:") || artUrl.startsWith("file:/")) return artUrl
        if (artUrl.startsWith("/")) return "file://" + artUrl
        return root.downloaded ? Qt.resolvedUrl(artFilePath) : ""
    }
```

- [ ] **Step 3: Download only http(s) art, passing arguments instead of splicing text**

Replace

```qml
    onArtFilePathChanged: {
        if (root.artUrl.length == 0) {
            root.artDominantColor = Appearance.m3colors.m3secondaryContainer
            return;
        }

        // Binding does not work in Process
        coverArtDownloader.targetFile = root.artUrl 
        coverArtDownloader.artFilePath = root.artFilePath
        // Download
        root.downloaded = false
        coverArtDownloader.running = true
    }
```

with

```qml
    onArtFilePathChanged: {
        root.downloaded = false
        if (root.artUrl.length == 0) {
            root.artDominantColor = Appearance.m3colors.m3secondaryContainer
            return;
        }
        if (!root.artIsRemote) return;

        coverArtDownloader.targetFile = root.artUrl
        coverArtDownloader.artFilePath = root.artFilePath
        coverArtDownloader.running = true
    }
```

(the old line `coverArtDownloader.targetFile = root.artUrl ` has a trailing space), and replace

```qml
        command: [ "bash", "-c", `[ -f ${artFilePath} ] || curl -4 -sSL '${targetFile}' -o '${artFilePath}'` ]
```

with

```qml
        command: [ "bash", "-c", `[ -f "$2" ] || curl -4 -sSL "$1" -o "$2"`, "_", targetFile, artFilePath ]
```

`onExited` and the rest of the process stay as they are. The three `source: root.displayedArtFilePath` users (`ColorQuantizer`, `blurredArt`, `mediaArt`) need no change.

- [ ] **Step 4: Commit**

```sh
cd ~/src/dots-hyprland
git diff --stat
git add dots/.config/quickshell/ii/modules/ii/mediaControls/PlayerControl.qml
git commit -m 'fix(media): show base64 data URI and raw path album art

Reimplementation of pctrade/end4-pC d6c8d5d for mediaControls/PlayerControl.qml
https://github.com/pctrade/end4-pC/commit/d6c8d5d
Problem: PlayerControl curled every album art URL, so a data: URI or a bare file path (Telegram and others) never rendered; the URL was also spliced into a shell string.
Port: reimplemented, the fork commit patches Player.qml and other files that do not exist here; data: and file: art is used directly, a path gets file://, only http(s) is downloaded, and the URL and target path go to curl as arguments
Drop when: the pinned PlayerControl.qml accepts data: and file: art and downloads only http(s).'
git status --short
```

Expected: one file changed, empty status afterwards.

---

### Task 11: Tag, export, stage

**Files:** Create `patches/ii/09-end4pc-fixes/*.patch`

- [ ] **Step 1: Check the commit list**

```sh
cd ~/src/dots-hyprland
git status --short
git log --oneline krane/08-bar-popouts..krane
```

Expected: status empty; ten commits (nine if Task 9 was skipped), in order: notification timer, system-info, ai, wallpaper, schedule icon, media dedupe, thumbnails mkdir, screenshot, overview (if kept), album art.

- [ ] **Step 2: Tag the last commit and create the series directory**

```sh
cd ~/src/dots-hyprland
git tag -f krane/09-end4pc-fixes krane
mkdir -p ~/.dotfiles/patches/ii/09-end4pc-fixes
```

- [ ] **Step 3: Run the export loop from `docs/II-INTEGRATION.md`**

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

Expected: no "missing" message.

- [ ] **Step 4: Stage and check that only the new series changed**

```sh
git -C ~/.dotfiles add patches/ii
git -C ~/.dotfiles status --short
ls ~/.dotfiles/patches/ii/09-end4pc-fixes
```

Expected: only `A  patches/ii/09-end4pc-fixes/00NN-*.patch` lines (ten, or nine), none for `01-fixes` to `08-bar-popouts`. If an older series shows as modified, the re-export differs from the repo: stop and ask, do not commit it.

---

### Task 12: Docs

**Files:** Modify `docs/II-INTEGRATION.md`, `docs/VERIFY.md`

- [ ] **Step 1: Series list in "Backported fork fixes" (`docs/II-INTEGRATION.md`)**

Replace

```md
`01-fixes`, `02-translator`, `04-agents`, `05-settings`, `06-notifications`
and `07-idle`. `lib/mk-host.nix` applies them with `applyPatches`, after
```

with

```md
`01-fixes`, `02-translator`, `04-agents`, `05-settings`, `06-notifications`,
`07-idle`, `08-bar-popouts` and `09-end4pc-fixes`. `lib/mk-host.nix` applies them with `applyPatches`, after
```

If another plan already extended this list (for example with `10-icon-picker`), keep its entries and add `09-end4pc-fixes` in numeric order.

- [ ] **Step 2: The `01-fixes` range sentence**

Replace

```md
(`0001` to `0008`) plus local fixes (`0009` to `0011`): thumbnails,
```

with

```md
(`0001` to `0008`; later ones are in `09-end4pc-fixes`) plus local fixes (`0009` to `0011`): thumbnails,
```

- [ ] **Step 3: Add the `09-end4pc-fixes` paragraph after the `08-bar-popouts` section (before "### Workflow")**

```md
### `09-end4pc-fixes`

Later [pctrade/end4-pC](https://github.com/pctrade/end4-pC) fixes on top of
`08`, one commit each, the fork commit named in its message: `NotifTimer`
ignores a removed notification, the `lspci` GPU fallback prefers the discrete
card, `setModel` matches ids case-insensitively, the Gemini wallpaper script
decodes one video frame, the time notification icon is `schedule`, player
de-duplication compares absolute differences, the thumbnail script creates its
cache directory, screenshots reach the clipboard as `image/png`, the overview
stays open while a window preview is dragged, and `PlayerControl.qml` shows
data-URI and raw-path album art (a reimplementation: the fork commit patches
files that do not exist here). The fork's `SidebarRightContent.qml` and
`RegionSelector.qml` hunks are not ported.
```

If Task 9 was skipped, delete "the overview stays open while a window preview is dragged, " from the paragraph.

- [ ] **Step 4: Manual checks (`docs/VERIFY.md`): append after the last bullet of "### Bar icon popouts"**

```md

### End4-pC fixes

- Dismiss a notification before its 7 s timeout; `qs log -c ii` has no new `TypeError`.
- The About page shows the discrete GPU (tariognatha). The `lspci` fallback only runs when the `glxinfo` Intel match is empty; otherwise read `getGpu` in `services/SystemInfo.qml`.
- `sed '/^esac/q' ~/.config/quickshell/ii/scripts/ai/gemini-categorize-wallpaper.sh | bash -s -- <video>` ends in seconds and leaves a 200 px `/tmp/quickshell/ai/wallpaper.jpg` (no network call).
- `rm -rf ~/.cache/thumbnails/<size>`, then open the wallpaper selector: thumbnails appear.
- After a screenshot copy, `wl-paste --list-types` lists `image/png`.
- Dragging a window preview in the overview does not close it.
- Play something with data-URI or raw-path art (for example Telegram): the art shows. Plain http art still shows.
```

If Task 9 was skipped, drop the overview bullet.

- [ ] **Step 5: Check the docs**

```sh
git -C ~/.dotfiles diff -- docs
```

Expected: only the edits above.

---

### Task 13: Build and runtime verification

- [ ] **Step 1: Stage and build (`applyPatches` fails on any stale patch)**

```sh
git -C ~/.dotfiles add patches/ii docs
nixos-rebuild build --flake ~/.dotfiles#tariognatha
```

Expected: exit 0 and a `result` symlink in the current directory. A failure names the patch file: fix that commit in the clone, move the tag, re-export (Task 11 steps 2 to 4) and rebuild. Delete the `result` symlink afterwards.

- [ ] **Step 2: Switch and restart ii (the build does not load QML)**

```sh
sudo nixos-rebuild switch --flake ~/.dotfiles#tariognatha
```

Then restart ii with the restart-widgets keybind, or log out and in. Expected: no activation error.

- [ ] **Step 3: QML errors**

```sh
qs log -c ii | grep -iE 'TypeError|ReferenceError|Cannot assign|is not a type|unavailable' | head
```

Expected: no lines naming `Notifications.qml`, `Overview.qml`, `PlayerControl.qml`, `ThumbnailImage.qml`, `MediaControls.qml`, `Ai.qml` or `SystemInfo.qml`.

- [ ] **Step 4: Notifications (584cd9e)**

```sh
notify-send -t 3000 end4pc-test
```

Dismiss it at once (close button), wait 10 s, then repeat the Step 3 grep. Expected: no `TypeError`.

- [ ] **Step 5: GPU (ebeef46)**

```sh
glxinfo 2>/dev/null | grep 'renderer string' | grep -o 'Intel(R) HD Graphics [0-9]\{4\}'
lspci | grep -iE 'vga|3d|display'
```

If the first prints nothing, the `lspci` fallback runs: the Settings About page shows the NVIDIA card, not an Intel iGPU. If it prints a match, the fallback never runs on this host: the check is reading `getGpu` in `~/.config/quickshell/ii/services/SystemInfo.qml` (it has `grep -vi 'Intel Corporation'`).

- [ ] **Step 6: Model ids (061b321)**

In the left sidebar AI tab run `/model` with a known id in another case (for example `GEMINI-2.5-FLASH` against `gemini-2.5-flash`). Expected: `Model set to ...`, no invalid-model message. If a local ollama model with an uppercase id exists, selecting it works. Otherwise the uppercase case is verified by code read only.

- [ ] **Step 7: Video wallpaper (5f1b4b4)**

```sh
v=$(ls ~/Videos/*.mp4 ~/Pictures/Wallpapers/*.mp4 2>/dev/null | head -1); echo "$v"
sed '/^esac/q' ~/.config/quickshell/ii/scripts/ai/gemini-categorize-wallpaper.sh | bash -s -- "$v"
identify /tmp/quickshell/ai/wallpaper.jpg
```

Watch memory while it runs (`btop`, or `ps -o rss= -C magick`). Expected: finishes in seconds, no `magick` process, `identify` prints `JPEG 200x...`. The `sed` form stops before the Gemini call, so nothing is uploaded; the full script with a Gemini key set uploads the 200 px frame.

- [ ] **Step 8: Thumbnails (a25766e)**

```sh
ls ~/.cache/thumbnails
```

Remove the size directories listed there (`rm -rf ~/.cache/thumbnails/<size>`), then open the wallpaper selector. Expected: thumbnails appear and `ls ~/.cache/thumbnails` lists the directory again.

- [ ] **Step 9: Notification icon (e3bb865)**

```sh
grep -n "'time'" ~/.config/quickshell/ii/modules/common/functions/NotificationUtils.qml
```

Expected: `'time': 'schedule',`.

- [ ] **Step 10: Media (18737b3, d6c8d5d)**

Play something in two players if possible: the media controls overlay shows one card per distinct player and no `TypeError`. Play something with data-URI or raw-path art (for example Telegram): the art shows in the card and its blurred background. Play a plain http-art player (a browser video): art still shows. Expected: all three. The `MprisController` fallback (`player.isPlaying`) only runs when a player is destroyed: code read only.

- [ ] **Step 11: Screenshot (6de2c5f)**

Take a region screenshot to the clipboard (the region selector's copy action), then:

```sh
wl-paste --list-types
```

Expected: `image/png` listed; pasting into an image-aware app works. Repeat with the overlay recorder's Screenshot button.

- [ ] **Step 12: Overview (18b00f2); skip if Task 9 was skipped**

Open the overview, drag a window preview to another workspace and release. Expected: the overview stays open through the drag and the window moved.

- [ ] **Step 13: Report**

Record which checks ran, which were verified by code read only (GPU if `glxinfo` matched, uppercase model id, `MprisController` fallback), and any failure. Fix a failure in the clone, move `krane/09-end4pc-fixes`, re-export (Task 11 steps 3 and 4) and rebuild before continuing.

---

### Task 14: Commit

- [ ] **Step 1: Check what is staged**

```sh
git -C ~/.dotfiles status --short
```

Expected: `patches/ii/09-end4pc-fixes/*`, `docs/II-INTEGRATION.md`, `docs/VERIFY.md`, plus this plan and its spec if untracked (leave those out; Task 15 removes them).

- [ ] **Step 2: Commit on main, subject only**

```sh
git -C ~/.dotfiles add patches/ii docs/II-INTEGRATION.md docs/VERIFY.md
git -C ~/.dotfiles commit -m 'Add end4-pC fixes patch series'
git -C ~/.dotfiles status --short
```

Expected: empty status apart from the plan and spec files. No push.

---

### Task 15: Remove the spec and plan

Run only after Task 13's verification, the final review pass and the user's approval. The spec also covers `10-icon-picker`: delete it only if that series is done or the user says so; otherwise delete just this plan.

- [ ] **Step 1: Delete and commit**

```sh
git -C ~/.dotfiles rm -f docs/superpowers/plans/2026-11-28-end4pc-fixes.md docs/superpowers/specs/2026-11-28-end4pc-backports-design.md
git -C ~/.dotfiles commit -m 'Remove end4-pC backports spec and plan'
```

Expected: the commit lists both deletions. No push.
