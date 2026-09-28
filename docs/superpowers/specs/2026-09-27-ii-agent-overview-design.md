# Sidebar AI and Claude Code agent overview

Sub-project 4 of 5 in bringing pctrade/end4-pC work into this repo's ii setup.
It reuses the delivery mechanism from sub-project 1
(`docs/superpowers/specs/2026-09-27-ii-fork-fixes-design.md`): a
`git format-patch` series in its own directory, `patches/ii/04-agents/`,
applied to the pinned dots-hyprland source through `applyPatches` in
`lib/mk-host.nix`.

## Background

The user asked: "connect the sidebar's AI with local claude setup (is that
possible or even a good idea?, maybe rework to an agent overview to see what's
working?)".

- Terms: **ii** is end-4's illogical-impulse desktop shell, written in QML for
  Quickshell and shipped in end-4's `dots-hyprland` repo; **Hyprland** is the
  Wayland compositor it runs on; the **soymou module** is the third-party
  home-manager module that copies ii into `~/.config` on every switch (see
  `docs/II-INTEGRATION.md`); **teamclaude** is a local proxy
  (`modules/home/teamclaude.nix`) that Claude Code talks to instead of the
  Anthropic API directly.
- ii's left sidebar has an "Intelligence" tab (`modules/ii/sidebarLeft/AiChat.qml`)
  backed by `services/Ai.qml`. It talks to hosted models through small API
  strategies (`services/ai/*ApiStrategy.qml`) with `api_format` `openai`,
  `gemini` or `mistral`, lists local Ollama models, and offers the model three
  tools: `get_shell_config`, `set_shell_config`, `run_shell_command`.
  `policies.ai` is 0 (off), 1 (on) or 2 (localhost endpoints only). Extra models
  come from `ai.extraModels` in `~/.config/illogical-impulse/config.json`, which
  ii owns and Nix never writes. (Sub-project 5 later moves that file into the
  repo behind a directory symlink, still written only by ii.) API keys are stored in the keyring via
  the sidebar's `/key` command.
- The user runs Claude Code (`claude-code` 2.1.280 from `modules/home/dev.nix`)
  in kitty windows, plus background sessions (`claude --bg`, agent view), through
  a local teamclaude proxy (`modules/home/teamclaude.nix`) that serves
  subscription seats.
- end4-pC has no Claude or agent feature (its tree was checked); there is
  nothing to port. This sub-project is new work, delivered the same way.

Three options were on the table:

1. An Anthropic API key used through Anthropic's OpenAI-compatible endpoint, as
   an `ai.extraModels` entry. Pay per token.
2. Wrap the `claude` CLI (`claude -p --output-format stream-json`) as a new
   `ApiStrategy`. Subscription-backed, but the sidebar cannot answer permission
   prompts, so tools must be restricted, and it duplicates the terminal.
3. An agent overview tab that lists Claude Code sessions and focuses a
   session's terminal on click.

## Spike findings

All checks were read-only, on tariognatha, 2026-09-27.

### Reading session state

| Source | What it gives | Stability |
|---|---|---|
| `claude agents --json` | JSON array: `cwd`, `kind` (`interactive`/`background`), `startedAt`, `sessionId`, `name`; for live processes `pid` and `status` (`busy`/`waiting`/`idle`) and, when waiting, `waitingFor` (`permission prompt`, `input needed`, `sandbox request`, `worker request`, `dialog open`); for background sessions `id` (short id) and `state` (`working`/`blocked`/`done`/`failed`/`stopped`) | Documented at code.claude.com/docs/en/agent-view as "the supported way to read session state from outside Claude Code, for example from a status bar". Agent view as a whole is labelled a research preview. |
| `~/.claude/sessions/<pid>.json` | Per live process: the same fields plus `entrypoint` (`cli`, `sdk-cli`, `sdk-ts`), `procStart`, `updatedAt`, `parkedJobId` | Internal, undocumented. Not used. |
| `~/.claude/jobs/<id>/state.json` | Background session state | Docs say: read it through `claude agents --json` instead. Not used. |
| `~/.claude/projects/<cwd-slug>/<sessionId>.jsonl` | Full transcript (records `user`, `assistant`, `ai-title`, `last-prompt`, …). Up to 7.6 MB per file, 233 MB total | Internal format. Only its mtime is used, as "last activity". |
| Hooks (`SessionStart`, `Stop`, `Notification` with `permission_prompt`/`idle_prompt`, `SessionEnd`) and `statusLine` | Push events with `session_id`, `cwd`, `transcript_path` | Documented. Not used as the tab's data source, since `claude agents --json` already exists; a `Notification` hook is the step 0 fallback for desktop alerts. |

