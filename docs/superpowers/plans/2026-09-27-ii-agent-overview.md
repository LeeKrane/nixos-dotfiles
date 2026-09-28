# Sidebar Agents Tab and Claude Code Notifications — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make sure a blocked Claude Code session raises a desktop notification, then add an "Agents" tab to ii's left sidebar that lists every Claude Code session, shows its state, and focuses its terminal on click.

**Architecture:** Step 0 is a manual check. If it finds no notification, it adds a `claude-notify` package to this repo (`pkgs/claude-notify`, installed from `modules/home/dev.nix` like the other Claude Code hook binaries) and a `Notification` hook entry in `~/.claude/settings.json`, which belongs to the separate claude-dotfiles repo checked out at `~/.claude`. The tab is two commits on the `krane` branch of the dots-hyprland clone, after `krane/03-dock`, exported to `patches/ii/04-agents/`. Sub-project 1's `iiSeries` loader applies them with no Nix change. A bash script wraps `claude agents --json` and adds pid ancestry and transcript mtime. A QML singleton polls that script only while the tab is visible. Pure JS helpers do the window matching, sorting and error classification, so node can test them outside Quickshell.

**Tech Stack:** Nix flakes, home-manager, `writeShellApplication`, git (`apply`, `format-patch`, `am -3`), Quickshell QML, bash, jq, node (`node:test`), Claude Code 2.1.280 (`claude agents --json`, hooks).

**Spec:** `docs/superpowers/specs/2026-09-27-ii-agent-overview-design.md`

## Global Constraints

- Run every shell block with `bash` (the interactive shell is fish). In commands you type, use `command cat`, never bare `cat`.
- Sub-projects 1–3 are already executed. `lib/mk-host.nix` has the `iiSeries` loader. `patches/ii/01-fixes`, `02-translator` and `03-dock` exist. In `~/src/dots-hyprland`, branch `krane` ends at tag `krane/03-dock`.
- Pinned dots-hyprland revision: `jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock` (currently `97c5bc651f68092351b24aaa935af708b1e04514`). Pinned ii source: `/nix/store/xwkyskh3ylwwbhvff97z8jivcxmnbcg8-source/dots/.config/quickshell/ii`.
- Export command for this sub-project, always exactly:
  ```bash
  git -C ~/src/dots-hyprland tag -f krane/04-agents krane
  mkdir -p ~/.dotfiles/patches/ii/04-agents
  rm -f ~/.dotfiles/patches/ii/04-agents/*.patch && git -C ~/src/dots-hyprland format-patch --zero-commit --no-signature --no-numbered -o ~/.dotfiles/patches/ii/04-agents krane/03-dock..krane/04-agents
  ```
