# Backport end4-pC fixes into the pinned illogical-impulse

Sub-project 1 of 5 in bringing pctrade/end4-pC work into this repo's ii setup.
The order is: fixes (this spec), translator, dock, AI/agent overview, settings
pages. Each later sub-project gets its own spec.

## Background

- **illogical-impulse (ii)** is end-4's desktop shell for Hyprland. It is
  written in QML for [Quickshell](https://quickshell.org), a toolkit for
  building bars, panels and widgets. It lives in end-4's
  [dots-hyprland](https://github.com/end-4/dots-hyprland) repo under
  `dots/.config/quickshell/ii`.
- **This repo pins dots-hyprland** as the flake input `dots-hyprland`
  (`flake.nix`), currently at `97c5bc651f68092351b24aaa935af708b1e04514`.
- **The soymou module** ([soymou/illogical-flake](https://github.com/soymou/illogical-flake))
  is a third-party home-manager module that installs ii. On every switch it
  deletes `~/.config/quickshell` and `~/.config/hypr` and copies them again
  from the dots-hyprland source it is given. Edits made in `~/.config` are
  therefore lost; changes must be made to that source. `lib/mk-host.nix`
  already hands the module a patched copy of dots-hyprland (`patchedDotfiles`),
  and `docs/II-INTEGRATION.md` describes the full integration.
- **[pctrade/end4-pC](https://github.com/pctrade/end4-pC)** is a heavily
  reworked copy of ii's Quickshell config, maintained by a third party. Its
  history is not a git fork of dots-hyprland, and much of its code no longer
  exists upstream. Some of its fixes therefore apply to our pin as-is
  ("clean"), and others must be rewritten against upstream code
  ("hand-ported").
- **QML errors** are runtime errors that Quickshell prints to its log (`qs log`)
  when a QML file fails to load or a binding throws. A fix can be broken
  without producing one, which is why each fix below has its own acceptance
  check.

## Goal

Carry a chosen set of bug and performance fixes from end4-pC into the ii config
from the pinned dots-hyprland input, without changing how the soymou module
installs ii.

Success means:

- Every fix below is present in the ii files the soymou module copies into
  `~/.config/quickshell/ii`.
- All three hosts build.
- Quickshell starts with no new QML errors.
- Each fix passes its own acceptance check.

## Constraints

- Fixes must live in the dots-hyprland source handed to the soymou module, not
  in `~/.config`.
- Fork paths are relative to the ii root (`services/…`, `modules/…`). In
  dots-hyprland they sit under `dots/.config/quickshell/ii/`.
- No behavior changes beyond the fixes themselves: no fork-only features, files
  or config keys.
- No public fork of dots-hyprland and no pushing to any remote. Patches live in
  this repo.

## Scope

A dry run of 19 fork fix and performance commits against the pinned source
gave this split.

### Clean (apply to the pin unchanged, paths rewritten only)

| Fork commit | Fix |
|---|---|
| `05b50d9` | ThumbnailImage: write each thumbnail to a temp file, then `mv` it into place, so concurrent ImageMagick (`magick`) runs stop overwriting each other's cache files |
| `6f1dc5f` | Notifications: rebuild the list once on discard instead of calling `splice()`, which froze the UI |
| `2cf76f8` | Notifications: wrap `JSON.parse` of the saved notification file in try/catch, so a truncated or invalid file no longer breaks loading |
| `342a45b` | Notifications: guard against a null timer in `cancelTimeout` |
| `eb76c3d` | Notifications: guard against an undefined action in `attemptInvokeAction` |
| `3dad196` | Colors: read the palette key name used by `materialyoucolor >= 3` |

`3dad196` replaces the existing `primary_paletteKeyColor` sed entry in
`modules/home/illogical-impulse.nix` (`iiPatches`). The sed entry must be
removed in the same commit that adds the patch. `3dad196` looks up both key
names, and the sed would rewrite its fallback `'primary_paletteKeyColor'`
literal into the new name, silently turning the fallback into a duplicate
lookup.

The four Notifications patches all change `services/Notifications.qml` and must
stay in commit order.

### Hand-ported (conflict with the pin; port the intent only)

| Fork commit | Fix | Why it matters here |
|---|---|---|
| `d116eef` | Count a Bluetooth device as connected when its `Battery1` interface is exported (Quickshell's `batteryAvailable`), as the fork does, working around [bluez#2485](https://github.com/bluez/bluez/issues/2485) | JBL headset reconnects |
| `1b51f7a` | Debounce raw Hyprland IPC events (60 ms) and only re-query the data an event affects, instead of spawning all five `hyprctl` queries on every event | Bursts of events when moving windows |

A hand-port changes only files that exist at the pin. Hunks that touch
fork-only files (such as the fork's settings pages) are dropped. If a fix's intent cannot be expressed
without fork-only code, the fix is dropped and the reason is recorded in the
docs table.

The `1b51f7a` port drops the fork's `WM.compositor` guards (the pin has no
compositor abstraction). Its event routing sends `monitor*` events to a
monitors and workspaces refresh. It also routes `configreloaded` to that
refresh, because a config reload can change the monitor layout; without that
branch the debounce would regress hotplug and reload handling compared with the
pin, which refreshed everything on every event.

### Dropped during porting

Drafting the ports against the pin showed three of the selected fixes have no
target there:

- `37a9fab` optimizes the fork's CPU-temperature and disk-usage readers. The
  pinned `ResourceUsage.qml` reads neither, and no widget at the pin shows them.
  Porting it would add a new feature, not fix one.
- `204f22f` changes only `MonitorConfigOption.qml`, a fork-only settings
  component. The pin already refreshes monitors on every event; the part that
  matters after `1b51f7a` (the `configreloaded` branch) is folded into that
  port.
- `9c7b0e1` sets `sourceSize` on the fork's wallpaper images so 4K to 9K
  wallpapers are not decoded at full resolution. The pinned `Background.qml`
  wallpaper is a `StyledImage`, whose `sourceSize` is already bound to its
  rendered `width`/`height` (`scaledWallpaperWidth`/`Height`) times the
  window's device pixel ratio, so the pin already decodes at screen size. The
  fork's other hunks touch fork-only files (`Carousel.qml`,
  `CenteredWallpaper.qml`, `UserCardWidget.qml`) or need a fork-only config key
  (`wallpaperSelector.showBlurBackground`).

All three are recorded in the docs as not portable.

### Out of scope

`6da89b0`, `692870a`, `4491c1e`, `7f21d8f`, `284ea42`, `8441d82`, `eb82786`,
`6e62be7`, and anything tied to the fork's settings, dock, widgets or Niri
backend. Later sub-projects may revisit some of them.

## Design

### Patch series

The patches in `patches/ii/01-fixes/` are a series exported from git. Each fix
is one commit on the local branch `krane` in a clone of dots-hyprland at the
pinned revision, and `git format-patch` writes the series out.

All five sub-projects share this layout: one directory per sub-project under
`patches/ii/` (`01-fixes`, `02-translator`, `03-dock`, `04-agents`,
`05-settings`), all exported from the same `krane` branch. A lightweight tag
`krane/<dir>` in the clone marks the last commit of each sub-project, so each
directory is exported from its own range. This sub-project introduces the
layout and the wiring; later sub-projects only add a directory. Patch files
are the only thing committed to this repo; the clone is a disposable workspace
and can be recreated from them at any time.

`git format-patch` names files `NNNN-<subject>.patch` in commit order and
records each change's blob hashes in its `index` lines. Those hashes let
`git am -3` do a three-way merge when the series is re-applied to a newer pin.

Each commit message holds the header information:

```
<subject from the fork commit>

Backport of pctrade/end4-pC <sha>
https://github.com/pctrade/end4-pC/commit/<sha>
Problem: <one or two lines>
Port: clean | hand-ported (<what was dropped or adapted>)
Drop when: <condition>
```

"Drop when" is concrete: either "the pinned dots-hyprland contains commit
<sha>", or "the pinned `<file>` no longer contains `<code the fix replaces>`".

Patches and the `iiPatches` sed entries in `modules/home/illogical-impulse.nix`
both change ii's files: patches at build time, seds at activation time on the
copied files. A patch in any sub-project must not change or add text that a
sed entry matches. Otherwise the sed either stops matching without an error or
rewrites the patch's own code, as it would with `3dad196` (see Scope). Today the
entry at risk is the `launchOnStartup` line in `modules/common/Config.qml`,
since sub-projects 2 to 5 all patch that file. If a patch has to change such a
line, it takes over the sed's job, and the sed entry is removed in the same
commit.

### Workflow

Create or refresh the series:

```sh
git clone https://github.com/end-4/dots-hyprland ~/src/dots-hyprland
cd ~/src/dots-hyprland
git config rerere.enabled true
git switch -c krane <pinned rev from flake.lock>
# re-apply every series in order, tagging the end of each (skip on first creation)
for d in ~/.dotfiles/patches/ii/*/; do
  git am -3 "$d"*.patch || break
  git tag -f "krane/$(basename "$d")"
done
# add, edit or drop commits with ordinary git commands
# export each directory from its own range: <pinned rev>..krane/01-fixes,
# krane/01-fixes..krane/02-translator, and so on
```

`git rerere` records each conflict resolution in the clone, so the next pin
bump replays it. The exact export loop goes into the docs (see the plan).

On a pin bump: `nix flake update dots-hyprland`, then run the same steps
against the new revision. `git am -3` stops at a conflict so it can be resolved
with git's tools; `git am --continue` resumes the series.

To remove one fix, drop its commit (`git rebase -i` in the clone or
`git am --skip` while re-applying) and export again. Deleting the patch file
directly only works when no later patch changes the same file.

The procedure goes into `docs/II-INTEGRATION.md`.

### Wiring

`lib/mk-host.nix` already builds `patchedDotfiles` with `applyPatches` over
`inputs.illogical-flake.inputs.dotfiles`, applying
`patches/illogical-flake-cheatsheet-fkeys.patch`. Extend that list with one
generic loader over `patches/ii/`:

```nix
iiSeries = let
  root = ../patches/ii;
  sortedNames = pred: dir:
    lib.sort lib.lessThan (builtins.attrNames (lib.filterAttrs pred (builtins.readDir dir)));
  patchesIn = dir: map (n: dir + "/${n}")
    (sortedNames (n: t: t == "regular" && lib.hasSuffix ".patch" n) dir);
in lib.concatMap (d: patchesIn (root + "/${d}"))
     (sortedNames (n: t: t == "directory") root);

patchedDotfiles = ...applyPatches {
  name = "dots-hyprland-patched";
  src = inputs.illogical-flake.inputs.dotfiles;
  patches = [ ../patches/illogical-flake-cheatsheet-fkeys.patch ] ++ iiSeries;
};
```

Directories apply in lexical order, and the patches within each directory in
lexical order. The binding is not called `iiPatches`, which already names the
sed list in `modules/home/illogical-impulse.nix`.

`lib` is the bare nixpkgs lib (`inputs.nixpkgs.lib`). The module's own `lib`
argument cannot be used: the imported module's `imports` list is built from this
patched path, and anything derived from `config` would be an infinite
recursion. That is the same reason the existing comment gives for taking
`applyPatches` from the bare nixpkgs. Filename order equals commit order
because `git format-patch` numbers the files, and directory order equals
sub-project order because of the `NN-` prefix.

The cheatsheet patch stays a separate file ahead of the series. The comment
above `patchedDotfiles` is updated to say it carries both the cheatsheet fix and
the `patches/ii/` series.

### When to stop using patches

The settings spec (`2026-09-27-ii-settings-design.md`, "Delivery mechanism")
decides to stay with patch series and sets the re-evaluation triggers for all
sub-projects. There is no patch-count threshold. Re-evaluate a private fork of
dots-hyprland as the flake input if:

- a pin bump needs more than 5 hand-resolved conflict hunks, or more than one
  sitting; or
- the user sets up a private remote that every host and the docker check can
  already reach; or
- upstream ii ships its own rewrite of settings that overlaps that port.

### Docs

`docs/II-INTEGRATION.md` gets a "Backported fork fixes" section with:

- a table of patch file, fork commit, clean or hand-ported, and drop condition;
- the workflow above;
- the re-evaluation triggers.

The materialyoucolor bullet in its "Patched files" list moves there.

## Error handling

- A patch that stops applying (for example after a pin bump) fails the
  `applyPatches` derivation, and `nixos-rebuild` names the failing file. The
  fix is to re-run the workflow and resolve the conflict with `git am -3`.
- A hand-port that breaks at runtime shows up in the qs log or fails its
  acceptance check. It is dropped from the series and the series is exported
  again.

## Testing

### Build

1. `nix build` of the `patchedDotfiles` derivation.
2. `nixos-rebuild dry-build --flake .#<host>` for tariognatha, tarmantria and
   taractias.

### Runtime, every host

3. After switching: restart qs and confirm the log shows no new QML errors or
   warnings compared with before the switch.
4. Change the wallpaper: `material_colors.scss` is regenerated. This confirms
   `3dad196` works without the sed entry.

### Acceptance checks per fix

| Fix | Check | Hosts |
|---|---|---|
| `05b50d9` | Open the wallpaper selector (the only user of `ThumbnailImage` at the pin) twice with an empty thumbnail cache. The second open spawns no `magick` process (`pgrep -c magick` stays 0). | any host |
| `6f1dc5f` | Swipe away a notification group of 10 or more. The rest slide up with no visible freeze. | any host |
| `2cf76f8` | Truncate the saved notifications file, restart qs. It starts, and the log shows the handled parse error instead of a crash. | any host |
| `342a45b`, `eb76c3d` | Dismiss notifications with and without actions. No `TypeError` in the log. | any host |
| `d116eef` | Reconnect the JBL headset and play audio. Whenever `busctl get-property org.bluez <device path> org.bluez.Device1 Connected` reports `false` during playback, ii still shows the device as connected. If the BlueZ bug does not reproduce, confirm connect and disconnect still show correctly. | any host with the Bluetooth headset |
| `1b51f7a` | Add a temporary `console.log` counter to the refresh function. Drag a window for 10 s before and after the patch: the count drops. Workspaces and the active-window title still update. | any host |
| `1b51f7a` (hotplug) | Unplug and replug an external monitor (name from `hyprctl monitors`), and run `hyprctl reload`. The bar leaves and returns, and workspaces stay on the right monitors, without restarting qs. If the host has no external monitor, note the check as not run. | any host with an external monitor |

taractias has not yet been verified on its real hardware (see
`hosts/taractias/default.nix`). Checks there wait until it has been.

## Commits

One commit per fix (the patch file, plus the sed removal for `3dad196`), and one
commit for the docs, so each change can be reviewed and reverted on its own. The
wiring lands in the first fix's commit: the loader reads `patches/ii/` with
`builtins.readDir`, and a flake only sees tracked files, so the directory must
hold a patch before the loader can evaluate.
