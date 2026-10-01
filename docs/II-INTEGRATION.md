# illogical-impulse integration

This flake layers declarative Hyprland configuration on top of end-4's
illogical-impulse (ii) dotfiles. ii is delivered by the third-party
home-manager module soymou/illogical-flake, called the soymou module below.

Pinned revisions (`flake.lock`), re-read this document after either moves:
`dots-hyprland` at `21733c3ca7f4edc20faafedea844dc96002c6f7f`,
`illogical-flake` at `8629ef302b956cf6ab0089338a867dbe844156fd`.

## The problem

ii cannot be symlinked into place. The soymou module installs it through
`home.activation.copyIllogicalImpulseConfigs`
(`home-modules/dotfiles.nix`, `entryAfter [ "writeBoundary" ]`), which on
every `home-manager switch`:

1. removes and recopies every top-level entry of `dots/.config` and
   `dots/.local/share` from the upstream checkout,
2. truncates `~/.config/hypr/custom/env.lua` with `cat >` to inject NixOS
   `PATH` and `XDG_DATA_DIRS` fixes (the flake's `QT_QPA_PLATFORMTHEME` line is patched out),
3. appends its `hl.plugin(...)` block to `custom/general.lua`.

Anything home-manager symlinks under a wiped path dies on the next
switch. Anything this repo writes before that step dies immediately.

### Wiped on every switch

`~/.config` (each entry below is removed and recopied):

| | | | |
| --- | --- | --- | --- |
| `Kvantum` | `chrome-flags.conf` | `code-flags.conf` | `darklyrc` |
| `dolphinrc` | `fish` | `fontconfig` | `foot` |
| `fuzzel` | `hypr` | `kde-material-you-colors` | `kdeglobals` |
| `kitty` | `konsolerc` | `matugen` | `mpv` |
| `quickshell` | `starship.toml` | `thorium-flags.conf` | `wlogout` |
| `xdg-desktop-portal` | `zshrc.d` | | |

`~/.local/share`: `icons`, `konsole`, `kxmlgui5`. Excluded:
`~/.config/illogical-impulse`. It is a symlink into this repo,
`hosts/<host>/illogical-impulse/` (see "Settings persistence"). The copy
step's `mkdir -p` and its `config.json` seed check follow the link.

Two consequences this repo already handles:

- The soymou module turns on `programs.fish` and `programs.starship`, so
  the copy step replaces home-manager's `~/.config/fish/config.fish`
  symlink with a regular file. `lib/mk-host.nix` sets
  `home-manager.backupFileExtension = "hm-bak"` so the next switch does
  not abort on that collision. `*.hm-bak` files after a switch are normal.
- Fish customisation lives in NixOS `programs.fish.*` (`/etc/fish/...`),
  outside `$HOME`, never in home-manager.

## Activation order

```
home-manager switch
  writeBoundary                 home-manager writes ~/.config symlinks
  copyIllogicalImpulseConfigs   soymou module wipes/recopies, truncates
                                 env.lua, appends general.lua
  kraneIiOverrides               this repo installs owned files, appends
                                 its block to env.lua / general.lua
```

`home.activation.kraneIiOverrides = lib.hm.dag.entryAfter [
"copyIllogicalImpulseConfigs" ];`

home-manager's `hm.dag.topoSort` matches `after` names by
`a: b: builtins.elem a.name b.after`. A name no entry defines is never
matched. Only a cycle fails the build. A renamed or dropped
`copyIllogicalImpulseConfigs` would let `kraneIiOverrides` run unordered,
maybe before the wipe, and every override would be lost with no warning.

`modules/home/desktop/illogical-impulse.nix` guards against that with an
assertion, `config.home.activation ? copyIllogicalImpulseConfigs`, which
fails the build with a pointer to this document. Check it first after
any `nix flake update` that moves `illogical-flake`.

## Owned vs appended

| File (under `~/.config/hypr`) | Mode | Why |
| --- | --- | --- |
| `monitors.lua` | owned | Not shipped upstream. Sourced by `hyprland.lua` if present. |
| `custom/variables.lua` | owned | Upstream ships it empty. |
| `custom/keybinds.lua` | owned | Upstream ships one bind. |
| `custom/execs.lua` | owned | Upstream ships it empty. |
| `custom/rules.lua` | owned | Upstream ships it empty. |
| `custom/env.lua` | appended | Truncated with `cat >` every switch. Our block must land after. |
| `custom/general.lua` | appended | The soymou module appends its `hl.plugin` block. Our block must land after. |
| `custom/krane_gui.lua` | owned | Rendered from `hosts/<host>/ii-settings.json` by `modules/home/ii-settings.nix`; rewritten live by the settings window. Required last by `monitors.lua`. |

Recording binds (`custom/keybinds.lua`) come from `modules/home/desktop/recording.nix`,
which also unbinds ii's upstream wf-recorder binds
(`hyprland/keybinds.lua:85-93`) so the freed keys can be rebound to
`gsr-ui-cli`.

Owned files are written with `install -Dm644`, as regular files, never
symlinks: a symlink into the store would be wiped by the copy step and
would be read only besides.

Appended files get their block replaced, not merely appended:

```sh
awk -v s="$sentinel" '$0 == s { exit } { print }' "$target" > "$tmp"
cat "$tmp" > "$target"
{ printf '\n%s\n' "$sentinel"; cat "$chunk"; } >> "$target"
```

Everything from the sentinel line down is dropped before the fresh block
is written, so a stale block from an older generation self-corrects. The
sentinel is `-- >>> krane overrides >>>`, appearing exactly once after a
switch since the copy step recreates both files first. More than once
means the drop failed.

The block is written even when the rendered body is empty, so a stock
install still leaves `custom/env.lua` ending in the sentinel, keeping
the verification below meaningful whether or not a host sets the option.

The append runs from a store script, not a plain redirect: a redirection
cannot be prefixed with `$DRY_RUN_CMD`, it would still fire in dry-run
mode, while one command swallows it whole. Every tool used is an
absolute store path, so activation does not depend on the user's `PATH`.

## Dry runs are not read-only

This repo's step honours `$DRY_RUN_CMD` on every mutating command, so
`home-manager switch -n` and `nixos-rebuild dry-activate` print it
without touching `$HOME`. The soymou module's `cat > custom/env.lua` and
`cat >> custom/general.lua` are not guarded the same way, so a dry run
really does truncate `custom/env.lua`, destroying our override block,
and append another copy of the plugin block to `custom/general.lua`.

Nothing is lost for good: the next real switch wipes and recreates both
files, and our block is written again. Do not read a dry run as read
only, or run several dry runs then inspect `general.lua` and conclude
the append is broken. Run a real `nixos-rebuild switch` if you need the
files correct now.

## How ii sources Lua

From `dots/.config/hypr/hyprland.lua` at the pinned revision:

```
hyprland.lib -> hyprland.services -> hyprland.env -> custom.env
  -> hyprland.execs -> hyprland.general -> hyprland.rules
  -> hyprland.colors -> hyprland.keybinds
  -> custom.execs -> custom.general -> custom.rules -> custom.keybinds
  -> workspaces.lua -> monitors.lua -> hyprland.shellOverrides.main
```

Two things worth getting right:

- `custom/variables.lua` is not in that chain. It is sourced from
  `hyprland/keybinds.lua`, right after `hyprland/variables.lua`, which
  makes it the right place to override `terminal`, `fileManager`,
  `browser` and the other Lua globals that hold shell command strings,
  not package paths.
- There is no `custom/monitors.lua`. Monitor rules go in the top-level
  `monitors.lua`, which this repo owns and renders from
  `krane.hypr.monitors`. Its last lines require `custom/krane_gui.lua`,
  where display changes made in the ii settings window land. Do not use
  `nwg-displays`: whatever it writes into `monitors.lua` is replaced on
  the next switch.

## How to add an override

Pick the option for the file to affect, in `hosts/<host>/display.nix`
for one host or a module under `modules/home/desktop/` for all desktop hosts:

| Option | Renders to | Emits |
| --- | --- | --- |
| `krane.hypr.monitors` | `monitors.lua` | `hl.monitor({...})` |
| `krane.hypr.env` | `custom/env.lua` | `hl.env(k, v)` |
| `krane.hypr.extraMonitorsLua` | `monitors.lua` | verbatim Lua |
| `krane.hypr.variables` | `custom/variables.lua` | `k = v` globals |
| `krane.hypr.unbinds` | `custom/keybinds.lua` | `hl.unbind(...)` |
| `krane.hypr.extraKeybindsLua` | `custom/keybinds.lua` | verbatim Lua |
| `krane.hypr.settings` | `custom/general.lua` | `hl.config({...})` |
| `krane.hypr.devices` | `custom/general.lua` | `hl.device({...})` |
| `krane.hypr.extraGeneralLua` | `custom/general.lua` | verbatim Lua |
| `krane.hypr.binds` | `custom/keybinds.lua` | `hl.bind(...)` |
| `krane.hypr.execOnce` | `custom/execs.lua` | `hl.on("hyprland.start", ...)` |
| `krane.hypr.windowRules` | `custom/rules.lua` | `hl.window_rule({...})` |

```nix
krane.hypr.binds = [
  {
    keys = "SUPER + T";
    action = "hl.dsp.exec_cmd(terminal)";
    description = "Launch terminal";
  }
];
```

`binds.*.action` and `extraGeneralLua` are the only raw Lua escape
hatches. Everything else is serialised and cannot inject a syntax error.
A value it cannot represent throws at evaluation time.

Run `nix flake check` to check the result: `checks.lua-syntax`
runs `luac -p` over every rendered file for all three hosts.

Unknown keys in `hl.config` and unknown fields in `hl.monitor`/`hl.device`
are hard errors at Hyprland start. Neither `nix flake check` nor `luac -p`
catches them. `hyprctl configerrors` after first login is the only gate.
Use the underscore spelling of every Hyprland option in `krane.hypr.settings`,
for example `tap_to_click`, never the hyphenated hyprlang name.

## Patched files

Besides the owned/appended Hyprland files above, `kraneIiPatches` (also
`entryAfter [ "copyIllogicalImpulseConfigs" ]`) sed-patches files ii itself
writes or wipes on every switch, guarded by `[ -f "<file>" ]` so a missing
file is skipped rather than failing activation:

- `~/.config/fish/config.fish`:
  `s|^\(\s*\)cat \(~/.local/state/quickshell/user/generated/terminal/sequences.txt\)|\1command cat \2|`.
  `modules/nixos/common/shells.nix` aliases `cat` to `bat --color=always` at
  NixOS level (`/etc/fish` loads first), so ii's own line printing that
  file would emit a bat frame instead of raw OSC sequences. The patch
  makes that one line call `command cat` to bypass the alias.
- `~/.config/hypr/hyprland/keybinds.lua`:
  `s|killall ydotool qs quickshell|killall ydotool; pkill -f '[q]s-wrapped -c ii'|`.
  The nix-wrapped quickshell binary's comm is truncated to `.quickshell-wra`,
  so the restart-widgets keybind's `killall qs quickshell` never matches and
  every press stacks a new `qs` instance. `pkill -f` matches the full
  command line instead, so it still finds and kills the wrapped process.
- `~/.config/quickshell/ii/modules/common/Config.qml`:
  `s/property bool launchOnStartup: false/property bool launchOnStartup: true/`.
  Fresh hosts seed `~/.config/illogical-impulse/config.json` from this QML
  default the first time ii's copy step runs. Every host autologins via
  greetd straight into Hyprland (`modules/nixos/desktop/desktop.nix`), so there's
  no session picker to lock behind; flip the default itself so ii locks
  immediately on startup. After that the value lives in this host's
  config.json in the repo, and the settings window can still turn it off.
- `~/.config/quickshell/ii/scripts/colors/switchwall.sh`:
  `s#gsettings \(set\|get\) org.gnome.desktop.interface#GSETTINGS_SCHEMA_DIR=<schemas> <store gsettings> \1 org.gnome.desktop.interface#g`.
  ii's dark/light toggle writes `color-scheme` with gsettings, but the ii
  session has no schemas on `XDG_DATA_DIRS`, so every call failed with "No
  schemas installed" and the portal kept reporting no preference. The patch
  points each call at the `gsettings-desktop-schemas` directory directly.

Idle timeouts are no longer a sed: `kraneIiIdle` (in
`modules/home/ii-settings.nix`) runs ii's `hypridleconfigurator.py` with the
values from `krane.hypr.idle`, `idleTimeouts = false` (all zeros) or the
settings window. See "Settings persistence".

`kraneIiHyprReload` (`entryAfter [ "kraneIiOverrides" "kraneIiPatches" ]`)
runs `hyprctl reload config-only` once the `~/.config/hypr` tree and our
overrides are fully written. `copyIllogicalImpulseConfigs`'s `rm -rf` + `cp -r`
is non-atomic, so a running Hyprland can reload mid-copy on the first inotify
event, hit `module 'hyprland.lib' not found`, and latch emergency mode (no
binds) until the next explicit reload — this entry is that reload. It works
both interactively, where `HYPRLAND_INSTANCE_SIGNATURE` is already set, and
under `nixos-rebuild switch`'s `home-manager-krane.service` (logs as
`hm-activate-krane`), where it isn't, by scanning `$XDG_RUNTIME_DIR/hypr` for
a candidate instance directory. The reload itself is the liveness test, each
candidate socket dir is tried until one answers; a stale dir from a crashed
instance is skipped. No-op when no Hyprland instance is running.

