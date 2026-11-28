# Lock Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Follow ponytail: smallest change, no code comments.

**Goal:** Fix the lock screen cursor jump (pctrade/end4-pC#72), show the prompt, clock and weather on one monitor only, and add a `lock.mainMonitor` setting, as new series `patches/ii/11-lock`.

**Architecture:** Five commits on branch `krane` of `~/src/dots-hyprland` (paths below are under `dots/.config/quickshell/ii/`), exported to `patches/ii/11-lock/` with the workflow in `docs/II-INTEGRATION.md`. `Lock.qml` records the focused monitor and pointer, pushes each monitor to the nearest empty workspace, and publishes the prompt screen name in `GlobalStates.lockPromptScreen`. `LockScreen.qml` (shared with the waffle lock) fades its loaded lock surface out on other screens; `Background.qml` hides the widget canvas there.

**Tech Stack:** QML (Quickshell 0.3.x), Hyprland 0.56 Lua dispatchers (`hl.dsp.focus`, `hl.dsp.cursor.move`), hyprctl JSON, git patch series, Nix (nixos-rebuild).

**Spec:** `docs/superpowers/specs/2026-11-28-lock-fixes-design.md`

## Global Constraints

- Execution host: tariognatha (NixOS, NVIDIA dGPU, 2 monitors: DP-2 3840x2160 scale 1.5, DP-1 2560x1440). Work in a fresh session with no other context.
- QML has no unit tests here. Each code task is verified by running ii from the clone (`qs -p "$II" -d`), triggering the lock, observing, and reading the qs log for errors. Steps that unlock need the human at the keyboard (the password is typed by the user): ask the user to type it. Never test with the live lock unattended.
- Lock recovery if a test build leaves the session locked with no working prompt: switch to a TTY (Ctrl+Alt+F3), log in, then `export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-1 HYPRLAND_INSTANCE_SIGNATURE=$(ls -t $XDG_RUNTIME_DIR/hypr | head -1); pkill -f '[q]s-wrapped'; qs -c ii -d; qs -c ii ipc call lock activate` (`allow_session_lock_restore = true` is set by ii) and unlock from the new prompt.
- Patch commits in the clone have a subject and a body (problem, port, "Drop when ..."), no Claude/Anthropic attribution, no `Co-Authored-By`. The commit in `~/.dotfiles` is a subject line only.
- Create and change files only with Write/Edit (or REPL `write()`/`edit()`), never heredocs, `sed -i` or redirects. Clone edits are made with an exact old and new text.
- Do not touch the `property bool launchOnStartup: false` line in `modules/common/Config.qml` (a `kraneIiPatches` sed rewrites it). Do not change the waffle lock. Do not push anywhere.
- No code comments in the QML added here.
- Test-only changes (temporary log lines, `lock.mainMonitor` in config.json) are removed before each commit; `git diff` is checked before every commit.

---

## Task 0: Setup

**Files:** none changed. Uses `~/.dotfiles`, `~/src/dots-hyprland`.

**Interfaces:** shell variable `II` (the ii source root in the clone) and helpers used by every later task.

- [ ] **Step 1: Check tooling and the repo**

```sh
gh auth status
git -C ~/.dotfiles branch --show-current
git -C ~/.dotfiles status --short
hyprctl monitors -j | jq -r '.[].name'
```

Expected: gh logged in; `main`; no status lines; two names (`DP-1`, `DP-2`). Anything else: stop and ask the user.

- [ ] **Step 2: Pull the dotfiles**

```sh
git -C ~/.dotfiles pull --ff-only
ls ~/.dotfiles/patches/ii ~/.dotfiles/docs/superpowers/specs
```

Expected: fast-forward or "Already up to date"; `patches/ii` lists `01-fixes` through `08-bar-popouts` (and `09-*`/`10-*` if they have landed); the spec `2026-11-28-lock-fixes-design.md` exists.

- [ ] **Step 3: Ensure the clone exists**

```sh
[ -d ~/src/dots-hyprland/.git ] || git clone https://github.com/end-4/dots-hyprland ~/src/dots-hyprland
```

- [ ] **Step 4: Run the apply loop from docs/II-INTEGRATION.md "Workflow"**

If `krane` already exists in the clone, first run `git -C ~/src/dots-hyprland log --oneline krane -3` and confirm with the user that nothing on it is unexported; the switch below discards it.

```sh
PIN=$(jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock)
cd ~/src/dots-hyprland
git config rerere.enabled true
git fetch origin
if [ -d .git/rebase-apply ]; then
  echo "an am/rebase is already in progress; resolve it (git am --continue/--skip/--abort) first" >&2
  exit 1
fi
git switch -C krane "$PIN"
for d in ~/.dotfiles/patches/ii/*/; do
  git am -3 "$d"*.patch || break
  git tag -f "krane/$(basename "$d")"
done
```

Expected: every series applies without a conflict. On a conflict: resolve, `git am --continue`, tag, and resume from the next directory.

- [ ] **Step 5: Confirm a clean tree and matching tags**

```sh
git -C ~/src/dots-hyprland status --short
git -C ~/src/dots-hyprland branch --show-current
git -C ~/src/dots-hyprland tag | grep '^krane/'
git -C ~/src/dots-hyprland config user.name
git -C ~/src/dots-hyprland config user.email
```

Expected: no status lines; `krane`; one `krane/NN-*` tag per directory in `patches/ii`; a user name and email (existing patches are authored `krane <chris@krane.dev>`; set both with `git config` in the clone if empty).

- [ ] **Step 6: Run ii from the clone and record the baseline log**

```sh
export II=~/src/dots-hyprland/dots/.config/quickshell/ii
pkill -f '[q]s-wrapped'; sleep 1; qs -p "$II" -d; sleep 5
qs log -p "$II" | rg -i 'error|TypeError|ReferenceError|Unable to assign|is not a' | head -20
```

Expected: ii's bar and background appear. Record these baseline log lines; later tasks compare against them (a "no new errors" check means no line beyond this baseline). Every later task restarts ii the same way; the restart command is:

```sh
export II=~/src/dots-hyprland/dots/.config/quickshell/ii; pkill -f '[q]s-wrapped'; sleep 1; qs -p "$II" -d; sleep 5
```

---

## Task 1: Restore focus and pointer after lock and unlock

**Files:**
- Modify: `~/src/dots-hyprland/dots/.config/quickshell/ii/modules/ii/lock/Lock.qml`

**Interfaces:**
- `Lock.focusedMonitorAtLock: string`, tracked live while unlocked and frozen while locked.
- `Lock.cursorAtLock: {x, y} | null`, read from `hyprctl cursorpos -j` when locking.
- `Lock.focusRestoreBatch(): string`, a bash fragment that focuses `focusedMonitorAtLock` and moves the pointer back; empty if that monitor is gone.

- [ ] **Step 1: Confirm the dispatcher exists**

```sh
P=$(hyprctl cursorpos -j | jq -r '"\(.x),\(.y)"'); echo "$P"
hyprctl dispatch 'hl.dsp.cursor.move({x=200, y=200})'; hyprctl cursorpos
hyprctl dispatch "hl.dsp.cursor.move({x=${P%,*}, y=${P#*,}})"
```

Expected: `ok`, then `200, 200`, then `ok` (pointer back where it was).

- [ ] **Step 2: Reproduce the bug**

Run on each monitor in turn. For the monitor name `NAME` and its centre `X Y` (`hyprctl monitors -j | jq -r '.[] | "\(.name) \(.x + (.width / .scale / 2 | floor)) \(.y + (.height / .scale / 2 | floor))"'`):

```sh
hyprctl dispatch 'hl.dsp.focus({monitor="NAME"})'
hyprctl dispatch 'hl.dsp.cursor.move({x=X+100, y=Y+100})'
hyprctl cursorpos; hyprctl monitors -j | jq -r '.[] | select(.focused).name'
qs -p "$II" ipc call lock activate
```

(Substitute the numbers for `X+100` and `Y+100`.) Ask the user to type the password to unlock, then run the last two query commands again. Expected before the fix: after unlock the focused monitor is the last monitor in `Quickshell.screens` and the pointer is at its centre, for both starting monitors.

- [ ] **Step 3: Add the Io import**

Edit `modules/ii/lock/Lock.qml`, old:

```qml
import Quickshell
import Quickshell.Hyprland
```

new:

```qml
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
```

- [ ] **Step 4: Add the recorded state, the focus tracker and the restore fragment**

Old:

```qml
    // Monitor name -> workspace id to restore on unlock (set when locking)
    property var savedWorkspaces: ({})
```

new:

```qml
    // Monitor name -> workspace id to restore on unlock (set when locking)
    property var savedWorkspaces: ({})
    property string focusedMonitorAtLock: ""
    property var cursorAtLock: null

    Binding {
        target: root
        property: "focusedMonitorAtLock"
        value: Hyprland.focusedMonitor?.name ?? ""
        when: !GlobalStates.screenLocked
        restoreMode: Binding.RestoreNone
    }

    function focusRestoreBatch() {
        const mon = root.focusedMonitorAtLock
        if (!Quickshell.screens.some(s => s.name === mon)) return ""
        let batch = `hyprctl dispatch 'hl.dsp.focus({monitor="${mon}"})';`
        if (root.cursorAtLock) batch += `hyprctl dispatch 'hl.dsp.cursor.move({x=${root.cursorAtLock.x}, y=${root.cursorAtLock.y}})';`
        return batch
    }

    function pushWorkspaces() {
        var next = {}
        var batch = "keyword animation workspaces,1,7,menu_decel,slidevert; "
        for (var i = 0; i < Quickshell.screens.length; ++i) {
            var mon = Quickshell.screens[i].name
            var mData = HyprlandData.monitors.find(m => m.name === mon)
            if (mData?.activeWorkspace == undefined) {
                return;
            }
            var ws = (mData?.activeWorkspace?.id ?? 1)
            next[mon] = ws
            batch += `hyprctl dispatch 'hl.dsp.focus({monitor="${mon}"})'; hyprctl dispatch 'hl.dsp.focus({workspace=${2147483647 - ws}})';`
        }
        root.savedWorkspaces = next
        Quickshell.execDetached(["bash", "-c", batch + root.focusRestoreBatch()])
    }

    Process {
        id: snapshotProc
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            id: snapshotCollector
            onStreamFinished: {
                root.cursorAtLock = JSON.parse(snapshotCollector.text)
                root.pushWorkspaces()
            }
        }
    }
```

- [ ] **Step 5: Append the restore fragment to the unlock batch**

Old:

```qml
            if (batch.length > 0) {
                Quickshell.execDetached(["bash", "-c", batch])
            }
```

new:

```qml
            batch += root.focusRestoreBatch()
            if (batch.length > 0) {
                Quickshell.execDetached(["bash", "-c", batch])
            }
```

- [ ] **Step 6: Replace the lock handler body with the snapshot trigger**

Old:

```qml
            if (GlobalStates.screenLocked) {
                // Lock: save workspace per monitor and move all to temp workspace in one batch
                var next = {}
                var batch = "keyword animation workspaces,1,7,menu_decel,slidevert; "
                for (var i = 0; i < Quickshell.screens.length; ++i) {
                    var mon = Quickshell.screens[i].name
                    var mData = HyprlandData.monitors.find(m => m.name === mon)
                    if (mData?.activeWorkspace == undefined) {
                        return;
                    }
                    var ws = (mData?.activeWorkspace?.id ?? 1)
                    next[mon] = ws
                    batch += `hyprctl dispatch 'hl.dsp.focus({monitor="${mon}"})'; hyprctl dispatch 'hl.dsp.focus({workspace=${2147483647 - ws}})';`
                }
                root.savedWorkspaces = next
                Quickshell.execDetached(["bash", "-c", batch])
            } else {
```

new:

```qml
            if (GlobalStates.screenLocked) {
                snapshotProc.running = true
            } else {
```

- [ ] **Step 7: Verify**

Restart ii (Task 0 step 6 restart command). Repeat the Step 2 sequence on each monitor, with the pointer deliberately off-centre (centre + 100, +100). Ask the user to unlock.

Expected: after unlock the focused monitor name equals the one before locking, and `hyprctl cursorpos` equals the value before locking (same x, y), for both starting monitors. Then:

```sh
qs log -p "$II" | rg -i 'error|TypeError|ReferenceError|Unable to assign|is not a' | head -20
```

Expected: no line beyond the Task 0 baseline.

- [ ] **Step 8: Commit in the clone**

```sh
cd ~/src/dots-hyprland && git status --short
git add dots/.config/quickshell/ii/modules/ii/lock/Lock.qml
git commit -m "lock: restore focus and pointer to the monitor focused at lock time" -m "The lock batch focused each monitor in turn and the unlock batch did it again, so the last monitor kept focus and Hyprland moved the pointer there." -m "Record the focused monitor and the pointer position (hyprctl cursorpos) before locking. Both batches end with a focus on that monitor and a pointer move back." -m "Drop when the lock no longer focuses monitors to switch workspaces."
```

Expected: status shows only `Lock.qml`; one commit.

---

## Task 2: Nearest empty workspace (hand-port of fork 03b134b)

**Files:**
- Modify: `~/src/dots-hyprland/dots/.config/quickshell/ii/modules/ii/lock/Lock.qml`

**Interfaces:**
- `Lock.occupiedWorkspaceIds(): Set<int>`, workspaces with at least one window.
- `Lock.nearestEmptyWorkspace(from, taken): int`.
- `Lock.pushWorkspaces(rules: array)`, `rules` is the `hyprctl workspacerules -j` array (entries have `workspaceString` and, when pinned, `monitor`).

Fork commit `03b134b` does not apply as written (its hunks target a different `Lock.qml`), so this is a hand-port. Not ported: `pushedTargets`, `lastProcessedLockWall`, `lastProcessedDarkmode` and the `MaterialThemeLoader` calls. To re-read it: `gh api repos/pctrade/end4-pC/commits/03b134b -H "Accept: application/vnd.github.patch"`.

- [ ] **Step 1: Confirm the rule JSON on this host**

```sh
hyprctl workspacerules -j
```

Expected: an entry `{"workspaceString": "1", ..., "monitor": "DP-2"}` (the rule from `hosts/tariognatha/display.nix`) next to `special:special`. If the key names differ, change `monitor` and `workspaceString` in Step 4 to match.

- [ ] **Step 2: Reproduce the old behaviour**

With windows open on DP-2 (workspace 1) and DP-1 (workspace 2) and one more window on workspace 3, lock and read the workspaces while locked (the command returns while locked):

```sh
qs -p "$II" ipc call lock activate; sleep 3
hyprctl monitors -j | jq -c '[.[] | {name, ws: .activeWorkspace.id}]'
```

Expected before the change: workspace ids near 2147483647. Ask the user to unlock.

- [ ] **Step 3: Replace the snapshot command and handler**

Old:

```qml
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            id: snapshotCollector
            onStreamFinished: {
                root.cursorAtLock = JSON.parse(snapshotCollector.text)
                root.pushWorkspaces()
            }
        }
```

new:

```qml
        command: ["bash", "-c", "printf '{\"cursor\":%s,\"rules\":%s}' \"$(hyprctl cursorpos -j)\" \"$(hyprctl workspacerules -j)\""]
        stdout: StdioCollector {
            id: snapshotCollector
            onStreamFinished: {
                const snapshot = JSON.parse(snapshotCollector.text)
                root.cursorAtLock = snapshot.cursor
                root.pushWorkspaces(snapshot.rules)
            }
        }
```

- [ ] **Step 4: Replace `pushWorkspaces` and add the two helpers**

Old:

```qml
    function pushWorkspaces() {
        var next = {}
        var batch = "keyword animation workspaces,1,7,menu_decel,slidevert; "
        for (var i = 0; i < Quickshell.screens.length; ++i) {
            var mon = Quickshell.screens[i].name
            var mData = HyprlandData.monitors.find(m => m.name === mon)
            if (mData?.activeWorkspace == undefined) {
                return;
            }
            var ws = (mData?.activeWorkspace?.id ?? 1)
            next[mon] = ws
            batch += `hyprctl dispatch 'hl.dsp.focus({monitor="${mon}"})'; hyprctl dispatch 'hl.dsp.focus({workspace=${2147483647 - ws}})';`
        }
        root.savedWorkspaces = next
        Quickshell.execDetached(["bash", "-c", batch + root.focusRestoreBatch()])
    }
```

new:

```qml
    function occupiedWorkspaceIds() {
        var ids = new Set()
        var list = Hyprland.workspaces.values
        for (var k = 0; k < list.length; ++k) {
            if ((list[k].toplevels?.values?.length ?? 0) > 0) {
                ids.add(list[k].id)
            }
        }
        return ids
    }

    function nearestEmptyWorkspace(from, taken) {
        var id = Math.max(from, 0) + 1
        while (taken.has(id)) {
            id++
        }
        return id
    }

    function pushWorkspaces(rules) {
        var taken = root.occupiedWorkspaceIds()
        for (var r = 0; r < rules.length; ++r) {
            if (rules[r].monitor && /^\d+$/.test(rules[r].workspaceString)) {
                taken.add(parseInt(rules[r].workspaceString))
            }
        }
        var currents = {}
        for (var i = 0; i < Quickshell.screens.length; ++i) {
            var current = Hyprland.monitorFor(Quickshell.screens[i])?.activeWorkspace?.id
            if (current == undefined) {
                return
            }
            currents[Quickshell.screens[i].name] = current
            taken.add(current)
        }
        var batch = "keyword animation workspaces,1,7,menu_decel,slidevert; "
        for (var name in currents) {
            var target = root.nearestEmptyWorkspace(currents[name], taken)
            taken.add(target)
            batch += `hyprctl dispatch 'hl.dsp.focus({monitor="${name}"})'; hyprctl dispatch 'hl.dsp.focus({workspace=${target}})';`
        }
        root.savedWorkspaces = currents
        Quickshell.execDetached(["bash", "-c", batch + root.focusRestoreBatch()])
    }
```

- [ ] **Step 5: Verify the empty-workspace choice**

Restart ii. With the Step 2 layout (DP-2 on 1, DP-1 on 2, a window on 3):

```sh
qs -p "$II" ipc call lock activate; sleep 3
hyprctl monitors -j | jq -c '[.[] | {name, ws: .activeWorkspace.id}]'
```

Expected: DP-2 on 4 and DP-1 on 5 (3 is in use). Ask the user to unlock, then repeat the monitors query. Expected: DP-2 on 1, DP-1 on 2 again, and `hyprctl workspaces -j | jq -c '[.[].id]'` lists no leftover temporary ids.

- [ ] **Step 6: Verify a rule-pinned workspace is skipped**

```sh
hyprctl eval 'hl.workspace_rule({workspace="4", monitor="DP-2"})'
hyprctl workspacerules -j | jq -c '[.[] | select(.monitor) | {workspaceString, monitor}]'
qs -p "$II" ipc call lock activate; sleep 3
hyprctl monitors -j | jq -c '[.[] | {name, ws: .activeWorkspace.id}]'
```

Expected: the rules list shows workspaces 1 and 4 pinned to DP-2; while locked DP-2 is on 5 and DP-1 on 6 (4 is skipped). Ask the user to unlock, then run `hyprctl reload config-only` to drop the temporary rule.

- [ ] **Step 7: Check the log**

```sh
qs log -p "$II" | rg -i 'error|TypeError|ReferenceError|Unable to assign|is not a' | head -20
```

Expected: no line beyond the baseline. Also repeat the Task 1 step 7 focus and pointer check once.

- [ ] **Step 8: Commit in the clone**

```sh
cd ~/src/dots-hyprland && git status --short
git add dots/.config/quickshell/ii/modules/ii/lock/Lock.qml
git commit -m "lock: move monitors to the nearest empty workspace" -m "The lock sent each monitor to workspace 2147483647 - n. Port of end4-pC 03b134b, which does not apply as written: pick the next workspace id with no windows that is not another monitor's current workspace. Also skip ids a workspace rule pins to a monitor (hyprctl workspacerules -j), or focusing one would pull focus to another monitor." -m "Not ported: pushedTargets, lastProcessedLockWall, MaterialThemeLoader." -m "Drop when the pinned ii picks an empty workspace on lock."
```

---

## Task 3: Prompt screen selection

**Files:**
- Modify: `~/src/dots-hyprland/dots/.config/quickshell/ii/GlobalStates.qml`
- Modify: `~/src/dots-hyprland/dots/.config/quickshell/ii/modules/ii/lock/Lock.qml`

**Interfaces:**
- `GlobalStates.lockPromptScreen: string`, the screen name that shows the prompt; empty only while `Lock.qml` is not loaded.
- `Lock.promptScreenName: string` (readonly): `lock.mainMonitor` if connected, else `focusedMonitorAtLock` if connected, else `Quickshell.screens[0].name`.

`Config.options.lock.mainMonitor` does not exist until Task 5, so it reads `undefined` here and the first rule is skipped; the second and third are exercised in this task, the first in Task 5.

- [ ] **Step 1: Add the global**

Edit `GlobalStates.qml`, old:

```qml
    property bool screenLockContainsCharacters: false
```

new:

```qml
    property bool screenLockContainsCharacters: false
    property string lockPromptScreen: ""
```

- [ ] **Step 2: Add the selection and its binding in `Lock.qml`**

Old:

```qml
    function focusRestoreBatch() {
```

new:

```qml
    readonly property string promptScreenName: {
        const names = Quickshell.screens.map(s => s.name)
        const main = Config.options.lock.mainMonitor
        if (main && names.includes(main)) return main
        if (names.includes(root.focusedMonitorAtLock)) return root.focusedMonitorAtLock
        return names[0] ?? ""
    }

    Binding {
        target: GlobalStates
        property: "lockPromptScreen"
        value: root.promptScreenName
    }

    function focusRestoreBatch() {
```

- [ ] **Step 3: Add a temporary log line (removed in Step 6)**

Old:

```qml
    readonly property string promptScreenName: {
```

new:

```qml
    onPromptScreenNameChanged: console.log("PROMPT", promptScreenName)
    readonly property string promptScreenName: {
```

- [ ] **Step 4: Verify the fallbacks**

Restart ii, then:

```sh
qs log -p "$II" | rg 'PROMPT'
```

Expected: a `PROMPT <name>` line, the focused monitor's name. Focus DP-1 (`hyprctl dispatch 'hl.dsp.focus({monitor="DP-1"})'`), lock, read the log: `PROMPT DP-1` is the last line. Ask the user to unlock; repeat with DP-2: last line `PROMPT DP-2`.

- [ ] **Step 5: Verify the re-evaluation when screens change**

Lock with DP-2 focused (`PROMPT DP-2`). While locked, disable DP-2:

```sh
hyprctl eval 'hl.monitor({output="DP-2", disabled=true})'; sleep 2
qs log -p "$II" | rg 'PROMPT' | tail -2
```

Expected: a new line `PROMPT DP-1`. If Hyprland rejects `disabled`, unplug the DP-2 cable instead. Restore with `hyprctl reload` (or re-plug), ask the user to unlock.

- [ ] **Step 6: Remove the temporary line and check**

Edit `Lock.qml`, old: `    onPromptScreenNameChanged: console.log("PROMPT", promptScreenName)\n` new: empty. Then:

```sh
cd ~/src/dots-hyprland && git diff --stat && rg -n 'console.log' dots/.config/quickshell/ii/modules/ii/lock/Lock.qml
qs log -p "$II" | rg -i 'error|TypeError|ReferenceError|Unable to assign|is not a' | head -20
```

Expected: two files changed; no `console.log` match; no log line beyond the baseline.

- [ ] **Step 7: Commit in the clone**

```sh
cd ~/src/dots-hyprland
git add dots/.config/quickshell/ii/GlobalStates.qml dots/.config/quickshell/ii/modules/ii/lock/Lock.qml
git commit -m "lock: pick the prompt screen" -m "GlobalStates.lockPromptScreen holds the name of the screen that shows the lock prompt: lock.mainMonitor if connected, else the monitor focused at lock time, else the first screen. It follows Quickshell.screens, so unplugging the prompt screen while locked moves it. Nothing reads it yet." -m "Drop when upstream chooses one lock prompt screen."
```

---

## Task 4: Show the prompt and widgets on the prompt screen only

**Files:**
- Modify: `~/src/dots-hyprland/dots/.config/quickshell/ii/modules/common/panels/lock/LockScreen.qml`
- Modify: `~/src/dots-hyprland/dots/.config/quickshell/ii/modules/ii/lock/Lock.qml`
- Modify: `~/src/dots-hyprland/dots/.config/quickshell/ii/modules/ii/background/Background.qml`
- `modules/ii/lock/LockSurface.qml` and `modules/waffle/lock/WaffleLock.qml` stay unchanged: the surface is hidden from `LockScreen`'s loader, so the waffle lock (which never sets the property) is unchanged.

**Interfaces:**
- `LockScreen.promptScreen: string`, default `""` meaning every screen. Only `Lock.qml` sets it.
- The lock surface stays loaded on every screen (typing on any monitor reaches `LockContext.currentText`); on other screens its opacity is 0.

- [ ] **Step 1: Add the property to `LockScreen.qml`**

Old:

```qml
    property alias context: lockContext
```

new:

```qml
    property alias context: lockContext
    property string promptScreen: ""
```

- [ ] **Step 2: Fade the loaded surface out on other screens**

Old:

```qml
            opacity: active ? 1 : 0
```

new:

```qml
            readonly property bool onPromptScreen: root.promptScreen === "" || sessionLockSurface.screen?.name === root.promptScreen
            opacity: active && onPromptScreen ? 1 : 0
```

- [ ] **Step 3: Set it from `Lock.qml`**

Old:

```qml
    property string focusedMonitorAtLock: ""
```

new:

```qml
    promptScreen: GlobalStates.lockPromptScreen
    property string focusedMonitorAtLock: ""
```

- [ ] **Step 4: Hide the widget canvas on other screens**

Edit `modules/ii/background/Background.qml`, old:

```qml
            WidgetCanvas {
                id: widgetCanvas
                width: parent.width
                height: parent.height
```

new:

```qml
            WidgetCanvas {
                id: widgetCanvas
                width: parent.width
                height: parent.height
                visible: !GlobalStates.screenLocked || GlobalStates.lockPromptScreen === "" || bgRoot.screen.name === GlobalStates.lockPromptScreen
```

- [ ] **Step 5: Verify**

Restart ii. Focus DP-1 (`hyprctl dispatch 'hl.dsp.focus({monitor="DP-1"})'`) and lock with `qs -p "$II" ipc call lock activate`.

Expected: on DP-1 the password toolbar, clock and weather; on DP-2 only the blurred wallpaper. With the pointer on DP-2, type a few characters without clicking: dots appear in DP-1's field (the surface under the pointer takes the keys, `LockContext` shares them). Ask the user to unlock with the pointer on either monitor: it unlocks. Repeat focusing DP-2: the prompt is on DP-2.

Turn the blur off in Settings (SUPER + I, Interface, Lock screen, "Enable blur"), lock: the monitor without the prompt shows the unblurred wallpaper. Turn it back on.

```sh
qs log -p "$II" | rg -i 'error|TypeError|ReferenceError|Unable to assign|is not a' | head -20
```

Expected: no line beyond the baseline (in particular no `sessionLockSurface` or `screen` binding error).

- [ ] **Step 6: Commit in the clone**

```sh
cd ~/src/dots-hyprland && git status --short
git add dots/.config/quickshell/ii/modules/common/panels/lock/LockScreen.qml dots/.config/quickshell/ii/modules/ii/lock/Lock.qml dots/.config/quickshell/ii/modules/ii/background/Background.qml
git commit -m "lock: show the prompt and widgets on the prompt screen only" -m "Every monitor showed the password field, clock and weather. LockScreen gets promptScreen (empty: every screen; only the ii lock sets it, so the waffle lock is unchanged). Other screens keep the lock surface loaded at zero opacity, so typing on any monitor still reaches the password field. Background hides the widget canvas on those screens while locked; they keep the wallpaper and blur." -m "Drop when upstream shows the lock prompt on one monitor."
```

---

## Task 5: `lock.mainMonitor` setting

**Files:**
- Modify: `~/src/dots-hyprland/dots/.config/quickshell/ii/modules/common/Config.qml`
- Modify: `~/src/dots-hyprland/dots/.config/quickshell/ii/modules/settings/InterfaceConfig.qml`

**Interfaces:**
- `Config.options.lock.mainMonitor: string`, default `""` (focused monitor). Read by `Lock.promptScreenName`.
- Settings, Interface, Lock screen, "Main monitor": a `ConfigComboBox` whose first entry is "Focused monitor" (value `""`), then the connected monitor names, then a saved name whose monitor is unplugged.

- [ ] **Step 1: Add the option, away from the `launchOnStartup` line**

Edit `modules/common/Config.qml`, old:

```qml
                property bool materialShapeChars: true
```

new:

```qml
                property bool materialShapeChars: true
                property string mainMonitor: ""
```

(The edit fails on zero or several matches; if it matches more than once, include the following `}` line from the `lock` object to make it unique.)

- [ ] **Step 2: Import Quickshell in `InterfaceConfig.qml`**

Old:

```qml
import QtQuick
import QtQuick.Layouts
import qs
```

new:

```qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
```

- [ ] **Step 3: Add the row after "Launch on startup"**

Old:

```qml
                    onCheckedChanged: { Config.options.lock.launchOnStartup = checked }
                }
```

new:

```qml
                    onCheckedChanged: { Config.options.lock.launchOnStartup = checked }
                }
                ConfigComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "monitor"
                    text: Translation.tr("Main monitor")
                    description: Translation.tr("Shows the password prompt, clock and weather. Other monitors show the wallpaper only.")
                    fieldWidth: 240
                    model: {
                        const saved = Config.options.lock.mainMonitor
                        const names = Quickshell.screens.map(s => s.name)
                        if (saved && !names.includes(saved)) names.push(saved)
                        return [{ displayName: Translation.tr("Focused monitor"), value: "" }, ...names.map(name => ({ displayName: name, value: name }))]
                    }
                    currentValue: Config.options.lock.mainMonitor
                    onSelected: newValue => { Config.options.lock.mainMonitor = newValue }
                }
```

- [ ] **Step 4: Confirm the `launchOnStartup` line is untouched**

```sh
cd ~/src/dots-hyprland && git diff -U0 dots/.config/quickshell/ii/modules/common/Config.qml | rg 'launchOnStartup'; git diff --stat
```

Expected: the `rg` prints nothing; two files changed.

- [ ] **Step 5: Verify the setting**

Restart ii; open Settings (SUPER + I), Interface, "Lock screen".

Expected: a "Main monitor" row showing "Focused monitor"; its list is "Focused monitor", `DP-1`, `DP-2`. Choose `DP-1`:

```sh
jq -r '.lock.mainMonitor' ~/.config/illogical-impulse/config.json
```

Expected: `DP-1`. Lock with DP-2 focused: the prompt, clock and weather are on DP-1 only; DP-2 shows the wallpaper; typing works with the pointer on either monitor; the user unlocks. Choose `DP-2`: the prompt is on DP-2. Choose "Focused monitor": the value is `""` and the prompt follows the focused monitor.

Disconnected name: set it by hand and reopen the page.

```sh
jq --indent 4 '.lock.mainMonitor = "HDMI-A-9"' ~/.config/illogical-impulse/config.json > ~/.config/illogical-impulse/config.json.tmp && mv ~/.config/illogical-impulse/config.json.tmp ~/.config/illogical-impulse/config.json
```

Expected: the row shows `HDMI-A-9` and the list includes it; locking puts the prompt on the focused monitor. Set the row back to "Focused monitor" afterwards.

```sh
qs log -p "$II" | rg -i 'error|TypeError|ReferenceError|Unable to assign|is not a' | head -20
```

Expected: no line beyond the baseline.

- [ ] **Step 6: Commit in the clone**

```sh
cd ~/src/dots-hyprland && git status --short
git add dots/.config/quickshell/ii/modules/common/Config.qml dots/.config/quickshell/ii/modules/settings/InterfaceConfig.qml
git commit -m "feat(lock): main monitor setting" -m "lock.mainMonitor names the monitor that shows the lock prompt; empty means the focused monitor. Settings, Interface, Lock screen has a dropdown of the connected monitors with a Focused monitor entry; a saved monitor that is unplugged stays listed." -m "Drop when upstream has a lock monitor setting."
git log --oneline krane -6
```

Expected: five new commits above the previous series tip.

---

## Task 6: Tag and export the series

**Files:**
- Create: `~/.dotfiles/patches/ii/11-lock/0001-*.patch` through `0005-*.patch`

- [ ] **Step 1: Tag the last commit**

```sh
git -C ~/src/dots-hyprland tag -f krane/11-lock
```

- [ ] **Step 2: Run the export loop from docs/II-INTEGRATION.md "Workflow"**

```sh
cd ~/src/dots-hyprland
if [ -d .git/rebase-apply ]; then
  echo "an am/rebase is still in progress; finish it before exporting" >&2
  exit 1
fi
PIN=${PIN:-$(jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock)}
prev="$PIN"
mkdir -p ~/.dotfiles/patches/ii/11-lock
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

- [ ] **Step 3: Check the export**

```sh
ls ~/.dotfiles/patches/ii/11-lock
git -C ~/.dotfiles status --short
```

Expected: five patches (`0001-lock-restore-focus-and-pointer-to-the-monitor-foc.patch` and so on); status lists only `?? patches/ii/11-lock/`. Any modified file in another series means the clone and `patches/ii` disagree: stop and find out why before continuing.

- [ ] **Step 4: Stage the patches**

```sh
git -C ~/.dotfiles add patches/ii
```

---

## Task 7: Docs

**Files:**
- Modify: `~/.dotfiles/docs/II-INTEGRATION.md`
- Modify: `~/.dotfiles/docs/VERIFY.md`

- [ ] **Step 1: Add the series to the list in "Backported fork fixes"**

Edit `docs/II-INTEGRATION.md`, old:

```
`01-fixes`, `02-translator`, `04-agents`, `05-settings`, `06-notifications`
and `07-idle`.
```

new:

```
`01-fixes`, `02-translator`, `04-agents`, `05-settings`, `06-notifications`,
`07-idle`, `08-bar-popouts` and `11-lock`.
```

If another series (`09-*`, `10-*`) has landed and the sentence already lists it, keep every entry in directory order and only add the missing `08-bar-popouts` and `11-lock`.

- [ ] **Step 2: Add the `### 11-lock` section before `### Workflow`**

Old:

```
### Workflow
```

new:

```
### `11-lock`

Lock screen fixes (pctrade/end4-pC#72) and a main-monitor setting.

- `0001`: lock and unlock leave focus and the pointer on the monitor that was
  focused at lock time.
- `0002`: lock moves each monitor to the nearest empty workspace, skipping
  workspaces a rule pins to a monitor (`hyprctl workspacerules -j`). Hand-port
  of fork commit `03b134b` without its `pushedTargets`, `lastProcessedLockWall`
  and `MaterialThemeLoader` parts.
- `0003` to `0005`: the prompt, clock and weather show on one monitor,
  `GlobalStates.lockPromptScreen`: `lock.mainMonitor` (Settings, Interface,
  "Lock screen", "Main monitor") if connected, else the monitor focused at lock
  time, else the first screen. The choice follows `Quickshell.screens`. Other
  monitors show the wallpaper only. `LockSurface` stays loaded on every
  monitor at zero opacity there, so typing on any monitor reaches the password
  field. `LockScreen.promptScreen` defaults to every screen and only `Lock.qml`
  sets it, so the waffle lock is unchanged.

### Workflow
```

(If a `### 09-*` or `### 10-*` section exists, the new section goes after it, still before `### Workflow`.)

- [ ] **Step 3: Add the checks to VERIFY.md**

Edit `docs/VERIFY.md`, old:

```
### Checks

| Check |
```

new:

```
### Lock screen

Run on a host with two monitors (tariognatha). Lock with `qs -c ii ipc call lock activate`.

- With the pointer on each monitor in turn, lock and unlock: the pointer position and the focused monitor (`hyprctl monitors -j | jq -r '.[] | select(.focused).name'`) are back where they were.
- Set Settings, Interface, "Lock screen", "Main monitor" to each monitor: the password prompt, clock and weather appear only there, the other monitor shows the wallpaper, typing works with the pointer on either monitor, and the password unlocks.
- With "Focused monitor" selected, and with a saved name whose monitor is unplugged: the prompt appears on the monitor that was focused at lock time.
- Unplug the prompt monitor while locked: the prompt moves to the remaining monitor.
- Boot with `launchOnStartup` on, with "Main monitor" set and then empty: a prompt appears either way.
- Turn "Enable blur" off: the monitor without the prompt shows the unblurred wallpaper.
- Lock with windows open on both monitors: `hyprctl monitors -j | jq -c '[.[] | .activeWorkspace.id]'` shows empty workspaces that no window and no workspace rule uses; the original workspaces return after unlock.
- Waffle lock, on a host that enables it: unchanged.

### Checks

| Check |
```

(The `### Checks` heading is followed by the table header `| Check | Command | Host |`; the edit anchors on `### Checks` plus the first cell, so it matches once.)

- [ ] **Step 4: Stage**

```sh
git -C ~/.dotfiles add docs/II-INTEGRATION.md docs/VERIFY.md
git -C ~/.dotfiles diff --cached --stat
```

Expected: the `11-lock` patches and the two docs.

---

## Task 8: Build and runtime verification

**Files:** none changed.

- [ ] **Step 1: Build the host (patches staged)**

```sh
cd "$(mktemp -d)" && nixos-rebuild build --flake ~/.dotfiles#tariognatha 2>&1 | tail -15
```

Expected: exit 0, a `result` link. A patch that fails to apply names its file in the error: go back to Task 6.

- [ ] **Step 2: Confirm the patched source holds the series**

```sh
rg -l lockPromptScreen /nix/store/*-dots-hyprland-patched/dots/.config/quickshell/ii/GlobalStates.qml
```

Expected: at least one path (the new build's).

- [ ] **Step 3: Restart ii from the clone (tip of `krane`) and run every check below**

Use the Task 0 step 6 restart command. The user types the password for each unlock.

- [ ] **Step 4: Pointer and focus.** For DP-1 and DP-2 in turn (focus, then move the pointer to centre + 100, +100), lock and unlock. Expected: focused monitor and `hyprctl cursorpos` identical before and after.
- [ ] **Step 5: Main monitor DP-1, then DP-2.** Set it in Settings, Interface, Lock screen. Lock with the other monitor focused. Expected: prompt, clock and weather only on the chosen monitor; the other shows the wallpaper; typing works with the pointer on either monitor; the password unlocks.
- [ ] **Step 6: Empty name and unplugged name.** "Focused monitor", then `jq --indent 4 '.lock.mainMonitor = "HDMI-A-9"'` on `~/.config/illogical-impulse/config.json` (write to a temp file, then `mv`). Expected: for each, the prompt is on the monitor focused at lock time.
- [ ] **Step 7: Unplug while locked.** Main monitor DP-2, lock, then `hyprctl eval 'hl.monitor({output="DP-2", disabled=true})'` (or unplug the cable). Expected: the prompt appears on DP-1 within a few seconds and unlocks. Restore with `hyprctl reload` (or re-plug).
- [ ] **Step 8: Blur off.** Turn "Enable blur" off and lock. Expected: the monitor without the prompt shows the unblurred wallpaper. Turn it back on.
- [ ] **Step 9: Workspaces.** Windows on both monitors plus one on workspace 3, then the Task 2 steps 5 and 6 checks. Expected: monitors move to empty workspaces (4 and 5; with the temporary rule 5 and 6), the used workspace 3 and the rule-pinned workspaces are not taken, and the original workspaces return after unlock.
- [ ] **Step 10: Waffle lock.** Only on a host that enables the waffle family; tariognatha does not, so record "not applicable". `modules/waffle/lock/WaffleLock.qml` is unchanged and never sets `promptScreen`.
- [ ] **Step 11: Log.**

```sh
qs log -p "$II" | rg -i 'error|TypeError|ReferenceError|Unable to assign|is not a' | head -20
```

Expected: no line beyond the Task 0 baseline.

- [ ] **Step 12: Boot through lock-on-start (needs the user's approval)**

This needs the new generation running. Ask the user before running it:

```sh
sudo nixos-rebuild switch --flake ~/.dotfiles#tariognatha
```

Then, with the user, log out or reboot (autologin starts Hyprland and ii locks). Expected, once with "Main monitor" set to a monitor and once with it empty: a password prompt appears on the chosen (or first) monitor, and `journalctl --user -b | grep krane-lock-on-start` prints nothing. Set "Main monitor" in Settings between the two boots. If the user declines, record this step as not run.

- [ ] **Step 13: Restore the live shell and test-only state**

```sh
pkill -f '[q]s-wrapped'; sleep 1; qs -c ii -d
hyprctl reload config-only
git -C ~/.dotfiles diff --stat hosts/tariognatha/illogical-impulse/config.json
```

Expected: ii runs from `~/.config/quickshell/ii` again. If `config.json` shows a diff, it is the new `"mainMonitor"` key ii writes or a test value: revert with `git -C ~/.dotfiles checkout -- hosts/tariognatha/illogical-impulse/config.json` (ii re-adds the key on its next save).

---

## Task 9: Commit in ~/.dotfiles

- [ ] **Step 1: Check the staged set**

```sh
git -C ~/.dotfiles status --short
```

Expected: only `patches/ii/11-lock/*`, `docs/II-INTEGRATION.md`, `docs/VERIFY.md` (and the untracked plan and spec if they are not committed yet; leave them out).

- [ ] **Step 2: Commit on main (subject only)**

```sh
git -C ~/.dotfiles add patches/ii docs/II-INTEGRATION.md docs/VERIFY.md
git -C ~/.dotfiles commit -m "Add lock patch series"
```

Expected: one commit on `main`; no push.

---

## Task 10: Remove the plan and spec

Run only after verification and the final review pass, and only after the user's explicit approval. Ask the user first and stop if they decline or want changes.

- [ ] **Step 1: Delete and commit**

```sh
git -C ~/.dotfiles rm docs/superpowers/plans/2026-11-28-lock-fixes.md docs/superpowers/specs/2026-11-28-lock-fixes-design.md
git -C ~/.dotfiles commit -m "Remove lock fixes spec and plan"
```

Expected: one commit; `git -C ~/.dotfiles status --short` is empty. Do not push.