`claude agents --json` takes about 0.12 s wall and 0.12 s CPU and peaks at
about 165 MB RSS per call; the memory is released when the process exits. At
one call every 3 s that is about 4% of one core while the tab is open, and
nothing while it is closed. Whether the call starts the transient
`claude daemon run` supervisor when none is running was not tested (the
supervisor was running during the spike; `daemon.log` shows it starting with
the first interactive session); acceptance check 13 covers it.

It lists every live interactive and background session, including
headless SDK sessions (the claude-mem observer spawns these continuously: 2 of
the 4 live sessions during the spike). A terminal that is attached to a
background session is not listed separately; the background session is. Without
`--all`, finished background sessions whose process has exited are omitted.

### Notifications Claude Code already sends

`~/.claude/settings.json` (user-managed, not in this repo) has
`inputNeededNotifEnabled` and `agentPushNotifEnabled` set, but those push to
the Claude mobile app. On the desktop, Claude Code emits terminal
notifications through its `preferredNotifChannel` (unset, so `auto`; the
binary knows `kitty`, `ghostty`, `iterm2`, `terminal_bell`). Whether a
permission prompt in a kitty window on another workspace produces a desktop
notification today was not tested. The configured hooks are `PreToolUse` and
`UserPromptSubmit` only; there is no `Notification` hook.

### Mapping a session to a window

`claude agents --json` does not report which terminal or window a session
runs in, so the mapping below is derived.