### Preserved files

`kraneIiSaveFishVars` (runs after `writeBoundary` and before `copyIllogicalImpulseConfigs`) and
`kraneIiRestoreFishVars` (runs after `copyIllogicalImpulseConfigs`)
save and restore `~/.config/fish/fish_variables` around the copy step.
That file holds fish's universal variables, including
`__fish_initialized`; the copy step's `rm -rf` wipes it, which retriggers
fish's 4.3 upgrade notice and `conf.d/fish_frozen_key_bindings.fish` on
every new terminal after each activation. The backup lives at
`~/.local/state/krane/fish_variables`.

## Backported fork fixes

`patches/ii/` holds one `git format-patch` series per sub-project:
`01-fixes` (fixes from [pctrade/end4-pC](https://github.com/pctrade/end4-pC)),
then `02-translator`, `04-agents`, `05-settings`, `06-notifications` and
`07-idle` as they land (`05-settings` is not present yet).
`lib/mk-host.nix` applies them with `applyPatches`, after the cheatsheet
patch, to build the `dots-hyprland-patched` source the soymou module copies:
directories in lexical order, and the files in each directory in lexical
order, which is commit order. The table below covers `01-fixes`. Each patch's commit message records the fork
commit, the problem, how it was ported and when to drop it.

| Patch | Fork commit | Port | Drop when |
|---|---|---|---|
| `0001` thumbnail temp file + `mv` | `05b50d9` | clean, $tmp escaping fixed | pinned `ThumbnailImage.qml` writes via a temp file |
| `0002` notification discard freeze | `6f1dc5f` | clean | pinned `Notifications.qml` no longer uses `list.splice()` to discard |
| `0003` corrupt notifications file | `2cf76f8` | clean | pinned `Notifications.qml` wraps the file `JSON.parse` in try/catch |
| `0004` null notification timer | `342a45b` | clean | pinned `cancelTimeout` checks for null |
| `0005` undefined notification action | `eb76c3d` | clean | pinned `attemptInvokeAction` checks for undefined |
| `0006` materialyoucolor key name | `3dad196` | clean | pinned `generate_colors_material.py` reads `primaryPaletteKeyColor` |
| `0007` BlueZ connected state | `d116eef` | hand-ported | bluez#2485 fixed, or pinned `BluetoothStatus.qml` counts `batteryAvailable` |
| `0008` Hyprland IPC throttle | `1b51f7a` (+ `204f22f` intent) | hand-ported, routing widened | pinned `HyprlandData.qml` throttles or coalesces `onRawEvent` |
| `0009` trust on Always connect | `local` | local | pinned `BluetoothDeviceItem.qml` trusts devices it pairs |
| `0010` thumbnail hash for symlinked wallpapers | `local` | local | pinned thumbnail scripts hash the listed path, not its realpath |
| `0011` unterminated OSC in terminal sequences | `local` | local | pinned `sequences.txt` ends with `ESC \` |

`0008`: coalesces bursts of raw Hyprland events (a drag fires dozens) into
hyprctl queries with a leading-edge throttle. The first event flushes
immediately; after that, at most one round runs per 60ms. A query still
running when the timer ticks is never killed; its pending flag retries on
the next tick instead of restarting it.

`0009` to `0011` are not fork backports. `0009`: ii's sidebar registers no
BlueZ agent, so pairing needs one running (the `bluetooth-agent` root system
service in `modules/nixos/desktop/bluetooth.nix`, bound to `bluetooth.service`;
check with `systemctl status bluetooth-agent`), and even then a
paired-but-untrusted device makes BlueZ ask that agent to authorize every
profile connection. `0009` sets `trusted` right after `pair()` so audio
reconnects stop dropping. The agent has no pin file, so legacy PIN-only
devices and pairings the remote device starts are refused; pairing started
from ii (Just Works) still works.

`0010`: `generate-thumbnails-magick.sh` hashed
`realpath "$src"`, the symlink target, while the wallpaper selector's
`ThumbnailImage` hashes the path as listed; home-manager's wallpaper symlinks
into `/nix/store` made every thumbnail miss. `0010` hashes `realpath -s "$src"`
instead, which resolves `.`/`..` and makes the path absolute but leaves
symlinks unresolved.

`0011`: `applycolor.sh` writes the filled-in `sequences.txt` into every
`/dev/pts/N`, and the template's last OSC (708) ended with a bare `ESC`
instead of `ESC \`. kitty then stayed inside that OSC and discarded the
foreground program's output until a later terminator arrived: Neovim looked
frozen, and its exit sequences, including the kitty keyboard-protocol pop,
were lost, so the shell afterwards got every key on press and on release.
`0011` appends the missing `\`.

At the pin, the wallpaper selector does not use `ThumbnailImage`'s own
generation (`generateThumbnail: false` in `WallpaperDirectoryItem.qml`), so
`0001` has no effect until something enables it.

Not portable: `37a9fab` (optimizes CPU-temperature and disk readers that the
pinned `ResourceUsage.qml` does not have), `204f22f` as its own patch (it
changes only a fork-only settings component) and `9c7b0e1` (the pinned
`Background.qml` wallpaper is a `StyledImage`, which already decodes at the
rendered size times the device pixel ratio; the fork's other hunks touch
fork-only files or a fork-only config key).

### Translator (`02-translator`)

The left sidebar's Translator tab, restyled after the fork (input box,
centred source/swap/target row, output box, surfaces tinted from the
wallpaper palette), plus five fixes the fork lacked: pill hover feedback,
scrolling inside each box, selectable output text, a swap that also exchanges
the texts, and a paste icon that keeps a fixed colour instead of greying
out with the clear button.

| Patch | Fork commit | Port | Drop when |
|---|---|---|---|
| `0001` null-safe character counter | `966162c` (`TextCanvas.qml` hunk) | clean | pinned `TextCanvas.qml` counter reads `inputLoader.item?.text` |
| `0002` restyle with swap button | `4da3e83` + `c7aaeb5` + `6868389` (translator hunks) | hand-ported | never; revisit if upstream restyles `Translator.qml` |
| `0003` enable by default | none | new | upstream defaults `sidebar.translator.enable` to `true` |
| `0004` selectable output | none | new | pinned `TextCanvas.qml` output area is selectable |
| `0005` swap texts with languages | none | new | pinned `Translator.qml` swap exchanges the texts |
| `0006` paste icon keeps a fixed colour | none | new | pinned `Translator.qml` paste icon colour no longer depends on `deleteButton.enabled` |

The `0003` default only reaches hosts whose `config.json` has no
`sidebar.translator.enable` key yet (a fresh host). ii saves its whole
options tree, so a host where ii has already run holds an explicit `false`:
turn the translator on once in Settings, Interface, "Enable translator", or
from a terminal with bash (ii applies it live; `--indent 4` keeps ii's own
formatting):

```sh
bash -c 'f=~/.config/illogical-impulse/config.json; jq --indent 4 ".sidebar.translator.enable = true" "$f" > "$f.tmp" && mv "$f.tmp" "$f"'
```

Not ported: `9f63cce`, which hardcodes `trans -e bing`; Bing rejects the
default `auto` source and target.

### Agents (`04-agents`)

New work, not from the fork: a left-sidebar Agents tab that lists Claude Code
sessions (spec: `docs/superpowers/specs/2026-09-27-ii-agent-overview-design.md`;
usage under "Claude Code" below).

| Patch | Adds | Drop when |
|---|---|---|
| `0001` ClaudeAgents service | `services/ClaudeAgents.qml`, `services/claude-agents.js`, `scripts/claude/agents.sh`, config `sidebar.agents.enable` (default `true`) | pinned ii ships an equivalent agents tab, or `claude agents --json` is removed |
| `0002` Agents tab | `modules/ii/sidebarLeft/Agents.qml`, `agents/AgentRow.qml`, tab and polling switch in `SidebarLeftContent.qml` | same as `0001` |
| `0003` group by directory | grouping in `claude-agents.js` (`annotate`'s `group`/`groupStart`, `tildePath`), header rendering in `agents/AgentRow.qml` | same as `0001` |
| `0004` normalize group paths | `normalizePath` in `claude-agents.js`, used by `tildePath`/`groupLabel` so `annotate` groups on one normalized cwd per session and normalizes home once | same as `0001` |

Tests, runnable against the clone (default) or a built source:

```sh
bash scripts/ii-agents/test-agents-sh.sh [<ii root>]
node scripts/ii-agents/test-logic.mjs [<ii root>]
```

`<ii root>` is `…/dots/.config/quickshell/ii`, for example inside the
`dots-hyprland-patched` store path.

### Notifications (`06-notifications`)

| Patch | Fork commit | Port | Drop when |
|---|---|---|---|
| `0001` start expanded when flagged `x-ii-expanded` | `local` | local | pinned `NotificationGroup.qml`'s `expanded` default reads a per-notification hint |

A notification popup starts collapsed unless its sender set the
`x-ii-expanded` hint, which `scripts/flake-update-notify.sh` does so its
action buttons are visible without a right-click.

### Idle (`07-idle`)

| Patch | Fork commit | Port | Drop when |
|---|---|---|---|
| `0001` keep awake by default and across reboots | `local` | local | pinned `Idle.qml` restores `states.idle.inhibit` on a new Hyprland instance and defaults it to `true` |
| `0002` re-arm the inhibitor once its surface is mapped | `local` | local | Hyprland rechecks idle inhibitors when a layer surface maps |
| `0003` also hold a logind idle lock while Keep awake is on | `local` | local | Hyprland counts layer-surface inhibitors regardless of the layer's alpha |

Upstream resets "Keep awake" to off on every new Hyprland instance, so it
never survives a reboot. `0001` defaults it to on and always restores the
saved value from `~/.local/state/quickshell/states.json`.

`0002`: Quickshell creates the inhibitor before its layer surface is mapped,
Hyprland counts it as not visible and only rechecks on window or focus
events, so "Keep awake" could stay ineffective after login. The patch
recreates the inhibitor once, 3 s after start.

`0003`: Hyprland also ignores the inhibitor while its layer's alpha is zero,
which happens during the fade-in and whenever a fullscreen window covers the
monitor, so hypridle could still lock with "Keep awake" on. While it is on,
`Idle.qml` also runs `systemd-inhibit --what=idle ... cat`, an idle lock that
hypridle honours on its own. `cat` exits on stdin EOF, so the lock goes away
when the toggle turns off or Quickshell exits.

### Workflow

The clone at `~/src/dots-hyprland` is a disposable workspace; the patch files
are the source of truth. One local branch, `krane`, holds every sub-project's
commits in order. A lightweight tag `krane/<dir>` (for example
`krane/01-fixes`) marks the last commit of each sub-project; the tags exist
only in the clone and are recreated by the apply loop. `git rerere` records
each conflict resolution so the next pin bump replays it.

`git switch -C krane "$PIN"` below force-resets `krane` to the pin, discarding
any commits on it that are not yet reflected in `patches/ii/`. Only run it on
a fresh clone, or once `krane` is fully exported; the apply block below warns
if `krane` already exists.

```sh
PIN=$(jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock)
git clone https://github.com/end-4/dots-hyprland ~/src/dots-hyprland   # once
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
# apply every series in order and tag the end of each
for d in ~/.dotfiles/patches/ii/*/; do
  git am -3 "$d"*.patch || break   # on a conflict: resolve, `git am --continue`, tag, resume from the next directory
  git tag -f "krane/$(basename "$d")"
done
```

A new sub-project creates its `patches/ii/NN-<name>/` directory and tags its
last commit `krane/NN-<name>` before exporting. Nothing in `lib/mk-host.nix`
changes.

On a pin bump, run `nix flake update dots-hyprland` first, then the same
apply block. `git am -3` stops at a conflict; resolve it with git's tools and
run `git am --continue`. A patch that no longer applies otherwise fails the
`applyPatches` build, and `nixos-rebuild` names the file.

Add, edit or drop commits with ordinary git commands, then move any tag whose
commit was rewritten (tags do not follow a rebase). Then export every series
again:

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

To remove one fix, drop its commit (`git am --skip` while re-applying, or
`git rebase -i` afterwards) and export again. Deleting a patch file directly
only works when no later patch changes the same file. Stage `patches/ii`
(`git -C ~/.dotfiles add patches/ii`) before running `nixos-rebuild`: it reads
the flake's git tree, so an unstaged patch edit has no effect on the build.
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

## Settings persistence

`patches/ii/05-settings` ports pctrade/end4-pC's settings pages (at
`dc2ca2600ee6`) into ii's standalone settings window (`SUPER + I`). Every
control either persists in this repo or was removed. The rule: persist
choices, derive consequences.

| Kind | Source of truth | Live apply |
|---|---|---|
| ii shell options | `hosts/<host>/illogical-impulse/config.json`, through the `~/.config/illogical-impulse` symlink | ii's own file watcher |
| Hyprland options (`hl.config` keys) | `hosts/<host>/ii-settings.json`, `hyprland` | writer re-renders `custom/krane_gui.lua`, `hyprctl reload config-only` |
| Monitor fields | `hosts/<host>/ii-settings.json`, `monitors` | same file, full reload, confirm-or-revert |
| Idle timeouts | `hosts/<host>/ii-settings.json`, `idle`, or `krane.hypr.idle` | writer edits `hypridle.conf`, restarts hypridle |
| Animation preset | `hosts/<host>/ii-settings.json`, `animationPreset` | `require("hyprland.animationPresets.<name>")` in `krane_gui.lua` |
| Border colors | config.json, `hyprland.general.borderColor` (roles and opacity) | resolved from the palette into `shellOverrides/main.lua` |
| Hyprlock 12h clock | config.json, `time.format` | `shell.qml` seds `hyprlock.conf` on ready, on change and on every reload |

### One owner per key

Nix owns every key it sets: each `krane.hypr.settings` leaf, every entry of
`krane.hypr.guiLocked`, the non-null fields of each `krane.hypr.monitors`
entry (`output`, `mode`, `position`, `scale` and `disabled` always), and
`idle` when `krane.hypr.idle` or `idleTimeouts = false` is set. The settings
window shows those controls disabled with "Set in Nix", and
`krane-ii-settings` refuses them. Every other key in
`pkgs/krane-ii-settings/schema.json` belongs to the GUI file. A key in
both places fails evaluation, naming both files: delete it from one. To hand
a key to the GUI, delete it from `display.nix` in the same commit that adds
it to `ii-settings.json`. Keyboard layout stays in Nix because
`qwertz-binds.nix` depends on it.

Only keys in `schema.json` can be written; each was checked against
Hyprland 0.56's source. Adding one means checking it the same way (Task 12
of `docs/superpowers/plans/2026-09-27-ii-settings.md`).

### The writer

`krane-ii-settings` (`pkgs/krane-ii-settings`, on `PATH` with this host's
manifest) is the only writer of `ii-settings.json`:

- `set` / `reset <section> <key>`: validate, write the repo file atomically
  under a lock, re-render the live file, reload. It never creates the repo
  file and refuses to write one it cannot parse. If Hyprland reports an error
  in `krane_gui.lua` after the reload, it restores both files.
- `apply`: re-render the live file from the repo file, after a hand edit or a
  `git checkout`. The settings window offers the same as "Apply now" when it
  sees the file change; nothing is applied on its own.
- `try monitor …` / `confirm`: a display change is live at once, and a
  transient systemd timer (`krane-ii-settings-revert`, 15 s) reverts it
  unless Keep is pressed. The previous live file is kept aside so the revert
  never depends on the repo file being readable. While the timer is pending,
  the Displays page disables every control until Keep or Revert. Kept
  changes carry `bootConfirmed: false`; `boot-check` (run at login) waits
  for the session to lock then unlock, re-arms the same timer and asks
  again. If it is not kept before the timer runs out, `revert-unconfirmed`
  deletes the whole `monitors.<output>` entry, not just the changed fields.
  `confirm` validates the repo file and the merge before it stops the
  timer, so a repo file it cannot read or a rejected merge leaves the timer
  armed and the change still reverts.
- `get`: the state the settings window shows.

The GUI never commits. `config.json` changes on every wallpaper switch
(`wallpaperPath`), so `git status` shows it often; commit selectively.
`ai/` and `*.tmp` are ignored; `actions/` and `presets/` are tracked.
Read a host's whole `config.json` before committing it for the first time:
it can hold the weather city, a booru username and AI endpoints.

### Hotplug and reload: KRANE_GUI_MONITORS

A host's `display.nix` can define `extraMonitorsLua` to re-send a monitor
rule outside the GUI's own `monitors.<output>` block, for example to keep a
laptop panel scaled correctly as external monitors come and go. That Lua
runs with only the fields `display.nix` itself knows: `output`, `mode`,
`position` and `scale`. Fields the settings window owns (transform, VRR,
color management, HDR) are not in scope there, so a naive re-send would
silently drop them on every hotplug or `hyprctl reload`.

The writer renders a `KRANE_GUI_MONITORS` Lua global into `custom/krane_gui.lua`
alongside each `hl.monitor({...})` call, keyed by output name, holding the
full rendered rule it just sent to Hyprland — `output`, `mode`, `position`
and `scale` included, alongside every GUI-owned field. The `monitors.lua`
trailer requires `custom/krane_gui.lua` last, then calls `krane_after_gui()`
if the host defined one (`modules/home/hypr-config.nix`'s `monitorsFile`).
A host that needs its `extraMonitorsLua` to survive hotplug sets
`krane_after_gui` to a function that merges `KRANE_GUI_MONITORS[output]`
into each rule it re-sends before calling `hl.monitor`, skipping `output`,
`mode`, `position` and `scale` itself so Nix's own computed values for
those fields are not clobbered by the GUI's last-rendered ones.
`hosts/tarmantria/display.nix`'s `scale_internal` is the example: it merges
eDP-1's GUI fields back in, filtering out those four keys, whenever a
monitor is added or removed, so a transform or color change set from the
settings window is not lost on the next hotplug.

### Escape hatches

- A display setting leaves a screen unusable: wait 15 s (the revert timer),
  or unlock blind after a reboot and wait 15 s (the boot check).
- That fails too: from a TTY, remove the `monitors.<output>` entry from
  `hosts/<host>/ii-settings.json` and switch. Faster, until the next switch:
  `rm ~/.config/hypr/custom/krane_gui.lua && hyprctl reload` drops every GUI
  delta.
- The repo file is broken (merge conflict): the settings window says so and
  writes nothing. Fix the file, then `krane-ii-settings apply`.

### Ported and dropped controls

Ported pages: Quick, General, Bar, Background, Interface, Services, Profile,
Hyprland, About (plus upstream's Advanced, kept). Fork widgets, models and
services added: 15 (`AboutCard`, `AndroidClock`, `Carousel`,
`ColorSelectionArray`, `ConfigComboBox`, `ConfigTextArea`, `GroupedList`,
`WorldMap` with `WorldMapDots.js` and `WorldCities.js`, `PresetsCard`,
`PresetPopup`, `AutostartApps`, `MonitorCanvas`, `MonitorRect`, the
`MonitorConfigOption` model and the `Presets` service). Not taken: the fork's
`MaterialSymbol`, `StyledImage` and `Fonts` (they need font files the pin does
not ship, or only remove pin behaviour), and `ConfigSelectionShapeArray`,
`LayoutSection` and `WidgetsMonitorSelector` (only dropped controls used them).
Not ported: the Niri page, the fork's panel-style settings overlay, About's
"Update dots" and "System update", Profile's hostname editing and online
presets.

| Page | Control (section) | Key | Reason |
|---|---|---|---|
| General | Show date (Time) | `time.showDate` | fork-only feature |
| Bar | Bar layout (whole section) | `bar.layouts.{leftLayout,middleLayout,rightLayout}` | fork-only feature |
| Bar | Group Color (Positioning & Styles) | `bar.groupColor` | fork-only feature |
| Bar | Show Frame, Overlap windows when center-only, Follow Frame Color, Frame thickness, Frame Color (Positioning & Styles) | `bar.showFrame`, `bar.centerOnlyReserveFrame`, `bar.followFrameColor`, `bar.frameThickness`, `bar.frameColor` | fork-only feature |
| Bar | Dynamic Island (whole section: Left widget, Right widget, Visualizer style, Show media controls) | `bar.dynamicIsland.*` | fork-only feature |
| Bar | Popup position (Notifications) | `notifications.position` | fork-only feature |
| Bar | Divider (whole section: Style, Space width) | `bar.divider.{style,spacing}` | fork-only feature |
| Bar | Wallpapers Toggle (Utility buttons) | `bar.utilButtons.showWallpaperToggle` | fork-only feature |
| Bar | Indicator style (Workspaces) | `bar.workspaces.indicatorStyle` | fork-only feature |
| Bar | CPU Temperature, RAM, Disk, Style, Show Percentage (Resources) | `bar.resources.{alwaysShowCpuTemp,alwaysShowRam,alwaysShowDisk,style,showValue}` | fork-only feature |
| Bar | Media (whole section: Preferred Player, Pin media controls, Show only title, Max media width) | `bar.media.*` | fork-only feature |
| Bar | Tooltips (whole section: Enable, Click to show) | `bar.tooltips.enable` | fork-only feature |
| Background | Lock-screen half of the wallpaper carousel, Use same wallpaper for both (Wallpaper) | `background.lockWall` | fork-only feature |
| Background | Preview wallpaper, Blur wall, Blur Size, Split blur amount, Split blur side, Transitions (Wallpaper) | `background.{enableWallpaperPreview,showBlur,blurRadius,splitRatio,splitSide,wallpaperAnimation}` | fork-only feature |
| Background | Wallpaper change interval (Wallpaper) | `wallpaperSelector.changeInterval` | fork-only feature |
| Background | Centered wallpaper (whole subsection: Enable, Show only when locked, shape, Background Color, Size) | `background.centeredWallpaper*` | fork-only feature |
| Background | Automatic colors, Color (Digital clock settings) | `background.widgets.clock.color` | fork-only feature |
| Background | Pixel clock orientation (Pixel Clock Settings) | `background.widgets.clock.pixel.orientation` | fork-only feature |
| Background | Follow Clock Font (Quote) | `background.widgets.clock.quote.followClock` | fork-only feature |
| Background | Custom Image, Visualizer, Text (whole sections) | `background.widgets.{customImage,visualizer,customText}.*` | fork-only feature |
| Background | Show widgets on (Widgets) | `background.screenList` | fork-only feature |
| Background | Image converter, Media, Resources, Calendar, World clock, User card, Notes, Todo, Timers, Sticker entries (Widgets) | `background.widgets.{images,media,resources,calendar,worldClock,userCard,notes,todo,timers,sticker}.enable` | fork-only feature |
| Background | Show alignment grid while dragging, Show snap lines when dropping (Canvas) | `background.{showGrid,showSnapLines}` | fork-only feature |
| Interface | Settings Panel (whole section: Style, Border width, Border Color) | `settings.{style,borderSize,borderColor}` | fork panel-style settings overlay not ported |
| Interface | Background, Media Player, Show Pin Button, Show Apps Button (Dock) | `dock.{showBackground,showMedia,showPinButton,showAppsButton}` | fork-only feature |
| Interface | Enable, Follow Album Colors (Left Sidebar media) | `sidebar.media.{enable,artColors}` | fork-only feature |
| Interface | Banner, Bottom Group, Media Player (Right Sidebar) | `sidebar.{banner,bottomGroup,mediaPlayer}` | fork-only feature |
| Interface | Bottom-left, Bottom-right (hot corners) | `sidebar.cornerOpen.{bottomLeftAction,bottomRightAction}` | fork-only feature |
| Interface | Style (Overview) | `overview.style` | fork-only feature (niri-like overview) |
| Interface | Show Widgets, Show Toolbars, Show media player info (Lock screen) | `lock.{showWidgets,showToolbars,showMedia}` | fork-only feature |
| Interface | Samples (Style: Blurred) | `lock.blur.size` | fork-only feature |
| Interface | Show home directory in quick access, Close after selection, Show blur background, Columns in grid view, Wallpaper change interval, Always show search bar, Custom Wallpaper Folder, Live Wallpaper Folder (Wallpaper selector) | `wallpaperSelector.{showHomePath,closeAfterSelection,showBlurBackground,columns,changeInterval,showSearchbar,userPath,liveWallpapersPath}` | fork-only feature |
| Services | Icons, Keybinds (Prefixes) | `search.prefix.{symbols,keybinds}` | fork-only feature |
| About | Packages, Updates cards; Update Dots, System update buttons | none | pacman-only / out of scope (spec) |
| Profile | Online presets; hostname editing (shown read-only) | `profile.onlinePresets` | out of scope (spec) |
| Hyprland | Displays section of the fork's `monitors.lua` writer; "add a require line" notice | none | replaced by `krane-ii-settings` (Design B, C) |

The writer's own test suite (`pkgs/krane-ii-settings/tests`) covers this
behaviour: 53 tests across command validation, the displays confirm-or-revert
flow and the Lua render output.

## Claude Code

### Agents tab

The left sidebar's Agents tab (`patches/ii/04-agents`) lists every Claude
Code session on the machine that has a window or runs in the background:
name, `bg` for background sessions, last activity, and a dot for the state
(error colour and the `waitingFor` reason while a session waits on you, a
pulsing primary colour while busy). Rows are grouped by working directory,
each group under a `~`-relative path header, with the group holding the
most urgent session (waiting, then busy, then idle) listed first. Clicking
a row focuses the session's terminal window on any workspace. For a
background session that no terminal is attached to, it runs `kitty -e
claude attach <id>`. The tab never answers, approves, stops or deletes
anything.

It runs `scripts/claude/agents.sh` (`claude agents --json`, plus the pid
chain up to the terminal and the transcript's mtime; transcript content is
never read) every 3 s, backing off to 15 s when a run is slow. It runs only
while the tab is visible, so a closed sidebar starts no `claude` process.
Sessions whose process has no terminal window (SDK sessions such as the
claude-mem observer, tmux, SSH, TTYs) are hidden and counted as
"headless hidden".

To turn the tab off, use Settings, Interface, "Agents tab", or add
`"sidebar": {"agents": {"enable": false}}` to
`~/.config/illogical-impulse/config.json` (this host's file in the repo, see
"Settings persistence"; not written by Nix).

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

The Agents tab only refreshes while open, so it cannot tell you that a
session is blocked. Claude Code's own terminal notifications do that
(checked 2026-09-30 from ii's notification history (`~/.cache/quickshell/notifications/notifications.json`) with `preferredNotifChannel` unset (`auto`) in
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

## Verifying on the target

See [docs/VERIFY.md](VERIFY.md)'s on-target checklist for the commands,
run after two consecutive `nixos-rebuild switch` runs.

`custom/env.lua` should end up as the soymou module's `PATH`/`XDG_DATA_DIRS`
block, then the sentinel, then our `hl.env` lines. No `QT_QPA_PLATFORMTHEME`
line: `patches/illogical-flake-kde-platformtheme.patch` drops the flake's
`qt6ct` override so ii upstream's `kde` value from `hyprland/env.lua` stands.
`custom/general.lua` follows the same pattern with its plugin comment
block in place of the `PATH` fixes.

`patches/illogical-flake-cheatsheet-fkeys.patch` fixes the cheatsheet's
number-key collapsing logic, which used a bare digit-substring test and so
also matched F-keys containing a "1" (F1, F10, F11) and dropped F9 (digit
9, no "1"); it now only collapses keys that are purely digits.

## Rollback and escape hatches

- UWSM session misbehaves: set `programs.hyprland.withUWSM = false` in
  `modules/nixos/desktop/desktop.nix`. The plain Hyprland session is already on
  the greeter, so this is a one-line, one-rebuild rollback.
- Autologin/lock-on-start misbehaves: `systemctl restart greetd` gives you
  tuigreet back, not another autologin, because greetd's
  `/run/greetd.run` runfile blocks a second autologin within the same
  boot.
- A single override misbehaves: delete the option value. The next
  switch re-renders the file without it. Appended files need no
  hand-editing, since the copy step recreates them from scratch and our
  step replaces everything from the sentinel down.
- The soymou module breaks or goes stale: it is a single-maintainer
  flake, and `copyIllogicalImpulseConfigs` is an internal name this repo
  asserts on. [FALLBACK-VENDORING.md](./FALLBACK-VENDORING.md) documents
  vendoring `dots-hyprland` directly and replacing the copy step,
  keeping `krane.hypr.*` and this DAG entry unchanged.
- Updating either input: `nix flake update dots-hyprland illogical-flake`
  is a reviewed change, not routine maintenance. Re-check the wipe-set
  table, the sourcing order, and that `copyIllogicalImpulseConfigs`
  still exists, then test two consecutive switches on the target.
