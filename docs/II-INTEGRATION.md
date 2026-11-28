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
  not abort on that collision. `*.hm-bak` files after a switch are normal;
  find them with `find ~ -name '*.hm-bak'` and delete them once checked.
- Fish customisation lives in NixOS `programs.fish.*` (`/etc/fish/...`,
  `modules/nixos/common/shells.nix`), outside `$HOME`, never in home-manager.

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
| `custom/keybinds.lua` | owned | Upstream ships one bind, `CTRL+SUPER+ALT+Slash` ("Edit user keybinds"), which is dropped. Add it back through `krane.hypr.binds` if missed. |
| `custom/execs.lua` | owned | Upstream ships it empty. |
| `custom/rules.lua` | owned | Upstream ships it empty. |
| `custom/env.lua` | appended | Truncated with `cat >` every switch. Our block must land after. |
| `custom/general.lua` | appended | The soymou module appends its `hl.plugin` block. Our block must land after. |
| `custom/krane_gui.lua` | owned | Rendered from `hosts/<host>/ii-settings.json` by `modules/home/desktop/ii-settings.nix`; rewritten live by the settings window. Required last by `monitors.lua`. |

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
is written, so a stale block self-corrects. The sentinel is
`-- >>> krane overrides >>>`, appearing exactly once after a switch since
the copy step recreates both files first. More than once means the drop
failed. The block is written even when the rendered body is empty, so every
host's `custom/env.lua` ends in the sentinel.

The append runs from a store script, not a plain redirect: a redirection
cannot be prefixed with `$DRY_RUN_CMD` and would still fire in dry-run
mode. Every tool used is an absolute store path, so activation does not
depend on the user's `PATH`.

## Dry runs are not read-only

This repo's steps honour `$DRY_RUN_CMD`, but the soymou module's
`cat > custom/env.lua` and `cat >> custom/general.lua` do not. A
`home-manager switch -n` or `nixos-rebuild dry-activate` really truncates
`custom/env.lua`, destroying our block, and appends another plugin block to
`custom/general.lua`. The next real switch recreates both. Do not inspect
`general.lua` after dry runs and conclude the append is broken; run a real
`nixos-rebuild switch` if you need the files correct now.

## How ii sources Lua

From `dots/.config/hypr/hyprland.lua` at the pinned revision:

```
hyprland.lib -> hyprland.services -> hyprland.env -> custom.env
  -> hyprland.execs -> hyprland.general -> hyprland.rules
  -> hyprland.colors -> hyprland.keybinds
  -> custom.execs -> custom.general -> custom.rules -> custom.keybinds
  -> workspaces.lua -> monitors.lua -> hyprland.shellOverrides.main
```

- `custom/variables.lua` is not in that chain. It is sourced from
  `hyprland/keybinds.lua`, right after `hyprland/variables.lua`, which
  makes it the place to override `terminal`, `fileManager`, `browser` and
  the other Lua globals that hold shell command strings, not package paths.
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
runs `luac -p` over every rendered file of every desktop host.

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
  `modules/nixos/common/shells.nix` aliases `cat` to `bat --color=always`,
  which would print a bat frame instead of the raw OSC sequences.
- `~/.config/hypr/hyprland/keybinds.lua`:
  `s|killall ydotool qs quickshell|killall ydotool; pkill -f '[q]s-wrapped -c ii'|`.
  The nix-wrapped quickshell's comm is truncated to `.quickshell-wra`, so
  `killall qs quickshell` never matched and every restart-widgets press
  stacked a new `qs` instance.
- `~/.config/quickshell/ii/modules/common/Config.qml`:
  `s/property bool launchOnStartup: false/property bool launchOnStartup: true/`.
  Every host autologins via greetd straight into Hyprland
  (`modules/nixos/desktop/desktop.nix`), so ii must lock on startup. Only
  fresh hosts seed `config.json` from this default; after that the value
  lives in the host's `config.json` and the settings window can turn it off.