- Clone commit messages (sub-project 1's format, new work):
  ```
  <subject>

  Problem: <one or two lines>
  Port: new (no fork origin)
  Drop when: the pinned ii ships an equivalent agents tab, or `claude agents --json` is removed.
  ```
- Dotfiles repo commit messages: subject line only, no body, no attribution lines. Never push.
- `~/.claude` is the claude-dotfiles repo (`origin` = `LeeKrane/claude-dotfiles`). Never commit or push there yourself. Its changes ship only when the user runs `/dotfiles-release`, which fetches and refuses if `origin` is ahead, then bumps `CHANGELOG.md`, syncs README/SETUP, commits and pushes. The push reaches every machine that later pulls and runs `/dotfiles-apply`, so anything added there must be harmless on machines without this repo's packages. Never run `/dotfiles-release` yourself.
- The only interface parsed is `claude agents --json`. Transcripts are only `stat`ed for their mtime and never read. Nothing reads `~/.claude/.credentials.json`.
- The tab never sends input, approves, stops or deletes a session. It only focuses windows and runs `kitty -e claude attach <id>`.
- No new runtime dependencies beyond `claude`, `jq`, `bash` (and `awk`/`stat` from coreutils/gawk, already used by ii's scripts; `pgrep` from procps if Task 5, Step 12 applies). Step 0 adds `notify-send` (libnotify).
- Nothing in this repo writes `~/.config/illogical-impulse/config.json`. The only edit is Task 5, Step 10's backed-up, restored test edit.
- If a check in this plan runs after sub-project 5 has landed, `~/.config/illogical-impulse` is a symlink into this repo (`hosts/<host>/illogical-impulse/`) and `config.json` is a tracked file. Restore every test edit exactly, never stage `config.json` (the user commits it after a privacy review), and check `git -C ~/.dotfiles status --short hosts/` before any repo commit.
- Scratch work: `mktemp -d -p "$XDG_RUNTIME_DIR"`.

### Checking the built source

This block prints the patched ii source path for the current host (it is the same block as in sub-project 1). The patched ii source is the same on every host (same pinned input, same patches), so checking one host is enough:

```bash
cd ~/.dotfiles
host=${host:-$(hostname)}
gen=$(nix build --no-link --print-out-paths .#nixosConfigurations.$host.config.home-manager.users.krane.home.activationPackage)
iisrc=$(grep -rhoE '/nix/store/[a-z0-9]{32}-dots-hyprland-[a-z-]+' "$gen" | sort -u | head -1)
echo "$iisrc"
```

Expected: the path ends in `-dots-hyprland-patched`. Flakes only see git-tracked files, so `git add` new patch files before running it.

## Assumed decisions

These are the spec's open questions, answered with the spec's recommended defaults, plus the choices this plan makes where the spec left room.

1. Headless (SDK) sessions are hidden. The header shows only their count, and there is no toggle.
2. No preview of the last message. Transcripts are never read.
3. Refresh every 3 s while the tab is visible. A run slower than 1 s doubles the interval, up to 15 s, and a fast run resets it to 3 s.
4. If terminal titles are disabled (`CLAUDE_CODE_DISABLE_TERMINAL_TITLE`), the degradation is accepted. Interactive sessions still match by pid. Only background sessions and several windows of one terminal process lose precise focus.
5. The patches live in `patches/ii/04-agents/` (decided in the spec).
6. The optional Claude `extraModels` entry is documented, marked optional and pay-per-token.
7. No bar indicator and no launcher-search category in this version.
8. `~/.claude/settings.json` is not brought under home-manager. The hook entry goes into the claude-dotfiles repo at `~/.claude`, which already tracks `settings.json` and documents each hook in its README "Hooks" table and SETUP "Tools" table. The user releases it with `/dotfiles-release`.
9. (Plan choice) `claude-notify` is a flake package, `pkgs/claude-notify/default.nix`, rather than an inline `writeShellApplication` in `dev.nix`. It is still installed from `dev.nix`, next to `rtk` and `codegraph`. This follows `pkgs/proton-drive-mount`, and it means `nix build .#claude-notify` can build and test it on its own.
10. (Plan choice) The `sidebar.agents` block goes directly after `sidebar.ai`, not directly after `sidebar.translator`. The hunk's context then never includes the `sidebar.translator.enable` line that `02-translator` changes.
11. (Plan choice) The pure logic lives in `services/claude-agents.js`, next to `ClaudeAgents.qml`. This follows ii's own `levendist.js`/`Levendist.qml` pattern. Its tests live in this repo under `scripts/ii-agents/` and take the ii root as an argument, so they run against the clone or against a built store path.
12. (Plan choice) `SidebarLeftContent.qml` sets `ClaudeAgents.active` through a `Binding`, keyed on the current swipe item's `objectName` and `GlobalStates.sidebarLeftOpen` only. The detached window (Ctrl+D) is visible exactly while `sidebarLeftOpen` is true (pinned `SidebarLeft.qml:181-184`), so no `detach` term is needed; adding one would keep polling while a detached sidebar is toggled hidden.

## Review Focus

1. **Unnamed sessions.** A background session with an empty `name` must never focus a window whose title is also empty. Expected: no window, and a click opens an attach terminal (Task 2, test "background with an empty name…").
2. **Unknown `status`/`state` after a claude-code bump.** Agent view is a research preview. Expected: the row stays, with a neutral dot and the raw value in the subtitle, and nothing throws (Task 2, test "effectiveStatus…keeps unknown values raw"; Task 3 renders the raw value).
3. **Sessions in tmux, over SSH, or in a TTY.** No ancestor owns a Hyprland window. Expected: counted in "K headless hidden", never focused onto an unrelated window (Task 2, test "interactive: no window owner means null").
4. **Detached sidebar (Ctrl+D).** Expected: the tab keeps refreshing while the detached window shows it, polling stops when the detached window is hidden with the sidebar toggle, and it stays stopped once the sidebar is reattached and closed (Task 5, Step 9).
5. **`claude agents --json` failing repeatedly.** Expected: the last list stays, the error line shows the first stderr line, polling stops after 3 consecutive failures, and it resumes when the tab is reopened (Task 2, test "classifyResult…"; Task 5, Step 8).

---

### Task 1: Step 0, a desktop notification for a blocked session

Checks first. Code is added only if no notification appears. Record which branch was taken; Task 4 documents it.

**Files (only if the hook is needed):**
- Create: `pkgs/claude-notify/default.nix`
- Modify: `pkgs/default.nix` (register the package)
- Modify: `modules/home/dev.nix` (add to `home.packages`, after `codegraph # Claude Code hooks`)
- Modify, in the claude-dotfiles repo: `~/.claude/settings.json` (`hooks.Notification`), `~/.claude/README.md` ("Hooks" table), `~/.claude/SETUP.md` ("3. Tools" table)

**Interfaces:**
- Produces: the executable `claude-notify` on every host's PATH. It reads a Notification hook JSON on stdin (`cwd`, `message`, `notification_type`), always exits 0 and never blocks. The hook entry calls it as `command -v claude-notify >/dev/null && claude-notify || true`, so machines sharing `~/.claude` without the package are unaffected.

- [ ] **Step 1: Confirm `~/.claude` is clean**

```bash
git -C ~/.claude status --short
jq '{hooks: (.hooks | keys), preferredNotifChannel}' ~/.claude/settings.json
```

Expected: `git status` prints nothing; hooks are `["PreToolUse","UserPromptSubmit"]` and `preferredNotifChannel` is `null`. If `git status` shows changes, stop and ask the user. The revert in Step 3 would throw them away.

- [ ] **Step 2: Baseline check (manual)**

1. On workspace 2, open a kitty window (Super+Enter) and start `claude` in `~/.dotfiles`.
2. Send: `Use the Bash tool to run: touch /tmp/claude-notify-probe`. A permission prompt appears, because `touch` is not on the allow list.
3. Before answering it, switch to workspace 1 and close the left sidebar. Wait 60 s.
4. Note whether a desktop notification (ii's notification popup) appeared, and what it said. Then go back and deny the prompt with Esc.

If a notification appeared, skip to Step 13 and record "terminal notifications, `preferredNotifChannel` auto".

- [ ] **Step 3: Try the kitty notification channel**

```bash
cd ~/.claude
jq '.preferredNotifChannel = "kitty"' settings.json > settings.json.tmp && command cat settings.json.tmp > settings.json && rm settings.json.tmp
git diff --stat
```

Expected: `settings.json | 2 +-`. Start a **new** `claude` session (settings load at start) and repeat Step 2.

If a notification appeared now, keep this change, skip to Step 12, and record "terminal notifications, `preferredNotifChannel` kitty". Otherwise revert it and continue:

```bash
git -C ~/.claude checkout -- settings.json
```

- [ ] **Step 4: Write the failing check**

```bash
cd ~/.dotfiles && nix build --no-link .#claude-notify
```

Expected: FAIL with `does not provide attribute 'packages.x86_64-linux.claude-notify'`.

- [ ] **Step 5: Create `pkgs/claude-notify/default.nix`**

```nix
# Claude Code Notification hook: a desktop notification when a session waits
# on a permission prompt, an idle prompt or a dialog, so a session in a kitty
# window on another workspace is not missed. The hook entry lives in
# ~/.claude/settings.json (the claude-dotfiles repo) and calls `claude-notify`
# by name. Never blocks (no --wait) and always exits 0, so a missing
# notification daemon or odd input never shows up as a hook error.
{
  writeShellApplication,
  jq,
  libnotify,
  coreutils,
}:
writeShellApplication {
  name = "claude-notify";
  runtimeInputs = [
    jq
    libnotify
    coreutils
  ];
  text = ''
    in=$(cat) || in='{}'
    cwd=$(jq -r '.cwd // "?"' <<<"$in" 2>/dev/null) || cwd="?"
    body=$(jq -r '.message // .notification_type // "needs attention"' <<<"$in" 2>/dev/null) || body="needs attention"
    notify-send -a "Claude Code" -i utilities-terminal "Claude Code · $(basename "$cwd")" "$body" || true
  '';
  meta.mainProgram = "claude-notify";
}
```

In `pkgs/default.nix`, add this line directly after the `claude-code = pkgs.callPackage ./claude-code/package.nix { };` line (currently line 5), before the blank line and `plymouth-lone = …`:

```nix
  claude-notify = pkgs.callPackage ./claude-notify { };
```

```bash
cd ~/.dotfiles && git add pkgs/claude-notify pkgs/default.nix
```

- [ ] **Step 6: Run the checks**

```bash
cd ~/.dotfiles
out=$(nix build --no-link --print-out-paths .#claude-notify)
echo 'not json' | DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent "$out/bin/claude-notify"; echo "rc=$?"
printf '' | DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent "$out/bin/claude-notify"; echo "rc=$?"
echo '{"cwd":"/home/krane/.dotfiles","message":"Claude needs your permission to use Bash","notification_type":"permission_prompt"}' | "$out/bin/claude-notify"; echo "rc=$?"
```

Expected: the build succeeds (shellcheck runs as part of it); `rc=0` three times. The third command shows a popup titled `Claude Code · .dotfiles` with body `Claude needs your permission to use Bash`.

- [ ] **Step 7: Install it on every host**

In `modules/home/dev.nix`, after the line `    codegraph # Claude Code hooks`, add:

```nix
    claude-notify # Claude Code Notification hook (pkgs/claude-notify)
```

```bash
cd ~/.dotfiles
for h in tariognatha tarmantria taractias; do nixos-rebuild dry-build --flake .#$h || echo "FAIL $h"; done
```

Expected: no `FAIL` lines.

- [ ] **Step 8: Commit**

```bash
cd ~/.dotfiles
git add pkgs/claude-notify pkgs/default.nix modules/home/dev.nix
git commit -m "Add claude-notify, a desktop notification hook for blocked Claude Code sessions"
```

- [ ] **Step 9: Switch and confirm it is on PATH**

```bash
cd ~/.dotfiles && sudo nixos-rebuild switch --flake .#$(hostname)
command -v claude-notify
```

Expected: `/etc/profiles/per-user/krane/bin/claude-notify`.

- [ ] **Step 10: Add the hook entry in the claude-dotfiles repo**

```bash
cd ~/.claude
jq '.hooks.Notification = [{"matcher": "permission_prompt|idle_prompt|elicitation_dialog", "hooks": [{"type": "command", "command": "command -v claude-notify >/dev/null && claude-notify || true"}]}]' settings.json > settings.json.tmp && command cat settings.json.tmp > settings.json && rm settings.json.tmp
git diff
```

Expected: the diff only adds the `"Notification": [ … ]` block inside `"hooks"`. The command is guarded because `settings.json` is shared by every machine that pulls the claude-dotfiles repo, including non-NixOS ones (its SETUP.md installs with `dnf`) where `claude-notify` does not exist; there the hook is a silent no-op instead of a hook error on every notification. If jq changed any other line (escaping, number format), undo with `git checkout -- settings.json` and add the block by hand instead.

In `~/.claude/README.md`, under `### Hooks`, add this row after the `PreToolUse (Bash)` row:

```markdown
| Notification (`permission_prompt`, `idle_prompt`, `elicitation_dialog`) | `claude-notify` (skipped when not installed) | Desktop notification when a session waits on you | claude-notify (optional) |
```

In `~/.claude/SETUP.md`, in the `## 3. Tools` table, add this row after the `codegraph` row:

```markdown
| claude-notify | Notification hook (optional) | NixOS hosts managed by `~/.dotfiles`: installed by `just switch <host>` (`pkgs/claude-notify`). Elsewhere there is no package; the hook checks `command -v` first, so it does nothing there | `command -v claude-notify` |
```

- [ ] **Step 11: Verify the hook end to end**

Repeat Step 2 in a **new** `claude` session. Expected: within a few seconds of the prompt appearing, a popup `Claude Code · .dotfiles` shows the permission message, while the sidebar is closed and workspace 1 is shown. Record "Notification hook `claude-notify`".

- [ ] **Step 12: Hand the claude-dotfiles change to the user**

Do not commit in `~/.claude`. Tell the user that `~/.claude` has uncommitted changes (the `Notification` hook with README/SETUP rows, or `preferredNotifChannel: "kitty"`), and that `/dotfiles-release` records, commits and pushes them.

- [ ] **Step 13: Record the result for Task 4**

Write down which branch was taken: `auto`, `kitty`, or the `claude-notify` hook. Task 4, Step 2 picks the matching docs variant.

---

### Task 2: ClaudeAgents service, `agents.sh` and the config key (patch `0001`)

**Files:**
- Create in the clone (`~/src/dots-hyprland/dots/.config/quickshell/ii/`): `scripts/claude/agents.sh`, `services/claude-agents.js`, `services/ClaudeAgents.qml`
- Modify in the clone: `modules/common/Config.qml` (add `sidebar.agents` after `sidebar.ai`, pinned lines 504-506)
- Create: `scripts/ii-agents/test-agents-sh.sh`, `scripts/ii-agents/test-logic.mjs` (this repo)
- Create: `patches/ii/04-agents/0001-*.patch` (generated)
- Modify: `docs/II-INTEGRATION.md` (new ``### Agents (`04-agents`)`` subsection with the `0001` row)

**Interfaces:**
- Consumes: `HyprlandData.windowList` (Hyprland clients with `pid`, `address`, `title`, `focusHistoryID`), `Directories.scriptPath`, `FileUtils.trimFileProtocol`, `Hyprland.dispatch`, `Quickshell.execDetached`.
- Produces, `agents.sh`: prints one JSON array, where each entry is a `claude agents --json` entry, unchanged, plus `ancestors: number[]` and `lastActivity: number|null` (seconds). It exits 127 when `claude` is missing and 2 when the output is not an array.
- Produces, `claude-agents.js` (plain functions, imported as `AgentsLogic`): `stripSpinner(title): string`, `matchWindow(session, windows, nameIsUnique = true): client|null`, `effectiveStatus(session): string`, `annotate(entries, windows): {sessions, headlessCount}`, `classifyResult(exitCode, stdout, stderr, failuresSoFar): {kind: "ok", entries} | {kind: "missing", message} | {kind: "error", message, stop}`, `nextInterval(current, elapsedMs): number`, `subtitle(session, nowMs): string`, `attachCommand(session): string[]`.
- Produces, the `ClaudeAgents` singleton: `sessions: var` (sorted, each with `window`), `available: bool`, `error: string`, `headlessCount: int`, `loaded: bool`, `active: bool` (set by Task 3), `focus(session)`, `statusOf(session): string`, `subtitleOf(session): string`.
- Produces, config: `Config.options.sidebar.agents.enable: bool` (default `true`).

- [ ] **Step 1: Check the clone state**

```bash
cd ~/src/dots-hyprland
git status --short
test "$(git rev-parse krane)" = "$(git rev-parse krane/03-dock)" && echo AT-03-DOCK
git switch krane
```

Expected: `git status` is empty and `AT-03-DOCK` prints. If the clone is gone, recreate it with the "Workflow" loop in `docs/II-INTEGRATION.md` ("Backported fork fixes") and check again.

- [ ] **Step 2: Write the script test**

Create `~/.dotfiles/scripts/ii-agents/test-agents-sh.sh`:

```bash
#!/usr/bin/env bash
# Tests scripts/claude/agents.sh in a dots-hyprland checkout against a fake
# `claude`. Usage: bash test-agents-sh.sh [<ii root>]   (default: the krane clone)
set -euo pipefail
ii=${1:-$HOME/src/dots-hyprland/dots/.config/quickshell/ii}
script="$ii/scripts/claude/agents.sh"
work=$(mktemp -d -p "${XDG_RUNTIME_DIR:-/tmp}")
trap 'rm -rf "$work"' EXIT
fail=0
check() { # name, expected, actual
    if [[ $2 == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: expected [$2], got [$3]"; fail=1; fi
}

mkdir -p "$work/bin" "$work/home/.claude/projects/-home-x-repo"
touch -d @1790000000 "$work/home/.claude/projects/-home-x-repo/s-int.jsonl"
# $$ is this test shell: a live pid whose ancestry ends at init.
command cat > "$work/bin/claude" <<FAKE
#!/usr/bin/env bash
[[ \$1 == agents && \$2 == --json ]] || exit 9
printf '%s' '[{"kind":"interactive","sessionId":"s-int","pid":$$,"name":"a","status":"idle","cwd":"/home/x/repo"},{"kind":"background","sessionId":"s-bg","pid":$$,"id":"ab12cd34","name":"b","state":"working","cwd":"/home/x/other"}]'
FAKE
chmod +x "$work/bin/claude"
# Only the tools agents.sh needs, so a claude installed on the host stays invisible.
mkdir -p "$work/tools"
for t in jq awk stat bash; do ln -s "$(command -v "$t")" "$work/tools/$t"; done
base_path="$work/tools"

out=$(HOME="$work/home" PATH="$work/bin:$base_path" bash "$script")
check "prints an array of both sessions" 2 "$(jq length <<<"$out")"
check "keeps upstream fields" "ab12cd34" "$(jq -r '.[1].id' <<<"$out")"
check "interactive ancestors start at the session pid" "$$" "$(jq -r '.[0].ancestors[0]' <<<"$out")"
check "interactive ancestors stop before init" "false" "$(jq '.[0].ancestors | any(. == 1)' <<<"$out")"
check "interactive ancestors are numbers" "number" "$(jq -r '.[0].ancestors[0] | type' <<<"$out")"
check "background ancestors are empty" "[]" "$(jq -c '.[1].ancestors' <<<"$out")"
check "lastActivity is the transcript mtime" "1790000000" "$(jq '.[0].lastActivity' <<<"$out")"
check "missing transcript gives null" "null" "$(jq '.[1].lastActivity' <<<"$out")"

printf '#!/usr/bin/env bash\necho "[]"\n' > "$work/bin/claude"
check "no sessions prints []" "[]" "$(HOME="$work/home" PATH="$work/bin:$base_path" bash "$script")"

printf '#!/usr/bin/env bash\necho "{}"\n' > "$work/bin/claude"
set +e
HOME="$work/home" PATH="$work/bin:$base_path" bash "$script" >/dev/null 2>&1; rc=$?
set -e
check "non-array output fails" 2 "$rc"

rm "$work/bin/claude"
set +e
err=$(HOME="$work/home" PATH="$work/bin:$base_path" bash "$script" 2>&1 >/dev/null); rc=$?
set -e
check "missing claude exits 127" 127 "$rc"
check "missing claude says so on stderr" "claude not found on PATH" "$err"

exit $fail
```

- [ ] **Step 3: Write the logic test**

Create `~/.dotfiles/scripts/ii-agents/test-logic.mjs`:

```js
// Tests for services/claude-agents.js in a dots-hyprland checkout.
// Usage: node test-logic.mjs [<ii root>]   (default: the krane clone)
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { test } from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";

const iiRoot = process.argv[2] ?? `${homedir()}/src/dots-hyprland/dots/.config/quickshell/ii`;
const ctx = vm.createContext({});
vm.runInContext(readFileSync(`${iiRoot}/services/claude-agents.js`, "utf8"), ctx);
const L = ctx;
const plain = v => JSON.parse(JSON.stringify(v));

const kitty = (pid, address, title, focusHistoryID) => ({ pid, address, title, focusHistoryID });

test("stripSpinner removes the busy and idle prefixes only", () => {
    assert.equal(L.stripSpinner("◑ Ricing ideas"), "Ricing ideas");
    assert.equal(L.stripSpinner("✳ Ricing ideas"), "Ricing ideas");
    assert.equal(L.stripSpinner("Ricing ideas"), "Ricing ideas");
    assert.equal(L.stripSpinner("~/src: fish"), "~/src: fish");
    assert.equal(L.stripSpinner(undefined), "");
});

test("interactive: first ancestor owning a window wins", () => {
    const s = { kind: "interactive", name: "a", ancestors: [3127, 3000, 2840, 900] };
    const w = L.matchWindow(s, [kitty(2840, "0xa", "✳ a", 1), kitty(900, "0xh", "Hyprland", 0)]);
    assert.equal(w.address, "0xa");
});

test("interactive: several windows of one process pick the title match", () => {
    const s = { kind: "interactive", name: "second", ancestors: [5, 4, 2840] };
    const w = L.matchWindow(s, [kitty(2840, "0x1", "✳ first", 0), kitty(2840, "0x2", "◐ second", 3)]);
    assert.equal(w.address, "0x2");
});

test("interactive: no or ambiguous title match falls back to most recently focused", () => {
    const s = { kind: "interactive", name: "zzz", ancestors: [2840] };
    const wins = [kitty(2840, "0x1", "✳ a", 4), kitty(2840, "0x2", "✳ b", 2)];
    assert.equal(L.matchWindow(s, wins).address, "0x2");
});

test("interactive: no window owner means null (headless)", () => {
    const s = { kind: "interactive", name: "obs", ancestors: [77, 1234] };
    assert.equal(L.matchWindow(s, [kitty(2840, "0x1", "✳ obs", 0)]), null);
});

test("background: exactly one title match or null, never ancestry", () => {
    const s = { kind: "background", name: "Ricing ideas", ancestors: [] };
    assert.equal(L.matchWindow(s, [kitty(1, "0x1", "◑ Ricing ideas", 0)]).address, "0x1");
    assert.equal(L.matchWindow(s, [kitty(1, "0x1", "◑ Ricing ideas", 0), kitty(2, "0x2", "✳ Ricing ideas", 1)]), null);
    assert.equal(L.matchWindow(s, []), null);
});

test("background with an empty name never matches an empty title", () => {
    const s = { kind: "background", name: "", ancestors: [] };
    assert.equal(L.matchWindow(s, [kitty(1, "0x1", "", 0)]), null);
});

test("background: two sessions with one name never borrow each other's window", () => {
    const wins = [kitty(1, "0x1", "◑ same-name", 0)];
    const entries = [
        { kind: "background", name: "same-name", id: "aaaa1111", status: "busy", ancestors: [] },
        { kind: "background", name: "same-name", id: "bbbb2222", status: "idle", ancestors: [] },
    ];
    const r = plain(L.annotate(entries, wins));
    assert.deepEqual(r.sessions.map(s => s.window), [null, null]);
    assert.equal(L.matchWindow(entries[0], wins, false), null);
});

test("effectiveStatus maps background state and keeps unknown values raw", () => {
    assert.equal(L.effectiveStatus({ status: "waiting" }), "waiting");
    assert.equal(L.effectiveStatus({ state: "blocked" }), "waiting");
    assert.equal(L.effectiveStatus({ state: "working" }), "busy");
    assert.equal(L.effectiveStatus({ state: "failed" }), "done");
    assert.equal(L.effectiveStatus({ status: "pondering" }), "pondering");
    assert.equal(L.effectiveStatus({}), "unknown");
});

test("annotate drops headless interactive sessions, counts them, and sorts", () => {
    const wins = [kitty(10, "0xa", "✳ idle-one", 0), kitty(20, "0xb", "✳ busy-one", 1), kitty(30, "0xc", "✳ wait-one", 2)];
    const entries = [
        { kind: "interactive", name: "idle-one", status: "idle", ancestors: [11, 10], lastActivity: 300 },
        { kind: "interactive", name: "busy-one", status: "busy", ancestors: [21, 20], lastActivity: 100 },
        { kind: "interactive", name: "wait-one", status: "waiting", waitingFor: "permission prompt", ancestors: [31, 30], lastActivity: 50 },
        { kind: "interactive", name: "observer", status: "busy", ancestors: [99, 1500], lastActivity: 999 },
        { kind: "background", name: "bg-job", state: "working", status: "busy", ancestors: [], startedAt: 50000, lastActivity: null },
    ];
    const r = plain(L.annotate(entries, wins));
    assert.equal(r.headlessCount, 1);
    assert.deepEqual(r.sessions.map(s => s.name), ["wait-one", "busy-one", "bg-job", "idle-one"]);
    assert.equal(r.sessions[3].window.address, "0xa");
    assert.equal(r.sessions[2].window, null);
});

test("classifyResult: 127 is missing, bad JSON is an error that stops on the third", () => {
    assert.equal(L.classifyResult(127, "", "", 0).kind, "missing");
    const ok = L.classifyResult(0, '[{"kind":"background"}]', "", 0);
    assert.equal(ok.kind, "ok");
    assert.equal(ok.entries.length, 1);
    const bad = L.classifyResult(0, "not json", "", 0);
    assert.equal(bad.kind, "error");
    assert.equal(bad.stop, false);
    assert.equal(L.classifyResult(0, "{}", "", 2).stop, true);
    assert.equal(L.classifyResult(1, "", "boom\nmore", 0).message, "boom");
});

test("nextInterval doubles slow runs up to 15 s and resets after a fast one", () => {
    assert.equal(L.nextInterval(3000, 1500), 6000);
    assert.equal(L.nextInterval(12000, 1500), 15000);
    assert.equal(L.nextInterval(15000, 200), 3000);
});

test("subtitle: cwd basename, bg marker, activity or start time", () => {
    const now = 1_000_000_000;
    assert.equal(L.subtitle({ cwd: "/home/krane/.dotfiles", kind: "interactive", lastActivity: (now - 120_000) / 1000 }, now), ".dotfiles · 2 min ago");
    assert.equal(L.subtitle({ cwd: "/home/krane/src/x/", kind: "background", lastActivity: null, startedAt: now - 7_200_000 }, now), "x · bg · started 2 h ago");
});

test("attachCommand opens a new kitty on the short id", () => {
    assert.deepEqual(plain(L.attachCommand({ id: "cd9c41f1" })), ["kitty", "-e", "claude", "attach", "cd9c41f1"]);
});
```

- [ ] **Step 4: Run both tests to see them fail**

```bash
bash ~/.dotfiles/scripts/ii-agents/test-agents-sh.sh; echo "rc=$?"
node ~/.dotfiles/scripts/ii-agents/test-logic.mjs; echo "rc=$?"
```

Expected: the first prints `bash: …/scripts/claude/agents.sh: No such file or directory` and no `ok` line, `rc=127` (the test runs under `set -e`); the second fails with `ENOENT … services/claude-agents.js`, `rc=1`.

- [ ] **Step 5: Create `scripts/claude/agents.sh` in the clone**

```bash
cd ~/src/dots-hyprland/dots/.config/quickshell/ii
mkdir -p scripts/claude
command cat > scripts/claude/agents.sh <<'EOF'
#!/usr/bin/env bash
# Prints `claude agents --json` as one JSON array, each entry unchanged plus:
#   ancestors     interactive sessions: pid chain from the session up to,
#                 not including, init; [] for background sessions, whose
#                 ancestry leads to the daemon supervisor, not a terminal
#   lastActivity  transcript mtime in seconds, or null
# Reads no transcript content. Exits 127 when claude is not on PATH.
set -euo pipefail

command -v claude >/dev/null 2>&1 || { echo "claude not found on PATH" >&2; exit 127; }

raw=$(claude agents --json)
jq -e 'type == "array"' >/dev/null <<<"$raw" || { echo "claude agents --json did not print an array" >&2; exit 2; }

jq -r '.[] | "\(.sessionId // "-") \(.kind // "-") \(.pid // 0)"' <<<"$raw" |
    while read -r sid kind pid; do
        chain=()
        if [[ $kind == interactive ]]; then
            p=$pid
            while [[ -n $p && $p != 0 && $p != 1 && ${#chain[@]} -lt 64 ]]; do
                chain+=("$p")
                p=$(awk '/^PPid:/{print $2}' "/proc/$p/status" 2>/dev/null || true)
            done
        fi
        mtime=null
        if [[ $sid != - ]]; then
            for f in "$HOME"/.claude/projects/*/"$sid".jsonl; do
                if [[ -e $f ]]; then
                    mtime=$(stat -c %Y "$f")
                    break
                fi
            done
        fi
        printf '{"ancestors":[%s],"lastActivity":%s}\n' "$(IFS=,; echo "${chain[*]}")" "$mtime"
    done |
    jq -c -s --argjson raw "$raw" '[$raw, .] | transpose | map(.[0] + .[1])'
EOF
chmod +x scripts/claude/agents.sh
```

- [ ] **Step 6: Create `services/claude-agents.js` in the clone**

```bash
cd ~/src/dots-hyprland/dots/.config/quickshell/ii
command cat > services/claude-agents.js <<'EOF'
// Pure helpers for services/ClaudeAgents.qml, kept free of QML types so
// they can be tested with plain node (see the dotfiles repo's
// scripts/ii-agents/test-logic.mjs).

const BASE_INTERVAL = 3000;
const MAX_INTERVAL = 15000;
const SLOW_RUN_MS = 1000;
const MAX_FAILURES = 3;

// Claude Code sets the terminal title to "<spinner> <session name>":
// ◐ ◑ ◒ ◓ while busy, ✳ otherwise. Braille frames are covered too.
function stripSpinner(title) {
    return String(title ?? "").replace(/^[◐-◓✳⠀-⣿]\s+/, "");
}

function titleMatches(win, name) {
    return !!name && stripSpinner(win.title) === name;
}

function mostRecentlyFocused(wins) {
    return wins.slice().sort((a, b) => (a.focusHistoryID ?? 1e9) - (b.focusHistoryID ?? 1e9))[0] ?? null;
}

// Returns the Hyprland client for a session, or null. nameIsUnique is false
// when another listed session has the same name: a background session then
// never matches by title, so it cannot land in the other session's window.
function matchWindow(session, windows, nameIsUnique = true) {
    const wins = windows ?? [];
    if (session?.kind === "interactive") {
        for (const pid of session.ancestors ?? []) {
            const owned = wins.filter(w => w.pid === pid);
            if (owned.length === 0) continue;
            if (owned.length === 1) return owned[0];
            const titled = owned.filter(w => titleMatches(w, session.name));
            if (titled.length === 1) return titled[0];
            return mostRecentlyFocused(titled.length > 1 ? titled : owned);
        }
        return null;
    }
    if (!nameIsUnique) return null;
    const titled = wins.filter(w => titleMatches(w, session?.name));
    return titled.length === 1 ? titled[0] : null;
}

// "waiting" | "busy" | "idle" | "done" | <raw unknown value> | "unknown"
function effectiveStatus(session) {
    if (session?.status) return session.status;
    switch (session?.state) {
    case "blocked": return "waiting";
    case "working": return "busy";
    case "done": case "failed": case "stopped": return "done";
    default: return session?.state ?? "unknown";
    }
}

function activityMs(session) {
    if (typeof session?.lastActivity === "number") return session.lastActivity * 1000;
    return typeof session?.startedAt === "number" ? session.startedAt : 0;
}

function rank(session) {
    const s = effectiveStatus(session);
    return s === "waiting" ? 0 : s === "busy" ? 1 : 2;
}

// entries: parsed agents.sh output. Returns { sessions, headlessCount }.
function annotate(entries, windows) {
    let headlessCount = 0;
    const sessions = [];
    const nameCounts = {};
    for (const e of entries ?? []) nameCounts[e.name] = (nameCounts[e.name] ?? 0) + 1;
    for (const e of entries ?? []) {
        const s = Object.assign({}, e, { window: matchWindow(e, windows, nameCounts[e.name] === 1) });
        if (s.kind === "interactive" && !s.window) {
            headlessCount++;
            continue;
        }
        sessions.push(s);
    }
    sessions.sort((a, b) => rank(a) - rank(b) || activityMs(b) - activityMs(a));
    return { sessions: sessions, headlessCount: headlessCount };
}

// Returns { kind: "ok", entries } | { kind: "missing", message }
//       | { kind: "error", message, stop }.
function classifyResult(exitCode, stdout, stderr, failuresSoFar) {
    if (exitCode === 127) return { kind: "missing", message: "Claude Code not found" };
    let entries = null;
    if (exitCode === 0) {
        try {
            entries = JSON.parse(stdout);
        } catch (e) {
            entries = null;
        }
    }
    if (Array.isArray(entries)) return { kind: "ok", entries: entries };
    const firstLine = String(stderr ?? "").trim().split("\n")[0];
    const message = firstLine || (exitCode === 0 ? "Invalid output from claude agents --json" : `agents.sh exited with ${exitCode}`);
    return { kind: "error", message: message, stop: failuresSoFar + 1 >= MAX_FAILURES };
}

function nextInterval(current, elapsedMs) {
    if (elapsedMs > SLOW_RUN_MS) return Math.min(current * 2, MAX_INTERVAL);
    return BASE_INTERVAL;
}

function basename(path) {
    const parts = String(path ?? "").split("/").filter(p => p.length > 0);
    return parts.length ? parts[parts.length - 1] : "/";
}

function relativeTime(ms, nowMs) {
    const sec = Math.max(0, Math.floor((nowMs - ms) / 1000));
    if (sec < 60) return "just now";
    if (sec < 3600) return `${Math.floor(sec / 60)} min ago`;
    if (sec < 86400) return `${Math.floor(sec / 3600)} h ago`;
    return `${Math.floor(sec / 86400)} d ago`;
}

function subtitle(session, nowMs) {
    const parts = [basename(session?.cwd)];
    if (session?.kind === "background") parts.push("bg");
    if (typeof session?.lastActivity === "number") parts.push(relativeTime(session.lastActivity * 1000, nowMs));
    else if (typeof session?.startedAt === "number") parts.push(`started ${relativeTime(session.startedAt, nowMs)}`);
    return parts.join(" · ");
}

function attachCommand(session) {
    return ["kitty", "-e", "claude", "attach", String(session.id)];
}
EOF
```

- [ ] **Step 7: Run both tests to see them pass**

```bash
bash ~/.dotfiles/scripts/ii-agents/test-agents-sh.sh; echo "rc=$?"
node ~/.dotfiles/scripts/ii-agents/test-logic.mjs 2>&1 | grep -E '^# (pass|fail)'
```

Expected: 12 `ok` lines, `rc=0`; `# pass 14`, `# fail 0`.

- [ ] **Step 8: Smoke-test `agents.sh` against the real `claude`**

```bash
bash ~/src/dots-hyprland/dots/.config/quickshell/ii/scripts/claude/agents.sh | jq -c '.[] | {kind, status, state, name, n: (.ancestors | length), lastActivity}'
```

Expected: one line per live session (including this one). Interactive sessions in a terminal have `n` > 2; headless SDK sessions (claude-mem observer, often named like `43-6b`) may have `n` ≤ 2 and `lastActivity` null. Background sessions have `n` = 0, and `lastActivity` for this session is within a few minutes of `date +%s`. (Checked 2026-09-27 against 2.1.280: output had this shape.)

- [ ] **Step 9: Create `services/ClaudeAgents.qml` in the clone**

```bash
cd ~/src/dots-hyprland/dots/.config/quickshell/ii
command cat > services/ClaudeAgents.qml <<'EOF'
pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "claude-agents.js" as AgentsLogic

/**
 * Claude Code sessions on this machine, read from `claude agents --json`
 * through scripts/claude/agents.sh. Polls only while `active` is true, which
 * the left sidebar sets while its Agents tab is visible. Read-only: it never
 * sends input to, approves, stops or deletes a session.
 */
Singleton {
    id: root

    property var sessions: []
    property bool available: true
    property string error: ""
    property int headlessCount: 0
    property bool loaded: false

    property bool active: false
    property bool stopped: false
    property int failures: 0
    property int pollInterval: 3000
    property var lastEntries: []

    readonly property string scriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/claude/agents.sh`)

    onActiveChanged: {
        if (root.active) {
            root.stopped = false;
            root.failures = 0;
        }
    }

    function applyWindows() {
        const result = AgentsLogic.annotate(root.lastEntries, HyprlandData.windowList);
        root.sessions = result.sessions;
        root.headlessCount = result.headlessCount;
    }

    function handleResult(exitCode, stdout, stderr, elapsedMs) {
        const result = AgentsLogic.classifyResult(exitCode, stdout, stderr, root.failures);
        if (result.kind === "ok") {
            root.available = true;
            root.error = "";
            root.failures = 0;
            root.loaded = true;
            root.lastEntries = result.entries;
            root.applyWindows();
        } else if (result.kind === "missing") {
            root.available = false;
            root.error = result.message;
            root.stopped = true;
        } else {
            // The script ran, so claude is on PATH; keep the last list visible.
            root.available = true;
            root.failures += 1;
            root.error = result.message;
            if (result.stop) root.stopped = true;
        }
        root.pollInterval = AgentsLogic.nextInterval(root.pollInterval, elapsedMs);
    }

    function focus(session) {
        if (session?.window?.address) {
            Hyprland.dispatch(`hl.dsp.focus({window = "address:${session.window.address}"})`);
        } else if (session?.kind === "background" && session?.id) {
            Quickshell.execDetached(AgentsLogic.attachCommand(session));
        }
    }

    function statusOf(session) {
        return AgentsLogic.effectiveStatus(session);
    }

    function subtitleOf(session) {
        return AgentsLogic.subtitle(session, Date.now());
    }

    // Window titles change with the session spinner; re-match without re-running the script.
    // Only while visible: a closed tab does no work, and the first tick on reopen re-matches.
    Connections {
        target: HyprlandData
        function onWindowListChanged() {
            if (root.loaded && root.active) root.applyWindows();
        }
    }

    Timer {
        id: pollTimer
        interval: root.pollInterval
        repeat: true
        running: root.active && !root.stopped
        triggeredOnStart: true
        onTriggered: {
            if (agentsProc.running) return;
            agentsProc.pendingParts = 2;
            agentsProc.startedAt = Date.now();
            agentsProc.running = true;
        }
    }

    Process {
        id: agentsProc
        // stdout closing and the exit can arrive in either order; handle the run once both are in.
        // stderr is only used for the error line, so it is read as far as it has arrived.
        property int pendingParts: 0
        property int exitCode: 0
        property real startedAt: 0
        function partDone() {
            agentsProc.pendingParts -= 1;
            if (agentsProc.pendingParts === 0)
                root.handleResult(agentsProc.exitCode, agentsOut.text, agentsErr.text, Date.now() - agentsProc.startedAt);
        }
        command: ["bash", root.scriptPath]
        stdout: StdioCollector {
            id: agentsOut
            onStreamFinished: agentsProc.partDone()
        }
        stderr: StdioCollector {
            id: agentsErr
        }
        onExited: (exitCode, exitStatus) => {
            agentsProc.exitCode = exitCode;
            agentsProc.partDone();
        }
    }
}
EOF
```

- [ ] **Step 10: Add the config key**

```bash
cd ~/src/dots-hyprland
git apply --ignore-whitespace <<'EOF'
--- a/dots/.config/quickshell/ii/modules/common/Config.qml
+++ b/dots/.config/quickshell/ii/modules/common/Config.qml
@@ -504,6 +504,9 @@ Singleton {
                 property JsonObject ai: JsonObject {
                     property bool textFadeIn: false
                 }
+                property JsonObject agents: JsonObject {
+                    property bool enable: true
+                }
                 property JsonObject booru: JsonObject {
                     property bool allowNsfw: false
                     property string defaultProvider: "yandere"
EOF
grep -n -A2 'property JsonObject agents' dots/.config/quickshell/ii/modules/common/Config.qml
```

Expected: one match followed by `property bool enable: true`. (`03-dock` adds keys to the `dock` object above, shifting this hunk by a few lines; `git apply` finds the context at the offset, which only `git apply -v` reports. Checked on the pin, and with a simulated 4-line `dock` insert and the `02-translator` flip: applies cleanly.)

- [ ] **Step 11: Syntax-check the QML**

```bash
qmllint ~/src/dots-hyprland/dots/.config/quickshell/ii/services/ClaudeAgents.qml 2>&1 | grep -iE 'syntax|expected|unexpected'
```

Expected: no output. qmllint cannot resolve the `qs.*` imports outside Quickshell, so only parse errors count here. Import and type warnings are expected.

- [ ] **Step 12: Commit in the clone**

```bash
cd ~/src/dots-hyprland
git add -A
git commit -F - <<'EOF'
ii: add ClaudeAgents service and agents.sh

Problem: nothing in the shell shows which Claude Code sessions run, which are busy, or which wait on a permission prompt.
Port: new (no fork origin). services/ClaudeAgents.qml polls scripts/claude/agents.sh (claude agents --json plus pid ancestry and transcript mtime) only while active; services/claude-agents.js holds the testable matching and sorting; sidebar.agents.enable defaults to true.
Drop when: the pinned ii ships an equivalent agents tab, or `claude agents --json` is removed.
EOF
```

Expected: 4 files changed (3 new, `Config.qml` +3).

- [ ] **Step 13: Confirm it is not in the build yet (failing check)**

Run the "Checking the built source" block, then:

```bash
test -e "$iisrc/dots/.config/quickshell/ii/services/ClaudeAgents.qml" && echo PRESENT || echo ABSENT
```

Expected: `ABSENT`.

- [ ] **Step 14: Export**

```bash
git -C ~/src/dots-hyprland tag -f krane/04-agents krane
mkdir -p ~/.dotfiles/patches/ii/04-agents
rm -f ~/.dotfiles/patches/ii/04-agents/*.patch && git -C ~/src/dots-hyprland format-patch --zero-commit --no-signature --no-numbered -o ~/.dotfiles/patches/ii/04-agents krane/03-dock..krane/04-agents
```

Expected: prints `.../patches/ii/04-agents/0001-ii-add-ClaudeAgents-service-and-agents.sh.patch`. Check that `grep -c '^new file mode 100755' ~/.dotfiles/patches/ii/04-agents/0001-*.patch` prints `1`.

- [ ] **Step 15: Confirm it is in the build and the tests pass against it (passing check)**

```bash
cd ~/.dotfiles && git add patches/ii/04-agents scripts/ii-agents
```

Run the "Checking the built source" block, then:

```bash
ii="$iisrc/dots/.config/quickshell/ii"
for f in services/ClaudeAgents.qml services/claude-agents.js scripts/claude/agents.sh modules/common/Config.qml; do
  diff -q "$ii/$f" ~/src/dots-hyprland/dots/.config/quickshell/ii/$f && echo "SAME $f"
done
bash ~/.dotfiles/scripts/ii-agents/test-agents-sh.sh "$ii" | grep -c '^ok'
node ~/.dotfiles/scripts/ii-agents/test-logic.mjs "$ii" 2>&1 | grep -E '^# fail'
```

Expected: `SAME` four times, `12`, `# fail 0`. If the node test cannot read `$ii/services/claude-agents.js` because it is missing, the loader did not apply the new directory. Check that `patches/ii/04-agents` is `git add`ed.

- [ ] **Step 16: Add the docs table row**

In `docs/II-INTEGRATION.md`, insert this subsection immediately before the `### Workflow` heading under `## Backported fork fixes` (after ``### Dock (`03-dock`)``, matching the ``### Translator (`02-translator`)`` naming):

````markdown
### Agents (`04-agents`)

New work, not from the fork: a left-sidebar Agents tab that lists Claude Code
sessions (spec: `docs/superpowers/specs/2026-09-27-ii-agent-overview-design.md`;
usage under "Claude Code" below).

| Patch | Adds | Drop when |
|---|---|---|
| `0001` ClaudeAgents service | `services/ClaudeAgents.qml`, `services/claude-agents.js`, `scripts/claude/agents.sh`, config `sidebar.agents.enable` (default `true`) | pinned ii ships an equivalent agents tab, or `claude agents --json` is removed |

Tests, runnable against the clone (default) or a built source:

```sh
bash scripts/ii-agents/test-agents-sh.sh [<ii root>]
node scripts/ii-agents/test-logic.mjs [<ii root>]
```

`<ii root>` is `…/dots/.config/quickshell/ii`, for example inside the
`dots-hyprland-patched` store path.
````

- [ ] **Step 17: Dry-build all hosts**

```bash
cd ~/.dotfiles
for h in tariognatha tarmantria taractias; do nixos-rebuild dry-build --flake .#$h || echo "FAIL $h"; done
```

Expected: no `FAIL` lines.

- [ ] **Step 18: Commit**

```bash
cd ~/.dotfiles
git add patches/ii/04-agents scripts/ii-agents docs/II-INTEGRATION.md
git commit -m "Add a ClaudeAgents service patch for ii that reads claude agents --json, with tests"
```

---

### Task 3: Agents tab in the left sidebar (patch `0002`)

**Files:**
- Create in the clone: `modules/ii/sidebarLeft/Agents.qml`, `modules/ii/sidebarLeft/agents/AgentRow.qml`
- Modify in the clone: `modules/ii/sidebarLeft/SidebarLeftContent.qml` (pinned lines 1, 15-24, 86-90, 95-102)
- Create: `patches/ii/04-agents/0002-*.patch` (generated)
- Modify: `docs/II-INTEGRATION.md` (`0002` row)

**Interfaces:**
- Consumes: `ClaudeAgents.sessions`, `.available`, `.loaded`, `.error`, `.headlessCount`, `.active`, `.focus(session)`, `.statusOf(session)`, `.subtitleOf(session)` (Task 2); `Config.options.sidebar.agents.enable` (Task 2); `GlobalStates.sidebarLeftOpen`; `SidebarLeftContent.scopeRoot.detach` (pinned `SidebarLeft.qml:13`).
- Produces: `Agents` (Item, `objectName: "claudeAgentsTab"`, `property bool detached`); `AgentRow` (RippleButton, `property var session`).

- [ ] **Step 1: Show the tab is absent (failing check)**

```bash
grep -c 'Agents' ~/src/dots-hyprland/dots/.config/quickshell/ii/modules/ii/sidebarLeft/SidebarLeftContent.qml
```

Expected: `0`.

- [ ] **Step 2: Create `AgentRow.qml`**

```bash
cd ~/src/dots-hyprland/dots/.config/quickshell/ii/modules/ii/sidebarLeft
mkdir -p agents
command cat > agents/AgentRow.qml <<'EOF'
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One Claude Code session: status dot, name, "<cwd> · bg · <activity>", and
 * whether a click focuses a window (open_in_new) or opens a terminal (terminal).
 */
RippleButton {
    id: root
    property var session
    readonly property string status: ClaudeAgents.statusOf(root.session)
    readonly property bool knownStatus: ["waiting", "busy", "idle", "done"].includes(root.status)

    horizontalPadding: 12
    verticalPadding: 8
    buttonRadius: Appearance.rounding.small

    contentItem: RowLayout {
        spacing: 10

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 10
            implicitHeight: 10
            radius: 5
            color: root.status === "waiting" ? Appearance.colors.colError
                : root.status === "busy" ? Appearance.colors.colPrimary
                : Appearance.colors.colOutlineVariant

            SequentialAnimation on opacity {
                running: root.status === "busy"
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.3; duration: 900; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutQuad }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer1
                text: root.session?.name || Translation.tr("Unnamed session")
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.status === "waiting" ? Appearance.colors.colError : Appearance.colors.colSubtext
                text: {
                    const sub = ClaudeAgents.subtitleOf(root.session);
                    if (root.status === "waiting")
                        return `${root.session?.waitingFor ?? Translation.tr("needs you")} · ${sub}`;
                    if (!root.knownStatus)
                        return `${root.status} · ${sub}`;
                    return sub;
                }
            }
        }

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: root.session?.window ? "open_in_new" : "terminal"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colSubtext
        }
    }
}
EOF
```

- [ ] **Step 3: Create `Agents.qml`**

```bash
cd ~/src/dots-hyprland/dots/.config/quickshell/ii/modules/ii/sidebarLeft
command cat > Agents.qml <<'EOF'
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarLeft.agents
import QtQuick
import QtQuick.Layouts

/**
 * Claude Code sessions from services/ClaudeAgents.qml. A click focuses the
 * session's terminal, or attaches a background session in a new terminal.
 * SidebarLeftContent.qml turns polling on while this tab is visible.
 */
Item {
    id: root
    objectName: "claudeAgentsTab"
    property bool detached: false
    readonly property int needYouCount: ClaudeAgents.sessions.filter(s => ClaudeAgents.statusOf(s) === "waiting").length

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        StyledText {
            Layout.fillWidth: true
            visible: ClaudeAgents.available && ClaudeAgents.loaded
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            elide: Text.ElideRight
            text: {
                let t = Translation.tr("%1 sessions · %2 need you").arg(ClaudeAgents.sessions.length).arg(root.needYouCount);
                if (ClaudeAgents.headlessCount > 0)
                    t += " · " + Translation.tr("%1 headless hidden").arg(ClaudeAgents.headlessCount);
                return t;
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: ClaudeAgents.available && ClaudeAgents.error.length > 0
            color: Appearance.colors.colError
            font.pixelSize: Appearance.font.pixelSize.smaller
            wrapMode: Text.Wrap
            text: ClaudeAgents.error
        }

        StyledListView {
            id: sessionList
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4
            clip: true
            popin: false
            animateAppearance: false
            model: ClaudeAgents.sessions
            delegate: AgentRow {
                required property var modelData
                width: sessionList.width
                session: modelData
                onClicked: {
                    ClaudeAgents.focus(modelData);
                    if (!root.detached)
                        GlobalStates.sidebarLeftOpen = false;
                }
            }
        }
    }

    PagePlaceholder {
        shown: !ClaudeAgents.available || (ClaudeAgents.loaded && ClaudeAgents.sessions.length === 0)
        icon: "smart_toy"
        title: ClaudeAgents.available ? Translation.tr("No Claude Code sessions") : Translation.tr("Claude Code not found")
        description: ClaudeAgents.available ? Translation.tr("Sessions started in a terminal or with claude --bg show up here") : Translation.tr("claude is not on the shell's PATH")
    }
}
EOF
```

- [ ] **Step 4: Wire the tab into `SidebarLeftContent.qml`**

```bash
cd ~/src/dots-hyprland
git apply --ignore-whitespace <<'EOF'
--- a/dots/.config/quickshell/ii/modules/ii/sidebarLeft/SidebarLeftContent.qml
+++ b/dots/.config/quickshell/ii/modules/ii/sidebarLeft/SidebarLeftContent.qml
@@ -1,3 +1,4 @@
+import qs
 import qs.services
 import qs.modules.common
 import qs.modules.common.widgets
@@ -13,16 +14,27 @@ Item {
     property int sidebarPadding: 10
     anchors.fill: parent
     property bool aiChatEnabled: Config.options.policies.ai !== 0
+    property bool agentsEnabled: Config.options.sidebar.agents.enable
     property bool translatorEnabled: Config.options.sidebar.translator.enable
     property bool animeEnabled: Config.options.policies.weeb !== 0
     property bool animeCloset: Config.options.policies.weeb === 2
     property var tabButtonList: [
         ...(root.aiChatEnabled ? [{"icon": "neurology", "name": Translation.tr("Intelligence")}] : []),
+        ...(root.agentsEnabled ? [{"icon": "smart_toy", "name": Translation.tr("Agents")}] : []),
         ...(root.translatorEnabled ? [{"icon": "translate", "name": Translation.tr("Translator")}] : []),
         ...((root.animeEnabled && !root.animeCloset) ? [{"icon": "bookmark_heart", "name": Translation.tr("Anime")}] : [])
     ]
     property int tabCount: swipeView.count
 
+    // services/ClaudeAgents.qml polls `claude agents --json` only while this is true.
+    Binding {
+        target: ClaudeAgents
+        property: "active"
+        value: root.agentsEnabled
+            && GlobalStates.sidebarLeftOpen
+            && swipeView.currentItem?.objectName === "claudeAgentsTab"
+    }
+
     function focusActiveItem() {
         swipeView.currentItem.forceActiveFocus()
     }
@@ -85,8 +97,9 @@ Item {
 
                 contentChildren: [
                     ...(root.aiChatEnabled ? [aiChat.createObject()] : []),
+                    ...(root.agentsEnabled ? [agents.createObject()] : []),
                     ...(root.translatorEnabled ? [translator.createObject()] : []),
-                    ...((root.tabButtonList.length === 0 || (!root.aiChatEnabled && !root.translatorEnabled && root.animeCloset)) ? [placeholder.createObject()] : []),
+                    ...((root.tabButtonList.length === 0 || (!root.aiChatEnabled && !root.agentsEnabled && !root.translatorEnabled && root.animeCloset)) ? [placeholder.createObject()] : []),
                     ...(root.animeEnabled ? [anime.createObject()] : []),
                 ]
             }
@@ -96,6 +109,12 @@ Item {
             id: aiChat
             AiChat {}
         }
+        Component {
+            id: agents
+            Agents {
+                detached: root.scopeRoot?.detach ?? false
+            }
+        }
         Component {
             id: translator
             Translator {}
EOF
git diff --stat
```

Expected: `SidebarLeftContent.qml | 21 ++++++++++++++++++++-` (20 insertions, 1 deletion). If `git apply` rejects a hunk, an earlier sub-project changed this file after all. Stop and report, and do not force it.

- [ ] **Step 5: Confirm the tab list and pages stay parallel (passing check)**

```bash
f=~/src/dots-hyprland/dots/.config/quickshell/ii/modules/ii/sidebarLeft/SidebarLeftContent.qml
grep -n 'agentsEnabled\|claudeAgentsTab\|id: agents' "$f"
for q in modules/ii/sidebarLeft/SidebarLeftContent.qml modules/ii/sidebarLeft/Agents.qml modules/ii/sidebarLeft/agents/AgentRow.qml; do
  qmllint ~/src/dots-hyprland/dots/.config/quickshell/ii/$q 2>&1 | grep -iE 'syntax|expected|unexpected'
done
```

Expected: `agentsEnabled` appears in the property, the tab entry, the Binding, the page entry and the placeholder condition; `claudeAgentsTab` once; `id: agents` once. qmllint prints no parse errors.

- [ ] **Step 6: Commit in the clone**

```bash
cd ~/src/dots-hyprland
git add -A
git commit -F - <<'EOF'
ii: add Agents tab to the left sidebar

Problem: a Claude Code session blocked on a permission prompt in a window on another workspace goes unnoticed, and there is no single place to see or jump to all sessions.
Port: new (no fork origin). Agents.qml and agents/AgentRow.qml list ClaudeAgents.sessions; a click focuses the session's window or runs kitty -e claude attach <id>. SidebarLeftContent.qml adds the tab after Intelligence and turns polling on only while the tab is visible.
Drop when: the pinned ii ships an equivalent agents tab, or `claude agents --json` is removed.
EOF
```

- [ ] **Step 7: Export**

```bash
git -C ~/src/dots-hyprland tag -f krane/04-agents krane
rm -f ~/.dotfiles/patches/ii/04-agents/*.patch && git -C ~/src/dots-hyprland format-patch --zero-commit --no-signature --no-numbered -o ~/.dotfiles/patches/ii/04-agents krane/03-dock..krane/04-agents
cd ~/.dotfiles && git status --short patches/ii/04-agents
```

Expected: one new file. `0002-ii-add-Agents-tab-to-the-left-sidebar.patch` is new (`??`); `0001-*` is unchanged, since `--no-numbered` keeps its `Subject: [PATCH] …` line the same regardless of series length.

- [ ] **Step 8: Confirm it is in the build (passing check)**

```bash
cd ~/.dotfiles && git add patches/ii/04-agents
```

Run the "Checking the built source" block, then:

```bash
for f in modules/ii/sidebarLeft/SidebarLeftContent.qml modules/ii/sidebarLeft/Agents.qml modules/ii/sidebarLeft/agents/AgentRow.qml; do
  diff -q "$iisrc/dots/.config/quickshell/ii/$f" ~/src/dots-hyprland/dots/.config/quickshell/ii/$f && echo "SAME $f"
done
```

Expected: `SAME` three times.

- [ ] **Step 9: Add the docs table row**

In `docs/II-INTEGRATION.md`, in the ``### Agents (`04-agents`)`` table, add below the `0001` row:

```markdown
| `0002` Agents tab | `modules/ii/sidebarLeft/Agents.qml`, `agents/AgentRow.qml`, tab and polling switch in `SidebarLeftContent.qml` | same as `0001` |
```

- [ ] **Step 10: Dry-build all hosts and commit**

```bash
cd ~/.dotfiles
for h in tariognatha tarmantria taractias; do nixos-rebuild dry-build --flake .#$h || echo "FAIL $h"; done
git add patches/ii/04-agents docs/II-INTEGRATION.md
git commit -m "Add an Agents tab to ii's left sidebar that lists Claude Code sessions"
```

Expected: no `FAIL` lines, one commit.

---

### Task 4: Documentation for Claude Code and the sidebar

**Files:**
- Modify: `docs/II-INTEGRATION.md` (new `## Claude Code` section, inserted immediately before `## Verifying on the target`)

- [ ] **Step 1: Confirm the anchor exists**

```bash
grep -n '^## Verifying on the target\|^## Claude Code' ~/.dotfiles/docs/II-INTEGRATION.md
```

Expected: one `## Verifying on the target` line and no `## Claude Code` line.

- [ ] **Step 2: Insert the section**

Insert the following before `## Verifying on the target`. For "Desktop notifications for blocked sessions", use variant A if Task 1 added the hook, or variant B otherwise (fill in `auto` or `kitty` from Task 1, Step 13). Include only one variant.

````markdown
## Claude Code

### Agents tab

The left sidebar's Agents tab (`patches/ii/04-agents`) lists every Claude
Code session on the machine that has a window or runs in the background:
name, project (cwd basename), `bg` for background sessions, last activity,
and a dot for the state (error colour and the `waitingFor` reason while a
session waits on you, a pulsing primary colour while busy). Clicking a row
focuses the session's terminal window on any workspace. For a background
session that no terminal is attached to, it runs `kitty -e claude attach
<id>`. The tab never answers, approves, stops or deletes anything.

It runs `scripts/claude/agents.sh` (`claude agents --json`, plus the pid
chain up to the terminal and the transcript's mtime; transcript content is
never read) every 3 s, backing off to 15 s when a run is slow. It runs only
while the tab is visible, so a closed sidebar starts no `claude` process.
Sessions whose process has no terminal window (SDK sessions such as the
claude-mem observer, tmux, SSH, TTYs) are hidden and counted as
"headless hidden".

To turn the tab off, add `"sidebar": {"agents": {"enable": false}}` to
`~/.config/illogical-impulse/config.json` (ii-owned, not written by Nix).

`claude agents --json` belongs to agent view, a research preview. After
every `just update-claude`, check its fields:

```sh
claude agents --json | jq -c '[.[] | keys] | add | unique'
```

Expected: `cwd`, `id`, `kind`, `name`, `pid`, `sessionId`, `startedAt`,
`state`, `status` (plus `waitingFor` while a session waits; `id` and
`state` appear only while a background session exists). A rename shows
up here before the tab breaks; the tab then shows the raw value or an error
line instead of failing silently.

### Desktop notifications for blocked sessions

<!-- Variant A: Task 1 added the hook -->
The Agents tab only refreshes while open, so it cannot tell you that a
session is blocked. That is the `Notification` hook's job: `claude-notify`
(`pkgs/claude-notify`, installed by `modules/home/dev.nix`) turns
permission prompts, idle prompts and dialogs into a desktop notification
titled `Claude Code · <project>`. It never blocks and always exits 0. The
hook entry is not in this repo: it lives in `~/.claude/settings.json`, which
belongs to the claude-dotfiles repo checked out at `~/.claude` (see its
README "Hooks" table) and ships with that repo's `/dotfiles-release`:

```json
"Notification": [
  {
    "matcher": "permission_prompt|idle_prompt|elicitation_dialog",
    "hooks": [{ "type": "command", "command": "command -v claude-notify >/dev/null && claude-notify || true" }]
  }
]
```

<!-- Variant B: no hook needed -->
The Agents tab only refreshes while open, so it cannot tell you that a
session is blocked. Claude Code's own terminal notifications do that
(checked 2026-09-27 with `preferredNotifChannel` set to `<auto|kitty>` in
`~/.claude/settings.json`, the claude-dotfiles repo): a permission prompt in
a kitty window on another workspace produces an ii notification popup. If it
stops working, add a `Notification` hook that calls `notify-send`; see
step 0 of `docs/superpowers/specs/2026-09-27-ii-agent-overview-design.md`.

### Claude in the sidebar chat

Optional and billed per token through an Anthropic API key. The Claude Code
subscription cannot be used here: routing the teamclaude proxy or Claude
Code's OAuth credentials into ii's requests falls outside Anthropic's terms.
Anthropic describes its OpenAI-compatible endpoint as meant for testing and
comparison, not long-term use.

Add to `ai.extraModels` in `~/.config/illogical-impulse/config.json`:

```json
{
  "api_format": "openai",
  "name": "Claude Sonnet 5",
  "description": "Anthropic API, billed per token",
  "endpoint": "https://api.anthropic.com/v1/chat/completions",
  "model": "claude-sonnet-5",
  "key_id": "anthropic",
  "key_get_link": "https://platform.claude.com/settings/keys",
  "requires_key": true,
  "extraParams": { "tools": [], "max_tokens": 4096 }
}
```

Then pick it with `/model` in the Intelligence tab and store the key with
`/key <key>` (ii keeps it in the keyring, never in this repo). `"tools": []`
is required: ii's `openai` strategy does not parse tool calls, so a reply
that calls one of ii's tools would arrive empty. Opus 5.5 works the same
with `"model": "claude-opus-5-5"`.
````

After pasting, delete the two HTML comment lines and the variant you did not use.

- [ ] **Step 3: Check the result**

```bash
grep -n '^## Claude Code\|^### Agents tab\|^### Desktop notifications\|^### Claude in the sidebar chat\|Variant' ~/.dotfiles/docs/II-INTEGRATION.md
```

Expected: the four headings once each, in that order, and no `Variant` line.

- [ ] **Step 4: Commit**

```bash
cd ~/.dotfiles
git add docs/II-INTEGRATION.md
git commit -m "Document the ii Agents tab, Claude Code desktop notifications and the optional Claude chat model"
```

---

### Task 5: Switch and acceptance checks

These are the spec's manual checks, plus the Review Focus checks. Record each one as pass, fail, or not run (with the reason) in the task report. A failure means fixing the owning commit in the clone and exporting again, not patching around it here. The one planned fix is the Step 12 gate.

**Files:** none, unless Step 12 applies the gate (then `scripts/claude/agents.sh` in the clone, `scripts/ii-agents/test-agents-sh.sh`, `patches/ii/04-agents/0001-*.patch`).

- [ ] **Step 1: Switch the current host and restart qs**

```bash
qs log -c ii > $XDG_RUNTIME_DIR/qs-before.log 2>&1 || true
cd ~/.dotfiles && sudo nixos-rebuild switch --flake .#$(hostname)
pkill -f '[q]s-wrapped -c ii'; hyprctl dispatch exec 'qs -c ii'
sleep 5; qs log -c ii > $XDG_RUNTIME_DIR/qs-after.log 2>&1 || true
grep -iE 'error|warn|TypeError|ReferenceError' $XDG_RUNTIME_DIR/qs-after.log | sort -u > $XDG_RUNTIME_DIR/qs-after.err
grep -iE 'error|warn|TypeError|ReferenceError' $XDG_RUNTIME_DIR/qs-before.log | sort -u > $XDG_RUNTIME_DIR/qs-before.err
comm -13 $XDG_RUNTIME_DIR/qs-before.err $XDG_RUNTIME_DIR/qs-after.err
```

Expected: no output (check 11). Then open the left sidebar and switch to the Agents tab, and run the same log comparison again. Expected: still no new lines. Delete the four `$XDG_RUNTIME_DIR/qs-*` files afterwards.

- [ ] **Step 2: Sessions appear (check 1)**

Open two kitty windows (Super+Enter), run `claude` in `~/.dotfiles` in one and in `~/src/dots-hyprland` in the other. Open the Agents tab. In a third terminal:

```bash
claude agents --json | jq -r '.[] | select(.kind == "interactive") | "\(.name)  \(.cwd)"'
```

Expected: both sessions appear in the tab with `.dotfiles` and `dots-hyprland` as subtitles. Every interactive session in the command output appears in the tab, except those counted as "headless hidden".

- [ ] **Step 3: State follows (checks 2 and 3)**

In one session, send a prompt. Expected: within 3 s its dot pulses (busy), and after the reply it turns subdued (idle). Then send `Use the Bash tool to run: touch /tmp/agents-probe`. Expected: the row moves to the top, turns the error colour and reads `permission prompt · …`. The header shows `… · 1 need you`. Deny the prompt.

- [ ] **Step 4: Focus across workspaces (checks 4 and 5)**

Move one kitty window to workspace 3 (`hyprctl dispatch 'hl.dsp.window.move({workspace = 3})'` with it focused), go back to workspace 1, open the tab and click its row. Expected: Hyprland shows workspace 3 with that window focused, and the sidebar closes.

In the other kitty window, press `ctrl+shift+n` and start `claude` in the new OS window (two windows, one kitty process). Clicking each of the two rows focuses its own window.

- [ ] **Step 5: Background sessions (checks 6 and 15)**

```bash
cd ~/.dotfiles && claude --bg "sleep 60 then say done"
```

Close that terminal. Expected: the row shows `bg` and a `terminal` icon, and a click opens a new kitty running `claude attach <id>`. Leave that kitty open, open the tab again and click the row. Expected: the kitty is focused and no new window opens.

For check 15, start two background sessions with the same name:

```bash
cd ~/.dotfiles && claude --bg -n same-name "sleep 120 then say one"
cd ~/src/dots-hyprland && claude --bg -n same-name "sleep 120 then say two"
```

Open a kitty window and `claude attach <id>` the first one, so a window titled `… same-name` exists. Then open the tab and click each `same-name` row in turn. Expected: both rows show the `terminal` icon, and each click opens a new kitty running `claude attach` with that row's own id (`pgrep -af '[c]laude attach'`). Neither click focuses the existing window. Close the extra terminals and `/stop` both sessions afterwards.

- [ ] **Step 6: Headless sessions (check 7, Review Focus 3)**

With the claude-mem observer running (it is by default), run `claude agents --json | jq '[.[] | select(.kind == "interactive")] | length'`. Expected: the header shows `K headless hidden`, where K equals that count minus the interactive rows in the tab. Then start a session with no terminal window: tmux is not installed, so run `nix run nixpkgs#tmux -- new -d claude` in a terminal. Expected: K goes up by one within 3 s, and no row focuses a kitty window for it. Clean up with `nix run nixpkgs#tmux -- kill-server`.

- [ ] **Step 7: No polling while closed (check 8)**

Open the Agents tab for 10 s, close the sidebar, wait 10 s, then:

```bash
for i in $(seq 10); do pgrep -fc '[c]laude agents'; sleep 1; done | sort -u
```

Expected: only `0`. Repeat with the sidebar open on the Intelligence tab. Expected: only `0`. (The `[c]` bracket keeps `pgrep` from counting a wrapper shell whose own command line contains the pattern.)

- [ ] **Step 8: Missing claude and repeated failures (check 9, Review Focus 5)**

```bash
f=~/.config/quickshell/ii/scripts/claude/agents.sh
chmod u+w "$f"
sed -i 's/command -v claude >/command -v claude-missing-for-test >/' "$f"
```

Open the tab. Expected: "Claude Code not found", and `pgrep -fc '[c]laude agents'` stays 0. Close the sidebar. Then simulate a failing interface:

```bash
command cp "$iisrc/dots/.config/quickshell/ii/scripts/claude/agents.sh" "$f"; chmod u+w "$f"
sed -i 's/^raw=\$(claude agents --json)$/echo "simulated failure" >\&2; exit 1/' "$f"
```

Open the tab. Expected: the previous list stays and the error line reads `simulated failure`. After about 10 s, `pgrep -fc '[a]gents\.sh'` stays 0 (stopped after 3 failures). Close and reopen the tab: 3 more attempts run. Restore and verify:

```bash
command cp "$iisrc/dots/.config/quickshell/ii/scripts/claude/agents.sh" "$f"
diff -q "$iisrc/dots/.config/quickshell/ii/scripts/claude/agents.sh" "$f" && echo RESTORED
qs log -c ii | grep -iE 'TypeError|ReferenceError' | tail -3
```

Expected: `RESTORED`, and no `TypeError`/`ReferenceError` lines. (Run the "Checking the built source" block first if `$iisrc` is unset.)

- [ ] **Step 9: Detached sidebar (Review Focus 4)**

Open the Agents tab and press Ctrl+D. Expected: the detached window shows the tab and rows keep updating (send a prompt in a session and watch it turn busy). Clicking a row focuses the window, and the detached window stays open. Hide the detached window with the left-sidebar toggle keybind (it stays detached) and repeat the Step 7 `pgrep` loop. Expected: only `0`. Show it again, press Ctrl+D to reattach, close the sidebar and repeat the loop. Expected: only `0`.

- [ ] **Step 10: Config off (check 10)**

```bash
f=~/.config/illogical-impulse/config.json
command cp "$f" ~/config.json.bak
jq '.sidebar.agents.enable = false' "$f" > "$f.tmp" && command cat "$f.tmp" > "$f" && rm "$f.tmp"
```

Expected: the Agents tab disappears (after a qs restart if it does not hot-reload), and Intelligence and Translator still work. Restore with `command cat ~/config.json.bak > "$f" && rm ~/config.json.bak`.

- [ ] **Step 11: Daemon check (check 13)**

Quit every Claude Code session (including background ones: `claude agents --json | jq -r '.[] | select(.kind == "background") | .id'`, then `/stop` in each after attaching). Then:

```bash
claude daemon status
```

Expected: no supervisor. Open the Agents tab for 30 s, close it, then run:

```bash
pgrep -af '[d]aemon run'
```

If nothing prints, check 13 passes; skip Step 12. If a `claude daemon run` process remains, do Step 12. (This check cannot run from inside a Claude Code session. Run it from a plain terminal after this session has ended, or hand it to the user.)

- [ ] **Step 12 (only if Step 11 failed): Gate the call on a live Claude Code process**

In the clone's `scripts/claude/agents.sh`, replace the line `raw=$(claude agents --json)` with:

```bash
# With no Claude Code process running, `claude agents --json` would start a
# transient daemon just to report nothing (acceptance check 13).
pgrep -x .claude-wrapped >/dev/null || { echo '[]'; exit 0; }

raw=$(claude agents --json)
```

In `~/.dotfiles/scripts/ii-agents/test-agents-sh.sh`, replace `base_path="$work/tools"` with:

```bash
base_path="$work/tools"
# agents.sh skips `claude agents --json` when pgrep finds no Claude Code process.
printf '#!/usr/bin/env bash\nexit 0\n' > "$work/tools/pgrep"
chmod +x "$work/tools/pgrep"
```

and insert this before the line `rm "$work/bin/claude"`:

```bash
printf '#!/usr/bin/env bash\ntouch "%s/called"\necho "[]"\n' "$work" > "$work/bin/claude"
printf '#!/usr/bin/env bash\nexit 1\n' > "$work/tools/pgrep"
out=$(HOME="$work/home" PATH="$work/bin:$base_path" bash "$script")
check "no claude process prints []" "[]" "$out"
check "no claude process never calls claude" "no" "$([[ -e $work/called ]] && echo yes || echo no)"
printf '#!/usr/bin/env bash\nexit 0\n' > "$work/tools/pgrep"

```

Run the test before amending: `bash ~/.dotfiles/scripts/ii-agents/test-agents-sh.sh`. Expected: 14 `ok` lines. Fold the change into the first clone commit, then move the tag and export:

```bash
cd ~/src/dots-hyprland
git add -A && git commit -m "fixup! ii: add ClaudeAgents service and agents.sh"
GIT_SEQUENCE_EDITOR=: git rebase -q --autosquash krane/03-dock
git tag -f krane/04-agents krane
rm -f ~/.dotfiles/patches/ii/04-agents/*.patch && git -C ~/src/dots-hyprland format-patch --zero-commit --no-signature --no-numbered -o ~/.dotfiles/patches/ii/04-agents krane/03-dock..krane/04-agents
cd ~/.dotfiles && git add patches/ii/04-agents scripts/ii-agents
sudo nixos-rebuild switch --flake .#$(hostname)
```

Repeat Step 11 and Step 2. Expected: no daemon remains, and sessions still list while any exist. Commit:

```bash
cd ~/.dotfiles && git commit -m "Skip claude agents --json in the ii Agents tab when no Claude Code process runs"
```

- [ ] **Step 13: Desktop notification (check 14)**

Repeat Task 1, Step 2 with the sidebar closed. Expected: a notification naming the project, from whichever mechanism Task 1 recorded.

- [ ] **Step 14: Optional chat entry (check 12)**

Only if the user has an Anthropic API key and wants to try it: add the `extraModels` entry from `docs/II-INTEGRATION.md` "Claude in the sidebar chat", `/model` → "Claude Sonnet 5", `/key <key>`, ask a question. Expected: the reply streams. Otherwise record "not run: no API key".

- [ ] **Step 15: The other hosts**

On each other host, as it is next used: `sudo nixos-rebuild switch --flake .#$(hostname)`, then Steps 1, 2, 3, 4 and 7, and Step 13 if Task 1 added the hook (the package comes with the switch, and the hook entry comes with a `git pull` + `/dotfiles-apply` in `~/.claude` after the user's release). taractias waits until its hardware is verified (`hosts/taractias/default.nix`); record that when it applies.

- [ ] **Step 16: Report**

List each check (spec 1–15, Review Focus 1–5) with pass, fail or not run. Say whether Step 12 was applied and which notification mechanism Task 1 recorded, and remind the user that `~/.claude` has changes waiting for `/dotfiles-release` if Task 1 made any.
