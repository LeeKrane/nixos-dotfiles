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
   `PATH`, `XDG_DATA_DIRS` and `QT_QPA_PLATFORMTHEME` fixes,
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

## Verifying on the target

See [docs/VERIFY.md](VERIFY.md)'s on-target checklist for the commands,
run after two consecutive `nixos-rebuild switch` runs.

`custom/env.lua` should end up as the soymou module's `PATH`/`XDG_DATA_DIRS`/
`QT_QPA_PLATFORMTHEME` block, then the sentinel, then our `hl.env` lines.
`custom/general.lua` follows the same pattern with its plugin comment
block in place of the `PATH` fixes.

## Rollback and escape hatches

- UWSM session misbehaves: set `programs.hyprland.withUWSM = false` in
  `modules/nixos/desktop.nix`. The plain Hyprland session is already on
  the greeter, so this is a one-line, one-rebuild rollback.
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