- `~/.config/quickshell/ii/scripts/colors/switchwall.sh`:
  `s#gsettings \(set\|get\) org.gnome.desktop.interface#GSETTINGS_SCHEMA_DIR=<schemas> <store gsettings> \1 org.gnome.desktop.interface#g`.
  The ii session has no gsettings schemas on `XDG_DATA_DIRS`, so the
  dark/light toggle never reached the portal; each call gets the
  `gsettings-desktop-schemas` directory directly.

Idle timeouts are not a sed: `kraneIiIdle` (in
`modules/home/desktop/ii-settings.nix`) runs ii's `hypridleconfigurator.py` with the
values from `krane.hypr.idle` or `idleTimeouts = false` (all zeros). See
"Settings persistence".

`kraneIiHyprReload` (`entryAfter [ "kraneIiOverrides" "kraneIiPatches" "kraneIiActivate" ]`)
runs `hyprctl reload config-only` once the `~/.config/hypr` tree, our
overrides and the GUI render are fully written. `copyIllogicalImpulseConfigs`'s
`rm -rf` + `cp -r` is non-atomic, so a running Hyprland can reload mid-copy,
hit `module 'hyprland.lib' not found`, and latch emergency mode (no binds)
until the next explicit reload; this entry is that reload. Under
`nixos-rebuild switch`'s `home-manager-krane.service` there is no
`HYPRLAND_INSTANCE_SIGNATURE`, so it tries each socket dir under
`$XDG_RUNTIME_DIR/hypr` until one answers; a stale dir from a crashed
instance is skipped. No-op when no Hyprland instance is running.

### Preserved files

`kraneIiSaveFishVars` (runs after `writeBoundary` and before `copyIllogicalImpulseConfigs`) and
`kraneIiRestoreFishVars` (runs after `copyIllogicalImpulseConfigs`)
save and restore `~/.config/fish/fish_variables` around the copy step.
That file holds fish's universal variables, including
`__fish_initialized`; the copy step's `rm -rf` wipes it, which retriggers
fish's 4.3 upgrade notice and `conf.d/fish_frozen_key_bindings.fish` on
every new terminal after each activation. The backup lives at
`~/.local/state/krane/fish_variables`. A `set -U` between save and wipe
is lost.

## Backported fork fixes

`patches/ii/` holds one `git format-patch` series per sub-project:
`01-fixes`, `02-translator`, `04-agents`, `05-settings`, `06-notifications`,
`07-idle`, `08-bar-popouts`, `09-end4pc-fixes` and `10-icon-picker`. `lib/mk-host.nix` applies
them with `applyPatches`, after `patches/illogical-flake-cheatsheet-fkeys.patch`,
to build the `dots-hyprland-patched` source the soymou module copies:
directories in
lexical order, files in each directory in lexical order, which is commit
order. Each patch's commit message records the problem, the port and, for
most, when to drop it.

A patch must not change or add text that a `kraneIiPatches` sed matches: the
sed would silently stop matching or rewrite the patch's own code. The line at
risk is `property bool launchOnStartup: false` in `Config.qml`; no patch
touches it today (`05-settings/0013` only binds the setting in the Interface
page). A patch that has to change such a line takes over the sed's job, and
the sed entry goes in the same commit.

### `01-fixes`