- Interactive sessions: walking `PPid` from the session `pid` reaches the
  terminal. Observed chain: `claude` 3127 → `fish` → `kitty` 2840 →
  `Hyprland`. `hyprctl clients -j` (and ii's `HyprlandData.windowList`) carries
  `pid`, `title` and `address` per window, so the first ancestor whose pid owns
  a Hyprland client identifies the window. This works for any terminal.
- Background sessions: the ancestry is misleading. Session 3444 descends from
  `claude daemon run` (the supervisor, pid 3403), which was itself spawned from
  the first interactive session, so a naive walk "finds" that session's kitty
  even when nothing is attached. Ancestry is therefore only used for
  interactive sessions; background sessions are never walked.
- Terminal titles: Claude Code sets the terminal title to
  `<spinner> <session name>` (`◐`/`◑` while busy, `✳` otherwise). The kitty
  window of the attached terminal was titled `◑ Illogical Impulse Hyprland
  ricing ideas`, the background session's name. This is the only link from a
  background session to the window it is attached in, and it disambiguates
  several windows owned by one terminal process.
- Terminal: `terminal = "kitty"` in `custom/variables.lua`, so each Super+Enter
  starts a separate kitty process. Windows opened from inside kitty
  (`ctrl+shift+n`) and ii's own `apps.terminal` (`kitty -1`) share a process.
  Kitty tabs and splits cannot be selected without kitty remote control, which
  `~/.config/kitty/kitty.conf` does not enable (and that file is recopied by the
  soymou module on every switch).
- Focusing: ii already focuses windows with
  `Hyprland.dispatch(\`hl.dsp.focus({window = "address:${address}"})\`)`
  (`modules/ii/overview/OverviewWidget.qml`), the Lua dispatcher syntax of the
  pinned Hyprland 0.56.

### The sidebar chat and Claude

- Endpoint: `https://api.anthropic.com/v1/chat/completions`, with
  `Authorization: Bearer <key>`, which is exactly what `OpenAiApiStrategy`
  sends. Streaming, system messages (hoisted), `temperature` (0 to 1, higher is
  capped) and usage fields are supported. Anthropic describes the layer as
  meant for testing and comparison, "not considered a long-term or
  production-ready solution for most use cases"; thinking output is not
  returned.
- Model IDs (platform.claude.com models overview, checked 2026-09-27):
  `claude-opus-5-5` ($4/$20 per MTok), `claude-sonnet-5` ($2/$10),
  `claude-haiku-4-5-20251001` ($1/$5; retirement not sooner than
  2026-10-15, so it may disappear within weeks).
- Tool calls: `OpenAiApiStrategy.parseResponseLine` reads only
  `delta.content` and `delta.reasoning`, never `delta.tool_calls`. With the
  user's `ai.tool` = `functions`, the three tools are sent, and a Claude reply
  that calls one ends up as an empty message. This is an upstream limitation
  for every `openai`-format model, not specific to Claude. Because `extraParams`
  is merged after the base request (`Object.assign`), an entry can send
  `"tools": []` to avoid it.
- Subscription instead of API key: routing the teamclaude proxy or the Claude
  Code OAuth credentials into the sidebar's curl requests would use
  subscription credentials outside Claude Code. Anthropic's terms limit those
  credentials to Claude Code and Anthropic's own apps. Rejected.
- CLI wrapper (option 2): `claude -p` stays inside Claude Code, so it is
  allowed, but every sidebar message would start a full Claude Code session
  (hooks, MCP servers, plugins, CLAUDE.md), tools would have to be disabled or
  pre-approved because nobody can answer a permission prompt from the sidebar
  (`-p` mode has no interactive prompt; the sidebar would need its own approval
  UI wired to Claude Code's permission protocol),
  and the result is a worse terminal. The spike found nothing that changes
  that.

## Recommendation

Is connecting the sidebar AI to the local Claude setup possible? Partly. Making
the sidebar chat use the Claude Code subscription is not something to do: the
proxy route is outside Anthropic's terms, and the CLI route produces a slow,
tool-less copy of the terminal. Making the sidebar chat use Claude through an
API key is possible today with no code, by adding one `extraModels` entry, but
it is billed per token and duplicates what Claude Code in a terminal already
does better.

The useful connection is the other direction: let the desktop tell the user
what the Claude Code sessions are doing. There are two parts to that, and the
cheaper one matters more:

1. **Being told when a session needs you.** A session blocked on a permission
   prompt while its window is on another workspace is the most expensive case:
   it waits until someone happens to look. A sidebar tab that only refreshes
   while open cannot solve this. Claude Code's own terminal notifications, or
   a `Notification` hook that calls `notify-send`, can, without touching ii.
   This is step 0 below: verify it works, and add the hook only if it does not.
2. **Seeing all sessions at a glance and jumping to one.** This is what the
   Agents tab does. `claude agents --json` is documented as the supported
   interface for status bars, so the tab is cheap to build and fits the
   shell. It complements step 0; it does not replace it.

The recommendation, in order:

- Step 0: make sure a blocked session produces a desktop notification
  (no ii code).
- Build the Agents tab in the left sidebar (this spec).
- Keep the Intelligence tab as is. Document the optional Claude
  `extraModels` entry for users who want an API-key chat; it answers the
  literal question with zero code, but ship no code for it.
- The CLI chat wrapper stays out of scope.

The main risk is that `claude agents --json` belongs to agent view, which is a
research preview. That is accepted because it is the only interface Anthropic
documents for this purpose, a break is contained to this one tab (the rest of
the shell is unaffected, and the tab says what failed), and the check after
each `claude-code` bump is one command. If it is withdrawn, the tab is dropped
with its two patches.

## Goal

A new left-sidebar tab, "Agents", that shows every Claude Code session running
on the machine that belongs to a window or runs in the background, what state
it is in, and focuses the session's terminal on click.

Success means:

- A session started in kitty appears in the tab within one refresh interval
  with its project and name, and its state follows busy, waiting and idle as
  it changes.
- A session waiting on a permission prompt is visibly marked as needing
  attention, with the `waitingFor` reason.
- Clicking an interactive session focuses its kitty window, including when it
  is on another workspace.
- Clicking a background session focuses the window it is attached in, or,
  if none, opens a new terminal running `claude attach <id>`.
- With the tab closed, the shell spawns no `claude` processes.
- A permission prompt in a session whose window is not visible produces a
  desktop notification (step 0), independent of the tab.
- All three hosts build; Quickshell starts with no new QML errors.

## Constraints

- Delivered in the dots-hyprland source handed to the soymou module, as
  patches in `patches/ii/04-agents/`. Nothing in `~/.config` is edited by
  hand, and nothing in the repo writes
  `~/.config/illogical-impulse/config.json`.
- Only the documented interface is parsed: `claude agents --json`. The one
  exception is the transcript file's mtime (a `stat`, no content read), used
  for "last activity", with a fallback when the file is not found.
- Privacy: the tab shows the session name, the working directory, state,
  `waitingFor`, and timestamps. It reads no transcript content, no prompts, no
  replies, and nothing from `~/.claude/.credentials.json` or other secrets.
  Session names can be auto-generated from the conversation topic and cwd can
  reveal project names; that is the same information the terminal titles
  already show.
- The tab never sends input to a session, approves a permission, stops or
  deletes a session. It only reads and focuses. Stopping and answering stay in
  the terminal.
- No new runtime dependencies beyond `claude`, `jq` and `bash`, all already on
  the Quickshell `PATH` on every host (`claude-code` and `jq` come from
  `modules/home`). Step 0's hook adds `notify-send` (libnotify), which
  ii already calls.

## Scope

### In

- Step 0: verify desktop notifications for blocked sessions; if missing, a
  `Notification` hook (below). No ii code.
- A service `services/ClaudeAgents.qml` and a helper script
  `scripts/claude/agents.sh`.
- A tab `modules/ii/sidebarLeft/Agents.qml` with a row delegate
  `modules/ii/sidebarLeft/agents/AgentRow.qml`.
- Tab wiring in `modules/ii/sidebarLeft/SidebarLeftContent.qml` and one config
  key in `modules/common/Config.qml`.
- A documented, optional Claude `extraModels` entry in
  `docs/II-INTEGRATION.md`.

### Out

- Any change to `services/Ai.qml` or its strategies, including a `claude -p`
  strategy and an `openai` tool-call parser.
- Showing transcript content (last prompt, last reply).
- Actions on sessions other than focus and attach: stop, reply, approve,
  dispatch new work.
- Selecting a kitty tab or split (needs kitty remote control).
- A bar indicator for sessions that need attention, and Claude sessions as a
  category in ii's launcher search (`services/LauncherSearch.qml`). Both are
  natural follow-ups that reuse `ClaudeAgents.qml`; the bar indicator needs
  polling while the sidebar is closed, which this version avoids. See the open
  questions.
- Finished background sessions (`--all`).

## Design

### Step 0: desktop notification for blocked sessions

Before any ii work, trigger a permission prompt in a kitty window on another
workspace and see whether a desktop notification appears (ii's notification
popup). Also try `"preferredNotifChannel": "kitty"` if `auto` shows nothing.

If none appears, add a `Notification` hook. The script is packaged in Nix
(`pkgs.writeShellApplication` named `claude-notify` in `modules/home/dev.nix`,
runtime inputs `jq` and `libnotify`) so every host has it:

```sh
in=$(cat)
title="Claude Code · $(basename "$(jq -r '.cwd // "?"' <<<"$in")")"
body=$(jq -r '.message // .notification_type // "needs attention"' <<<"$in")
notify-send -a "Claude Code" -i utilities-terminal "$title" "$body" || true
```

The hook entry itself (matcher `permission_prompt|idle_prompt|elicitation_dialog`,
command `command -v claude-notify >/dev/null && claude-notify || true`) goes
into `~/.claude/settings.json`. That file is not in this repo: `~/.claude` is
the separate claude-dotfiles repo, shared with machines that have no
`claude-notify` (hence the `command -v` guard). The entry and its README/SETUP
rows are left uncommitted there and ship when the user runs `/dotfiles-release`
(which pushes); `docs/II-INTEGRATION.md` documents it. The script never
blocks: no `--wait`, and it always exits 0.

### Data source: `scripts/claude/agents.sh`

One script, run by the service, prints one JSON array on stdout:

```sh
#!/usr/bin/env bash
set -euo pipefail
claude agents --json | jq -c '.[]' | while read -r s; do
  chain=()
  if [[ $(jq -r '.kind' <<<"$s") == interactive ]]; then
    p=$(jq -r '.pid // empty' <<<"$s")
    while [[ -n $p && $p != 0 && $p != 1 ]]; do
      chain+=("$p")
      p=$(awk '/^PPid:/{print $2}' "/proc/$p/status" 2>/dev/null || true)
    done
  fi
  sid=$(jq -r '.sessionId // empty' <<<"$s")
  t=$(stat -c %Y "$HOME"/.claude/projects/*/"$sid".jsonl 2>/dev/null | head -n1 || true)
  jq -c --argjson chain "$(printf '%s\n' "${chain[@]}" | jq -sc 'map(select(. != "") | tonumber)')" \
        --arg mtime "${t:-}" '. + {ancestors: $chain, lastActivity: ($mtime|tonumber? // null)}' <<<"$s"
done | jq -sc '.'
```

The exact code is an implementation detail; the contract is: each entry of
`claude agents --json`, unchanged, plus `ancestors` (for interactive sessions,
the pid chain from the session up to, not including, init; empty for
background sessions, whose ancestry leads to the supervisor rather than to a
terminal) and `lastActivity` (transcript mtime in seconds, or null). If
`claude` is missing, the script exits 127; any other failure exits non-zero
with a message on stderr.

A script rather than QML because walking `/proc` from QML needs one `FileView`
per pid per refresh, and `jq`/`awk` are already used by ii's scripts.

### Service: `services/ClaudeAgents.qml`

A `Singleton` following the pattern of the existing services:

- `property var sessions: []`, `property bool available`, `property string
  error`, `property int headlessCount`.
- `property bool active`, set by the tab while it is visible
  (`GlobalStates.sidebarLeftOpen` and the Agents tab is current). A `Timer`
  with `interval: 3000`, `running: active`, `triggeredOnStart: true` starts a
  `Process` running the script, unless the previous run is still going. If a
  run takes longer than 1 s, the interval doubles, up to 15 s, and returns to
  3 s after a fast run.
- On success it joins each entry with `HyprlandData.windowList` to set
  `window` (a Hyprland client or null):
  1. Interactive: the first pid in `ancestors` that owns one or more clients.
     If it owns several, the one client whose title minus the spinner prefix
     equals `name`; if none or several match, the most recently focused of
     them (`focusHistoryID`). All candidates are windows of the same terminal
     process, so the worst case is the right terminal showing another tab.
  2. Background: the client whose title minus the spinner prefix equals
     `name`, only if exactly one client matches; otherwise null. Two sessions
     with the same name therefore open a new attach terminal instead of
     focusing a guessed window.
- Interactive sessions with no `window` are headless (SDK sessions such as the
  claude-mem observer, or a session in a TTY or over SSH). They are dropped and
  counted in `headlessCount`.
- Sort: `waiting` first, then `busy`, then the rest; within a group, newest
  `lastActivity` first.
- `function focus(session)`: if `session.window`, dispatch
  `hl.dsp.focus({window = "address:<address>"})`. Else, for a background
  session, `Quickshell.execDetached([...terminal, "-e", "claude", "attach",
  session.id])` where `terminal` is `kitty`. Interactive sessions without a
  window are never shown, so there is no third case.

### UI: the Agents tab

Tab entry `{"icon": "smart_toy", "name": Translation.tr("Agents")}`, placed
after Intelligence and before Translator, shown when
`Config.options.sidebar.agents.enable` is true (default true). The pinned
`SidebarLeftContent.qml` builds `tabButtonList` and the swipe view's
`contentChildren` as two parallel lists, so the Agents entry goes into both at
the same position, and the placeholder condition (which checks only
Intelligence and Translator besides the anime closet) also counts Agents.

Each row (`AgentRow.qml`, using ii's existing `RippleButton`, `StyledText` and
`MaterialSymbol` widgets and `Appearance` colours):

- Leading status dot: `waiting` uses `Appearance.colors.colError` with the
  `waitingFor` text; `busy` uses the primary colour with a slow pulse; `idle`
  and `done` are subdued. Background `state` `blocked` without a live process
  is shown as waiting.
- Title: `name`, elided. Subtitle: cwd basename, then `bg` for background
  sessions, then relative last activity ("2 min ago") or start time.
- Trailing icon: `open_in_new` when the session has a window,
  `terminal` when clicking will attach in a new terminal.
- Click calls `ClaudeAgents.focus(session)` and closes the sidebar, as other
  launcher-style actions in ii do.

Header line: "N sessions · M need you", and "K headless hidden" when
`headlessCount > 0`. Empty state: "No Claude Code sessions". Error states are
listed below.

### Config

`modules/common/Config.qml` gains, under `sidebar`:

```qml
property JsonObject agents: JsonObject {
    property bool enable: true
}
```

The default applies while the key is absent from `config.json`. ii's
`FileView` only writes the file back after some option changes
(`onAdapterUpdated`), so the key shows up in `config.json` after the next
settings change. To turn the tab off, the user adds
`"sidebar": {"agents": {"enable": false}}` to `config.json` (ii-owned, not
Nix).

### Optional: Claude in the Intelligence tab

Not code; documented in `docs/II-INTEGRATION.md` under a "Claude in the
sidebar chat" heading. The user adds to `ai.extraModels` in
`~/.config/illogical-impulse/config.json`:

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

then selects it with `/model` and stores the key with `/key <key>` (kept in
the keyring by ii, never in the repo). `tools: []` avoids the empty-reply
problem above. Sonnet 5 is the suggested default for cost; Opus 5.5 works the
same with `claude-opus-5-5`.

### Wiring and delivery

Two commits on the shared `krane` branch in the dots-hyprland clone, after the
dock commits (tag `krane/03-dock`), exported into their own directory with
`git format-patch --no-numbered -o patches/ii/04-agents krane/03-dock..krane/04-agents`:

1. `ii: add ClaudeAgents service and agents.sh` (new files plus the config
   key).
2. `ii: add Agents tab to the left sidebar` (new tab files plus the
   `SidebarLeftContent.qml` edit).

Commit headers follow sub-project 1's format with `Port: new (no fork
origin)` and a "Drop when" of "the pinned ii ships an equivalent agents tab, or
`claude agents --json` is removed".

Patches rather than whole files installed by `kraneIiOverrides`: the tab needs
edits to two upstream files anyway, so a patch series is required; keeping the
new files in the same patches means one mechanism, build-time failure instead
of activation-time failure, and `git am -3` to rebase them on a pin bump. New
files never conflict; only the two small edits can.

No Nix changes beyond what sub-project 1 adds: its generic wiring already
applies every `patches/ii/*/` directory in lexical order. The only Nix change
in this sub-project is the optional `claude-notify` package from step 0.

### Sequencing and dependencies

- Step 0 has no dependencies and comes first.
- The two patches depend on sub-project 1's layout and wiring being in place
  (`patches/ii/` and the `iiSeries` loader in `lib/mk-host.nix`). At the time
  of writing sub-project 1 is approved but not implemented.
- Sub-projects 2 (translator) and 3 (dock) come earlier on the branch. Neither
  edits `SidebarLeftContent.qml`. Both edit `Config.qml`: the translator flips
  `sidebar.translator.enable`, right above where the new `sidebar.agents`
  block goes, and the dock adds keys to the `dock` object. These patches are
  authored on top of theirs in the same clone branch, so any overlap is
  resolved once, at authoring time with `git am -3`, never at build time.
  Keeping the tab's code in new files limits the overlap to the tab list, one
  `Component` and one config block.
- A `claude-code` version bump is a check point: run `claude agents --json`
  and compare the field names with the spike table above. That takes a
  minute and catches a changed interface before the tab shows errors.

## Error handling

| Condition | Behaviour |
|---|---|
| `claude` not on `PATH` (script exits 127) | Tab shows "Claude Code not found"; timer stops until the tab is reopened. |
| Script fails or prints invalid JSON | Keep the previous list, show a one-line error with the stderr text, retry on the next tick. After 3 consecutive failures, stop the timer until the tab is reopened. |
| `claude agents --json` output changes shape (research preview) | Missing fields are treated as absent (`?.`). Unknown `status` or `state` values show as a neutral dot with the raw value. |
| A run takes longer than the interval | The next tick is skipped while the `Process` is running; runs over 1 s double the interval up to 15 s. |
| Session pid exits between listing and focus | The dispatch targets a window address, not a pid; a closed window makes the dispatch a no-op, and the next refresh drops the row. |
| Transcript not found | `lastActivity` is null; the row shows start time instead. |
| Title matches zero or several windows | Interactive: most recently focused window of the same terminal process. Background: no window; clicking opens an attach terminal. Never a guessed window from another process. |
| Focus dispatch finds no window | The row's window was closed between refreshes; the dispatch is a no-op and the next refresh updates the row. |

## Testing

### Build

1. `nix build` of `patchedDotfiles` with the full series.
2. `nixos-rebuild dry-build --flake .#<host>` for tariognatha, tarmantria and
   taractias.

### Acceptance (tariognatha, then each laptop where Claude Code is used)

| # | Check |
|---|---|
| 1 | With two kitty windows each running `claude` in different repos, open the Agents tab. Both appear with the right cwd basename. `claude agents --json` run in a third terminal lists the same interactive sessions (minus headless ones). |
| 2 | Send a prompt in one session. Within 3 s its row turns busy, and returns to idle after the reply. |
| 3 | Trigger a permission prompt (a Bash command not on the allow list). The row moves to the top, shows the waiting colour and `permission prompt`. |
| 4 | Move one kitty window to another workspace, click its row. Hyprland switches to that workspace and focuses the window. |
| 5 | Open a second OS window from the same kitty process (`ctrl+shift+n`) running another `claude`. Clicking each row focuses the right window (title match). |
| 6 | Start `claude --bg "sleep 60 then say done"` and close the terminal. The row shows `bg`; clicking opens a new kitty with `claude attach <id>`. Attach from a terminal, then click again: that terminal is focused, no new one opens. |
| 7 | While claude-mem observer sessions run, they are not listed and the header shows "K headless hidden". |
| 8 | Close the sidebar; after 10 s, `pgrep -fc 'claude agents'` stays 0 over a further 10 s. |
| 9 | Temporarily move `claude` off `PATH` for qs (or rename the script's command in a test build): the tab shows "Claude Code not found" and the qs log has no QML errors. |
| 10 | Set `sidebar.agents.enable` to false: the tab disappears, other tabs keep working. |
| 11 | Restart qs: no new QML errors or warnings compared with before the series. |
| 12 | Optional entry: with an Anthropic key stored via `/key`, a question to "Claude Sonnet 5" streams a reply. |
| 13 | Stop all Claude Code sessions (`claude daemon status` reports no supervisor), open the tab for 30 s, close it. No `claude daemon run` process remains. If one does, the tab must call `claude agents --json` only while at least one `claude` process exists (`pgrep -x .claude-wrapped`), and this check is repeated. |
| 14 | Step 0: a permission prompt in a kitty window on another workspace produces a desktop notification naming the project, with the sidebar closed. |
| 15 | Two background sessions with the same name: clicking either opens an attach terminal for that session's id; neither focuses the other's window. |

## Commits

In this repo, each exported patch is committed with its entry in the docs
table. One commit adds the "Claude in the sidebar chat" section and the step 0
hook instructions to `docs/II-INTEGRATION.md`. If step 0 needs the hook, the
`claude-notify` package is its own commit, made first.

## Open questions for the user (defaults in brackets)

1. Show headless (SDK) sessions behind a toggle? [No; only a count.]
2. Show a short preview of the last message, read from the transcript?
   [No; it means parsing an internal format and puts conversation text on the
   screen.]
3. Refresh interval while the tab is open? [3 s, backing off to 15 s when
   slow.]
4. Should Claude Code's own terminal title be used for matching if the user
   later disables it (`CLAUDE_CODE_DISABLE_TERMINAL_TITLE`)? [Accept the
   degradation: interactive sessions still match by pid, only background
   sessions and shared-process windows lose precise focus.]
5. (Decided: the patches live in `patches/ii/04-agents/`, following the
   shared layout from sub-project 1. There is no patch-count threshold.)
6. Add the optional Claude `extraModels` entry to the docs at all, given the
   compatibility layer is not meant for long-term use? [Yes, clearly marked
   optional and pay-per-token.]
7. Follow-up: a bar indicator ("M agents need you") and a launcher-search
   category for jumping to a session by name? [Not in this version. Revisit
   after using the tab for a couple of weeks; both reuse `ClaudeAgents.qml`.
   The bar indicator would poll every 15 s while any `claude` process exists.]
8. Step 0 needs a hand edit of `~/.claude/settings.json`. Bring that file under
   home-manager instead? [No; it holds live state Claude Code writes itself.]
