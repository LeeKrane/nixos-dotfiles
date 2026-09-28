# illogical-impulse integration

This flake layers declarative Hyprland configuration on top of end-4's
illogical-impulse (ii) dotfiles. ii is delivered by the third-party
home-manager module soymou/illogical-flake, called the soymou module below.

Pinned revisions (`flake.lock`), re-read this document after either moves:
`dots-hyprland` at `97c5bc651f68092351b24aaa935af708b1e04514`,
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
`~/.config/illogical-impulse`, whose `config.json` is the shell's own
state and only seeded if absent.

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

`modules/home/illogical-impulse.nix` guards against that with an
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

Recording binds (`custom/keybinds.lua`) come from `modules/home/recording.nix`,
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
  `monitors.lua`, the same file `nwg-displays` writes. This repo owns
  that file, so a layout set through the ii display GUI is discarded on
  the next switch. Read the numbers back out of `monitors.lua` first and
  move them into `hosts/<host>/display.nix`.

## How to add an override

Pick the option for the file to affect, in `hosts/<host>/display.nix`
for one host or a module under `modules/home/` for all hosts:

| Option | Renders to | Emits |
| --- | --- | --- |
| `krane.hypr.monitors` | `monitors.lua` | `hl.monitor({...})` |
| `krane.hypr.env` | `custom/env.lua` | `hl.env(k, v)` |
| `krane.hypr.variables` | `custom/variables.lua` | `k = v` globals |
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
  `modules/nixos/shells.nix` aliases `cat` to `bat --color=always` at
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
  greetd straight into Hyprland (`modules/nixos/desktop.nix`), so there's
  no session picker to lock behind; flip the default itself so ii locks
  immediately on startup. `config.json` stays ii-owned after that, the GUI
  can still flip it back off.
- `~/.config/hypr/hypridle.conf`, only when a host sets
  `krane.hypr.idleTimeouts = false` (tariognatha): `/^listener {/,/^}/d`.
  Strips ii's idle listeners (lock at 5 min, DPMS off at 10, suspend at 15)
  and keeps the `general` block, so manual lock and lock-before-sleep still
  work. hypridle only reads its config at start, so the change applies from
  the next login or a hypridle restart.

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
  `modules/nixos/desktop.nix`. The plain Hyprland session is already on
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