Fixes backported from [pctrade/end4-pC](https://github.com/pctrade/end4-pC)
(`0001` to `0008`) plus local fixes (`0009` to `0011`): thumbnails,
notifications, colors, Bluetooth, and a throttle on raw Hyprland events.
`0009` (trust devices on pair) depends on this repo: ii's sidebar registers
no BlueZ agent, so pairing needs the `bluetooth-agent` root service
(`modules/nixos/desktop/bluetooth.nix`; check with
`systemctl status bluetooth-agent`). Only pairing started from ii works.

### `02-translator`

The left sidebar's Translator tab, restyled after the fork, plus fixes the
fork lacked. `0003` enables it by default; a patch, not a sed, because
`property bool enable:` occurs many times in `Config.qml`.

The `0003` default only reaches hosts whose `config.json` has no
`sidebar.translator.enable` key yet. ii saves its whole options tree, so a
host where ii has already run holds an explicit `false`: turn it on once in
Settings, Interface, "Enable translator", or from a terminal (ii applies it
live; `--indent 4` keeps ii's formatting):

```sh
bash -c 'f=~/.config/illogical-impulse/config.json; jq --indent 4 ".sidebar.translator.enable = true" "$f" > "$f.tmp" && mv "$f.tmp" "$f"'
```

### `04-agents`

New work, not from the fork: the left-sidebar Agents tab (usage under
"Claude Code" below). Tests, runnable against the clone
(default) or a built source:

```sh
bash scripts/ii-agents/test-agents-sh.sh [<ii root>]
node scripts/ii-agents/test-logic.mjs [<ii root>]
```

`<ii root>` is `…/dots/.config/quickshell/ii`, for example inside the
`dots-hyprland-patched` store path.

### `05-settings`

The settings port; see "Settings persistence".

### `06-notifications`

`0001`: a notification popup starts collapsed unless its sender set the
`x-ii-expanded` hint, which `scripts/flake-update-notify.sh` does so its
action buttons are visible without a right-click. Drop when pinned
`NotificationGroup.qml` reads a per-notification expanded hint.

### `07-idle`

"Keep awake" defaults to on and survives reboots. `0003`: while "Keep awake" is
on, `Idle.qml` also runs `systemd-inhibit --what=idle ... cat`, an idle lock
hypridle honours. `cat` exits on stdin EOF, so the lock goes away when the
toggle turns off or Quickshell exits.

### `08-bar-popouts`

Clicking the network, Bluetooth, speaker or mic bar icon opens a popout for that
icon instead of the right sidebar. `0001`: the volume dialog content gets a
mute button and a master slider, so the sidebar dialogs, the overlay mixer and
the popouts share them. `0002`: Wi-Fi and Bluetooth dialog content move into
their own files, a per-screen popout window with its own focus grab
(`BarIconPopout.qml`) is added, and `bar.iconPopouts` (default `true`)
controls it and keeps the speaker and mic icons always visible. With it off,
indicator clicks open the sidebar and the speaker and mic icons show only when
muted.

### `09-end4pc-fixes`

Later [pctrade/end4-pC](https://github.com/pctrade/end4-pC) fixes on top of
`08`, one commit each; each message names the fork commit it ports. Not
ported: the other hunks of `e3bb865`, the proxy-mask half of `18b00f2`, and
the fork's `SidebarRightContent.qml` and `RegionSelector.qml` hunks. `d6c8d5d`
is a reimplementation: the fork commit patches files that do not exist here.

### `10-icon-picker`

Settings, Bar, "Left sidebar button" picks the icon of the left sidebar button, its color and an optional folder of icons. The keys sit under `bar` in `config.json`: `topLeftIcon` (a bare built-in name, to which the button appends `-symbolic`; the file name as is for an icon from the custom folder; or `distro` for the OS logo), `topLeftIconColor` (a color role such as `primary`; empty is the theme color) and `topLeftIconsPath` (a folder of `.svg` and `.png` files, `~` allowed; empty is `assets/icons`). Changing the folder does not migrate `topLeftIcon`: pick the icon again. The button also shows when only the Agents tab is enabled. Drop when pinned ii has an icon picker for this button.

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

Stay with patch series: a private fork as a flake input would have to be
fetchable, with credentials, everywhere the flake is evaluated (every host,
root's nix daemon, the `just check` container, `install.sh` on a fresh
machine before sops can decrypt anything). Re-evaluate a
private fork of dots-hyprland as the flake input if:

- a pin bump needs more than 5 hand-resolved conflict hunks, or more than one
  sitting; or
- a private remote exists that every host and the docker check can already
  reach; or
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
| Monitor fields | `hosts/<host>/ii-settings.json`, `monitors`, over the `krane.hypr.monitors` baseline | same file, full reload, confirm-or-revert |
| Idle timeouts | `hosts/<host>/ii-settings.json`, `idle`, over the `krane.hypr.idle` baseline | writer edits `hypridle.conf`, restarts hypridle |
| Animation preset | `hosts/<host>/ii-settings.json`, `animationPreset` | `require("hyprland.animationPresets.<name>")` in `krane_gui.lua` |
| Border colors | config.json, `hyprland.general.borderColor` (roles and opacity) | resolved from the palette into `shellOverrides/main.lua` |
| Hyprlock 12h clock | config.json, `time.format` | `shell.qml` seds `hyprlock.conf` on ready, on change and on every reload |

GUI values live in their own file, `custom/krane_gui.lua`, not merged into
`custom/general.lua`. Resetting a key then just removes it from that file, and
a `config-only` reload brings the Nix or upstream value back without a switch.

### One owner per key

Nix locks only each `krane.hypr.settings` leaf, every entry of
`krane.hypr.guiLocked` and each monitor's `output`. The settings window shows
those controls disabled with "Set in Nix", and `krane-ii-settings` refuses
them. Every other key in `pkgs/krane-ii-settings/schema.json` belongs to the
GUI file. A `settings` or `guiLocked` key also in `ii-settings.json` fails
evaluation, naming both files: delete it from one. To hand a key to the GUI,
delete it from `display.nix` in the same commit that adds it to
`ii-settings.json`.

Everything else Nix sets is a default the GUI may override:

- `krane.hypr.monitors`: every field of an entry (`mode`, `scale`, `disabled`,
  `transform`, `vrr`, ..., `position`) is the monitor's baseline in the manifest.
  A GUI value in `monitors.<output>` wins; resetting the field removes it and
  the Nix value applies again. `position` is null in every host's
  `display.nix`, and a host with a fixed layout keeps it in `ii-settings.json`
  (one without, such as taractias, renders `auto`). A position depends on the
  neighbours' scale, so after changing a scale, re-drag the positions.
- `krane.hypr.idle` and `idleTimeouts = false` (0/0/0): the idle baseline. The
  effective idle values are the baseline overlaid with the GUI's `idle`.
- `krane.hypr.defaults` (same shape as `settings`): rendered into
  `custom/general.lua`, not locked. `custom/krane_gui.lua` loads later
  (`monitors.lua` is required after `custom/general.lua`), so a GUI value wins;
  resetting the key removes it from that file and the next reload brings the
  default back. The hosts' `input.kb_layout` and `kb_variant` live here.
  `qwertz-binds.nix` assumes `kb_layout = "at"`, so a GUI layout change leaves
  those binds wrong.

Only keys in `schema.json` can be written. To add one, check the key in
Hyprland's source for the pinned version, then list it in `schema.json` with
its type and range.

### The writer

`krane-ii-settings` (`pkgs/krane-ii-settings`, on `PATH` with this host's
manifest) is the only writer of `ii-settings.json`:

- `set` / `reset <section> <key>`: validate, write the repo file atomically
  under a lock, re-render the live file, reload. It never creates the repo
  file (an untracked file is invisible to flake evaluation, so a new one would
  not persist) and refuses to write one it cannot parse. If Hyprland reports an
  error in `krane_gui.lua` after the reload, it restores both files.
- `apply`: re-render the live file from the repo file, after a hand edit or a
  `git checkout`. The settings window offers the same as "Apply now" when it
  sees the file change; nothing is applied on its own.
- `activate`: run at every home-manager activation (`home.activation.kraneIiActivate`
  in `modules/home/desktop/ii-settings.nix`). home-manager re-runs activation at
  every boot from the last `nixos-rebuild switch`'s build-time render, so
  without this step any GUI change made since that switch would be lost on
  reboot; `activate` re-renders the live file and the idle config from the
  current repo file instead. It runs before Hyprland is up, so it never calls
  `hyprctl`, restarts hypridle or touches the pending file or revert timer.
  It must never fail activation: a missing, unparseable or ownership-rejected
  repo file prints a warning and leaves the build-time render in place. Before
  login `$XDG_RUNTIME_DIR` may not exist yet; the lock then falls back to
  `hosts/<host>/.ii-settings.lock` (git-ignored).
- `try monitor OUTPUT FIELD VALUE … [+ OUTPUT …]` / `confirm`: a display
  change, for one output or several at once (a monitor drag that moves
  others), is live at once, and a transient systemd timer
  (`krane-ii-settings-revert`, 15 s) reverts it unless Keep is pressed.
  The previous live file is kept aside so the revert never depends on the
  repo file being readable. While the timer is pending,
  the Hyprland page disables every section (Displays, Layout, Input, Idle,
  Visual & Aesthetics, Autostart Apps, Animations) until Keep or Revert.
  `confirm` validates the repo file and the merge before it stops the timer,
  so a repo file it cannot read or a rejected merge leaves the timer armed and
  the change still reverts.
- `boot-check` / `revert-unconfirmed`: kept changes carry
  `bootConfirmed: false`. `boot-check` (run at login) waits for the session to
  lock then unlock, re-arms the same timer and asks again. If it is not kept
  in time, `revert-unconfirmed` deletes the whole `monitors.<output>` entry,
  not just the changed fields. Only outputs Hyprland reports connected are
  asked about, and `confirm` and `revert-unconfirmed` act only on the outputs
  the pending boot check listed, so a disconnected output keeps
  `bootConfirmed: false` until it is reconnected.
- `get`: the state the settings window shows.

Tests: `pkgs/krane-ii-settings/tests` (command validation, the displays
confirm-or-revert flow, the boot path and the Lua render output).

The GUI never commits. `config.json` changes on every wallpaper switch
(`wallpaperPath`), so `git status` shows it often; commit selectively.
`ai/`, `*.tmp` and `presets/*.zip` are ignored. Read a host's whole
`config.json` before committing it for the first time: it can hold the
weather city, a booru username and AI endpoints.

### Hotplug and reload: KRANE_GUI_MONITORS

A host's `display.nix` can define `extraMonitorsLua` to re-send a monitor
rule outside the GUI's own `monitors.<output>` block, for example to keep a
laptop panel scaled correctly as external monitors come and go. That Lua
knows only the fields `display.nix` sets (`output`, `mode`, `scale`), so a
naive re-send would drop the GUI-owned fields (transform, VRR, color
management, HDR) on every hotplug or `hyprctl reload`.

The writer renders a `KRANE_GUI_MONITORS` Lua global into `custom/krane_gui.lua`,
keyed by output name, holding the full rule it sent to Hyprland. The
`monitors.lua` trailer requires `custom/krane_gui.lua` last, then calls
`krane_after_gui()` if the host defined one
(`modules/home/desktop/hypr-config.nix`'s `monitorsFile`). A host that needs
its `extraMonitorsLua` to survive hotplug sets `krane_after_gui` to a function
that merges `KRANE_GUI_MONITORS[output]` into each rule it re-sends, skipping
`output`; `KRANE_GUI_MONITORS[output]` already holds the Nix baseline overlaid
with the GUI values (mode and scale included), so the merge keeps the GUI's
choice. `hosts/tarmantria/display.nix`'s `place_internal` is the example: it
merges the panel's GUI entry back in whenever a monitor is added or removed
(the panel's position comes from the GUI entry of eDP-1 or, as the panel name
flips with the GPU mux, eDP-2).

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
Not ported: the Niri page, the fork's panel-style settings overlay (ii's
standalone window stays, so a broken page crashes only the settings process,
not the bar or lock screen), About's "Update dots" and "System update",
Profile's hostname editing and online presets.

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
| About | Packages, Updates cards; Update Dots, System update buttons | none | pacman-only / out of scope |
| Profile | Online presets; hostname editing (shown read-only) | `profile.onlinePresets` | out of scope |
| Hyprland | Displays section of the fork's `monitors.lua` writer; "add a require line" notice | none | replaced by `krane-ii-settings` |

## Claude Code

### Agents tab

The left sidebar's Agents tab (`patches/ii/04-agents`) lists every Claude
Code session on the machine that has a window or runs in the background,
grouped by working directory, most urgent group first. Clicking a row focuses
the session's terminal window on any workspace, or, for a background session
with no terminal attached, runs `kitty -e claude attach <id>`. The tab never
answers, approves, stops or deletes anything.

An interactive session is matched to its window by walking the session's pid
chain up to a Hyprland client. A background session is never walked. It is matched by
terminal title (Claude Code titles the window with the session name) and only
when exactly one window has that name; otherwise a click opens an attach
terminal instead of focusing a guessed window.

It runs ii's `scripts/claude/agents.sh` (`claude agents --json`, plus the pid
chain up to the terminal and the transcript's mtime; transcript content is
never read) every 3 s, backing off to 15 s when a run is slow, and only
while the tab is visible, so a closed sidebar starts no `claude` process.
Sessions whose process has no terminal window (SDK sessions such as the
claude-mem observer, tmux, SSH, TTYs) are hidden and counted as
"headless hidden".

To turn the tab off, use Settings, Interface, "Agents tab", or set
`"sidebar": {"agents": {"enable": false}}` in
`~/.config/illogical-impulse/config.json` (see "Settings persistence").

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

## Verifying on the target

See [docs/VERIFY.md](VERIFY.md)'s on-target checklist for the commands,
run after two consecutive `nixos-rebuild switch` runs.

`custom/env.lua` should end up as the soymou module's `PATH`/`XDG_DATA_DIRS`
block, then the sentinel, then our `hl.env` lines. No `QT_QPA_PLATFORMTHEME`
line: `patches/illogical-flake-kde-platformtheme.patch` drops the flake's
`qt6ct` override so ii upstream's `kde` value from `hyprland/env.lua` stands.
`custom/general.lua` follows the same pattern with its plugin comment
block in place of the `PATH` fixes.

## Rollback and escape hatches

- UWSM session misbehaves: set `programs.hyprland.withUWSM = false` in
  `modules/nixos/desktop/desktop.nix`. The plain Hyprland session is already on
  the greeter, so this is a one-line, one-rebuild rollback. ii starts
  programs with `hl.dsp.exec_cmd`, not UWSM-scoped launches, so some
  processes landing outside a UWSM scope is expected, not a fault.
- A single override misbehaves: delete the option value. The next
  switch re-renders the file without it. Appended files need no
  hand-editing, since the copy step recreates them from scratch and our
  step replaces everything from the sentinel down.
- The soymou module breaks or goes stale: see "If the soymou module breaks"
  below.
- Updating either input: `nix flake update dots-hyprland illogical-flake`
  is a reviewed change, not routine maintenance. Re-check the wipe-set
  table, the sourcing order, and that `copyIllogicalImpulseConfigs`
  still exists, then test two consecutive switches on the target.

## If the soymou module breaks

Trigger: the single-maintainer soymou module stops working, not just goes
quiet. Approach: self-vendor `dots-hyprland` (already a pinned input) and
drop `illogical-flake`; `krane.iiVendored.enable`
(`modules/home/desktop/fallback-vendoring.nix`) is a stub that fails the build.
What has to be ported from the module source at the pin: the copy step (wipe
set above), the env.lua and general.lua snippets, ii's runtime packages,
Quickshell build flags and the Python environment. `krane.hypr.*`, `display.nix`
and `kraneIiOverrides` stay; the `copyIllogicalImpulseConfigs` assertion goes.
