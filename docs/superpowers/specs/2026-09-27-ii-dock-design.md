# Port the end4-pC dock into the pinned illogical-impulse

Sub-project 3 of 5 in bringing pctrade/end4-pC work into this repo's ii setup
(fixes, translator, dock, AI/agent overview, settings pages). It reuses the
delivery mechanism from sub-project 1,
`docs/superpowers/specs/2026-09-27-ii-fork-fixes-design.md`, and assumes that
spec's wiring has landed first.

## Background

- Upstream ii at the pin (`dots-hyprland` `97c5bc6`, 2026-08-27) already ships
  a dock: `modules/ii/dock/{Dock,DockApps,DockAppButton,DockButton,DockSeparator}.qml`,
  loaded by `panelFamilies/IllogicalImpulseFamily.qml` when
  `Config.options.dock.enable` is true. Settings > Interface > Dock has switches
  for enable, hover-to-reveal, pinned-on-startup and monochrome icons. Upstream
  has not touched the dock since 2026-04-13, and the pin contains those commits.
- The user's `~/.config/illogical-impulse/config.json` has
  `dock.enable: false`, `pinnedApps: ["org.kde.dolphin", "kitty"]`,
  `monochromeIcons: true`, `hoverToReveal: true`. That file is ii's own state,
  written by the GUI; Nix never writes it. Sub-project 5 (settings) later
  moves it into the repo behind a directory symlink
  (`hosts/<host>/illogical-impulse/`), where it is still written only by ii.
- end4-pC started from ii on 2026-04-07. Its starting `Dock.qml`,
  `DockAppButton.qml`, `DockButton.qml` and `DockSeparator.qml` are
  byte-identical to the pin. Its `DockApps.qml` is older than the pin's (it
  lacks the two April upstream preview fixes).
- From there the fork rewrote the dock in about 25 commits, most of them
  unnamed ("df", "di", "ns"), ending at fork `HEAD` `dc2ca26` (2026-09-26):
  - `b8ddc00` "dock dock dock" deletes `DockApps.qml` and replaces it with
    `DragApps.qml` (pinned apps as fixed slots that can be dragged to reorder,
    plus the window-preview popup) and adds `DockMedia.qml` (a now-playing card
    with blurred cover art, title and play/pause/next). Running unpinned apps
    move to a separate row next to the media card.
  - Follow-up fixes on top of that rewrite: tint (`a91f94a`), padding
    (`4b36199`, `369f370`), fullscreen autohide (`3454521`), cover art
    (`f3c3dff`), separator (`71a9af6`, `722d85b`), empty pinned section
    (`4a3d008`, PR #19), and the unnamed tweaks listed above.
  - New config keys under `dock`: `showBackground`, `showPinButton`,
    `showAppsButton`, `showMedia`, with switches on the fork's own settings page.
  - `17d6f86` "DocktoPanel" moves the dock widgets to `modules/common/widgets/`
    and adds `modules/ii/bar/DocktoPanel.qml`, which renders pinned and running
    apps inside the bar.
- Terms used below: **Quickshell** is the QML toolkit ii runs on and `qs` is
  its binary; **MPRIS** is the D-Bus interface media players expose, read in ii
  by the `MprisController` service; **`ScreencopyView`** is the Quickshell item
  that draws a live window thumbnail; **`LazyLoader`** creates its component
  only while its `active` property is true.
- No fork screenshot shows the standalone dock. Screenshot 4 of the fork README
  shows DocktoPanel in the centre of a top bar.

## Goal

Give the user the fork's dock (drag-to-reorder pinned apps, a now-playing card,
autohide under fullscreen, the extra show/hide options) on top of the pinned
upstream dock, delivered as patches through the sub-project 1 mechanism.

Success means:

- The patched ii contains the ported dock and all three hosts build.
- With the dock enabled, Quickshell starts with no new QML errors or warnings.
- Each feature passes its acceptance check below on tariognatha, including on
  both monitors.
- With the dock disabled (the current config.json), nothing changes: no new
  log lines and no new layer surfaces.

## Constraints

- Everything is delivered through `applyPatches` on the dots-hyprland source,
  as in sub-project 1. Nothing is written into `~/.config/quickshell`.
- `config.json` stays ii-owned. Nothing in this repo writes it at build or
  activation time, also after sub-project 5 makes it a tracked file.
- No fork-only services. The fork's `WM` service (a Hyprland/Niri backend
  switch) does not exist at the pin; its uses are replaced by the pin's
  `Quickshell.Hyprland` API.
- The dock stays in `modules/ii/dock/`, the upstream path, so that `git am -3`
  can three-way merge against upstream dock changes on pin bumps.
- Repo rules: no public fork, no pushing, no commits until the user asks.

## Scope

A dependency check of the fork's final dock files against the pin found one
fork-only dependency, `WM` (used for `WM.monitorFor`, `WM.fullscreenOnMonitor`
and `WM.compositor === "hyprland"`). Everything else resolves at the pin:
`VerticalButtonGroup`, `GroupButton`, `RippleButton`, `StyledRectangularShadow`,
`StyledBlurEffect`, `StyledImage`, `AdaptedMaterialScheme`, `MprisController`,
`TaskbarApps` (`apps`, `togglePin`), `Directories.coverArt`, `AppSearch`,
`DesktopEntries.heuristicLookup`, `ColorUtils.{mix,transparentize,applyAlpha}`,
`StringUtils.cleanMusicTitle`, and every `Appearance.*` name used. No shapes
library is involved. The fullscreen check the fork originally wrote in
`3454521` used `Hyprland.workspaces` directly, the same pattern upstream uses in
`Background.qml` and `ScreenCorners.qml`.

### In scope

| Feature | Fork source | Port |
|---|---|---|
| Hide the dock on a monitor showing a fullscreen window, and drop its exclusive zone there | `3454521` | Hand-port onto the upstream `Dock.qml`, using the `3454521` Hyprland form, not the later `WM` form |
| Pinned apps as drag-to-reorder slots, with window previews; running unpinned apps in their own row | `b8ddc00` and follow-ups, fork `HEAD` `DragApps.qml` and `Dock.qml` | Snapshot port of the fork `HEAD` files (see below) |
| Tint, padding, separator and empty-pinned-section fixes | `a91f94a`, `4b36199`, `369f370`, `71a9af6`, `722d85b`, `4a3d008` | Included in the snapshot; they only make sense on the rewritten layout |
| Now-playing card | `DockMedia.qml`, `f3c3dff` | Snapshot port |
| `showBackground`, `showPinButton`, `showAppsButton`, `showMedia` options with switches in Settings > Interface > Dock | `5449319`, `1fde27f`, `b8ddc00` | Hand-port: keys into `Config.qml`, four `ConfigSwitch` entries into the pin's `modules/settings/InterfaceConfig.qml` Dock section |

"Snapshot port" means copying the fork's final version of a file at
`dc2ca26`, then applying only the adaptations listed under Design. Replaying the
fork's roughly 25 dock commits one by one is not worth it: most have no message,
several rewrite each other, and the intermediate states never ran on our pin.
The upstream preview fixes that postdate the fork's start
(`popupCenterXForButton`, the `shouldShow` guard on empty toplevels) are
already present in the fork's `DragApps.qml` and are kept.

At `dc2ca26`, `DragApps.qml`, `DockAppButton.qml`, `DockButton.qml` and
`DockSeparator.qml` live in `modules/common/widgets/`, where `17d6f86` moved
them for DocktoPanel; four later commits (`3ef02b1`, `5016148`, `c7b606e`,
`f25e709`) changed `DragApps.qml` there. `Dock.qml` and `DockMedia.qml` stayed
in `modules/ii/dock/`. The snapshot is taken from those paths and everything
lands in `modules/ii/dock/`.

A snapshot still has to be understood. Before exporting patch 2, the
implementer reads the fork diff of every commit that touched the dock after
`b8ddc00` (listed in Background), plus the four earlier fork dock commits
whose effects survive in the snapshot (`c5098e4`, `05283be`, `5449319`,
`b488320`: pin-button margins, hidden shadow, `showBackground`, `iconSize` 33) and records in the patch 2 commit message
which ones the snapshot contains and which it deliberately drops.

**Known regression in the fork, fixed by this port.** In the fork's `Dock.qml`
the running unpinned apps are `DockAppButton { appListRoot: appListBridge }`,
and `appListBridge` is a bare `QtObject` that nothing reads. Hovering an
unpinned app therefore never opens a window preview, where upstream
`DockApps.qml` shows one for every app. Most of the user's everyday windows are
unpinned, so this is not taken as-is (see patch 2).

### Out of scope

- **DocktoPanel** (`17d6f86`, `caa6079`). It is a bar widget, not a dock
  feature, and it depends on the fork's configurable bar: it registers as a
  widget id (`docktoPanel`) in the fork's `BarContent.qml` layout system and
  `BarConfig.qml` settings page, and it checks `bar.cornerStyle === 3`, a bar
  style ("M3") the pin does not have (the pin's styles are 0 to 2). The pin's `BarContent.qml` differs from the fork's by
  about 780 diff lines and has no widget-id layout. Porting it means porting the
  fork's bar first, which belongs with the settings sub-project or a bar
  sub-project.
- Moving `DockAppButton`, `DockButton`, `DockSeparator` and `DragApps` to
  `modules/common/widgets/`. The fork did this only so DocktoPanel could share
  them.
- The `dynamicIsland` config block added by `b9dca46` together with a one-line
  `DockMedia.qml` change. The dynamic island is a fork-only bar feature; only
  the `DockMedia.qml` line (`visible: root.hasTrack`) is kept.
- Declarative `pinnedApps` and a declarative `dock.enable` (see Design, "Config
  ownership").
- The waffle panel family's taskbar.

## Design

### Patch series

The dock gets its own series directory, `patches/ii/03-dock/`, following the
layout sub-project 1 defines: its commits sit on the shared `krane` branch in
the dots-hyprland clone, after the translator commits (tag
`krane/02-translator`), and are exported with
`git format-patch -o patches/ii/03-dock krane/02-translator..krane/03-dock`.
They are applied with `applyPatches` and refreshed with `git am -3` (and
`git rerere`) on pin bumps, like every other directory. The dock can be
removed as a whole by deleting its directory.

The dock series touches only `modules/ii/dock/*`, `modules/common/Config.qml`
and `modules/settings/InterfaceConfig.qml`. Sub-project 1 touches none of
these. Sub-project 2 changes `Config.qml` too, but only
`sidebar.translator.enable`, far from the `dock` object, so the dock patches
also apply to the bare pin; the fixed order on one branch just gives the later
agents and settings patches, which also edit `Config.qml`, one linear order to
stack onto.

Commit message header, as in sub-project 1:

```
<subject>

Port of pctrade/end4-pC <sha or "dc2ca26 snapshot of <files>">
https://github.com/pctrade/end4-pC/commit/<sha>
Problem: <one or two lines>
Port: hand-ported | snapshot (<adaptations>)
Drop when: <condition>
```

### Patches

1. **`dock: hide on fullscreen per monitor`** (hand-port of `3454521`) onto the
   upstream `Dock.qml`. Adds to the per-screen `PanelWindow`:

   ```qml
   property HyprlandMonitor hyprMonitor: Hyprland.monitorFor(modelData)
   property bool fullscreenOnThisMonitor: Hyprland.workspaces.values.some(ws =>
       ws.active && ws.monitor?.name === hyprMonitor?.name
       && ws.toplevels.values.some(w => w.wayland?.fullscreen))
   ```

   `reveal` becomes hover-only while `fullscreenOnThisMonitor` is true, and
   `exclusiveZone` is 0 there even when the dock is pinned. The optional
   chaining on `hyprMonitor` is an adaptation: the fork dereferences
   `hyprMonitor.name` unguarded, which throws while a monitor is being
   unplugged. This patch stands on its own and is first so it survives if later
   patches are dropped. Drop when: upstream `Dock.qml` checks fullscreen.

2. **`dock: pinned apps as reorderable slots`** (snapshot of fork `Dock.qml` and
   `DragApps.qml` at `dc2ca26`, placed in `modules/ii/dock/`). Deletes
   `DockApps.qml`, adds `DragApps.qml`, replaces the `Dock.qml` layout. Keeps
   `DockAppButton.qml` from the pin except the fork's `iconSize` 35 to 33
   change, and takes the fork's `DockSeparator.qml` margin change. Adaptations:
   - `WM.compositor === "hyprland"` becomes `true` (the pin runs on Hyprland
     only).
   - The fullscreen logic uses patch 1's properties, not `WM`.
   - `DragApps` looks up running apps with
     `TaskbarApps.apps.find(a => a.appId === appId.toLowerCase())`.
     `TaskbarApps` lowercases its keys and the fork compares the raw id, so a
     pinned id with capitals (for example a Steam shortcut id) would never show
     its running indicator.
   - Running unpinned apps get `appListRoot: dragSlots` instead of the dead
     `appListBridge`, so hovering them drives the same preview popup as the
     pinned slots. `DockAppButton` already sets `appListRoot.lastHoveredButton`
     and `buttonHovered`, `DragApps`' popup reads `lastHoveredButton.appToplevel`
     (a `TaskbarApps` entry in both cases), and the popup is anchored to the
     dock window, not to the `DragApps` item. `appListBridge` is deleted. If
     previews still fail for unpinned apps, most likely when `DragApps` is
     hidden because nothing is pinned, the first fallback keeps `DragApps`
     visible at zero width (a negative left margin cancels its row spacing),
     so the popup stays where the snapshot has it and the layout does not
     change. Only if that also fails is the popup moved out of `DragApps`
     into `Dock.qml` so both rows share it; that rewrites the snapshot's
     popup ownership and is decided with the user first. Whichever fallback
     is used is recorded in the patch's `Port:` line. Previews must work
     for pinned and unpinned apps before this patch is exported.
   - `DockMedia` references are left out of this patch (it is patch 3); the
     media slot and its separator condition are added there.
   Drop when: never automatically; this replaces upstream code. On a pin bump
   that changes `DockApps.qml`, re-check that upstream fixes are not lost.

3. **`dock: now-playing card`** (snapshot of fork `DockMedia.qml` at `dc2ca26`,
   includes `f3c3dff`). Adds `DockMedia.qml`, the `showMedia` key, and the
   media slot and separator conditions in `Dock.qml`. Cover art is downloaded
   with the same `curl` into `Directories.coverArt` that upstream
   `PlayerControl.qml` uses, so the two share one cache. Player state comes from
   the existing shared `MprisController` service, the same one the bar and
   media controls read, so no new media service is needed.

4. **`dock: show/hide options in settings`**. Adds `showBackground`,
   `showPinButton`, `showAppsButton` (all default `true`) to the `dock` object
   in `Config.qml`, wires them in `Dock.qml` as the fork does, and adds four
   `ConfigSwitch` rows (the three above plus `showMedia`) to the Dock section of
   `modules/settings/InterfaceConfig.qml`, next to the existing four. Defaults
   are `true`, so the dock looks like the fork's until the user changes them.

Four patches. The settings sub-project is the one most likely to conflict with
patch 4, since both edit `modules/settings/InterfaceConfig.qml` and
`Config.qml`. The settings spec resolves this: its `Config.qml` subset does not
redeclare the four keys added here, and its replacement Interface page keeps
the Dock switches, including these four.

### Prerequisites and order

Sub-project 1 has not been implemented yet: `patches/ii/` does not exist and
`lib/mk-host.nix` still applies only the cheatsheet patch. The dock depends on
it only for the wiring and the branch to stack on, not for any fix, and on
sub-project 2 only for its place in the branch. The order is:

1. Sub-projects 1 and 2 land (layout, wiring, docs, translator).
2. Patch 1 of this sub-project lands on its own and passes its checks. It is
   useful even if the rest is never finished.
3. Patches 2 to 4 land together, after their checks pass on tariognatha.

### Wiring

None. Sub-project 1's generic loader in `lib/mk-host.nix` applies every
`patches/ii/*/` directory in lexical order, so `03-dock` is picked up as soon
as it exists. Nothing in `modules/home/illogical-impulse.nix` changes.

### Config ownership

**Enabling the dock.** The pin's `Config.qml` default is `enable: false`, and
the user's `config.json` already stores `enable: false` explicitly, so a
changed default would only reach a host whose `config.json` does not exist yet.
The default here is: no Nix option. The user turns the dock on once per host in
Settings > Interface > Dock (or with the existing switch while trying it out),
and the choice lives in `config.json` like every other ii setting.

**pinnedApps.** Not declarative. The dock itself writes this list at runtime:
right-click pin/unpin (`TaskbarApps.togglePin`) and, after patch 2, every drag
reorder (`DragApps.commitOrder` assigns `Config.options.dock.pinnedApps`). An
activation step that writes the list would undo those edits on every switch. The
current upstream default (`org.kde.dolphin`, `kitty`) already equals the user's
list, so fresh hosts start from the same set. Once sub-project 5 has made
`config.json` a tracked repo file, every pin, unpin and reorder shows up in
`git status` as a change to `hosts/<host>/illogical-impulse/config.json`, to
be committed or discarded by hand like any other GUI change.

The new keys from patch 4 need no action. ii's config adapter uses the QML
default for a key missing from `config.json`.

### Multi-monitor behaviour (tariognatha)

The dock is a `Variants` over `Quickshell.screens`, so each monitor gets its own
dock window: DP-2 (3840x2160 at scale 1.5, 2560x1440 logical) and DP-1
(2560x1440 at scale 1). Both are 1440 logical pixels tall and share a bottom
edge, so the 2 px hover strip sits at the same height on both.

- **Pinned state** (`root.pinned`) is one property on the outer `Scope`, so
  pinning the dock pins it on both monitors. This is upstream behaviour and is
  kept.
- **Fullscreen** is per monitor after patch 1: a fullscreen game on DP-2 hides
  only the DP-2 dock.
- **Reveal when nothing is focused** (`!ToplevelManager.activeToplevel?.activated`)
  is global in upstream and stays global: with no focused window the dock shows
  on both monitors.
- **Reorder**: dragging happens inside one monitor's dock. `commitOrder` writes
  `pinnedApps`, and the other dock's `DragApps` reloads its order from the
  binding when it is not itself dragging.
- **Previews** use `ScreencopyView`, which the upstream dock already uses; the
  Nvidia behaviour is unchanged by this port.
- **Hotplug**: while a monitor is being removed, `hyprMonitor` is briefly null
  and `fullscreenOnThisMonitor` is false. That window's dock is about to be
  destroyed anyway, so this is accepted.
- **Two docks writing at once**: a reorder commits only on drop, and one
  pointer cannot drag in two docks at the same time, so the last write wins
  and both docks converge on it.

### Docs

`docs/II-INTEGRATION.md` gets a short "Dock" subsection under the backported
fork section from sub-project 1: the `patches/ii/03-dock/` table (patch, fork
source, snapshot or hand-port, drop condition), the note that DocktoPanel is
deferred, and how to enable the dock.

## Error handling

- A patch that fails to apply fails the `applyPatches` derivation and names the
  file, as in sub-project 1.
- A runtime error in a ported file shows up in `qs log`. With the dock disabled
  the files are never loaded (`PanelLoader` is a `LazyLoader` whose `active`
  includes `extraCondition`), so a broken
  dock cannot break a host that has not enabled it. Turning the dock off in
  Settings is the immediate workaround on a host that has.
- A pinned id with no desktop entry shows the `image-missing` icon and does
  nothing on click, as upstream does.
- `DockMedia` hides itself when there is no track (`hasTrack`), and a failed
  cover-art download leaves the blurred background empty without an error.

## Testing

### Build

1. `nix build` of the patched dots-hyprland derivation, which applies every
   series under `patches/ii/`.
2. `nixos-rebuild dry-build --flake .#<host>` for tariognatha, tarmantria and
   taractias.

### Runtime

3. Switch with the dock still disabled. `qs log` shows nothing new compared
   with before the switch, and `hyprctl layers` lists no `quickshell:dock`
   surface.
4. Enable the dock in Settings > Interface > Dock. `qs log` shows no new errors
   or warnings, and `hyprctl layers` lists one `quickshell:dock` surface per
   monitor.

### Acceptance checks per feature

| Feature | Check | Hosts |
|---|---|---|
| Fullscreen autohide | Pin the dock. Fullscreen a window (`hyprctl dispatch fullscreen`) on DP-2: the DP-2 dock slides away, the window covers the bottom edge (no exclusive zone), and the DP-1 dock stays. Hovering the DP-2 bottom edge still reveals it. Leave fullscreen: the dock returns and reserves space again. | tariognatha; tarmantria built-in screen |
| Hotplug | With the dock enabled, unplug and replug DP-1. No `TypeError` about `name` in `qs log`, and DP-1 gets its dock back. | tariognatha |
| Reorder | Drag kitty in front of dolphin. The order changes on both monitors, and `jq .dock.pinnedApps ~/.config/illogical-impulse/config.json` shows the new order after a qs restart. | tariognatha |
| Pin/unpin | Right-click a running unpinned app, pin it: it moves from the running row to the pinned slots. Unpin it: it moves back. Unpin every app: the pinned section and its separator disappear, with no empty gap. | tariognatha |
| Running indicator | Pin an app whose id has capitals (edit `pinnedApps` in `config.json`, restart qs), launch it: its slot shows the running dots and clicking focuses the window. | tariognatha |
| Previews | Hover a pinned app with two windows, then an unpinned app with two windows (for example two Firefox windows): each time the popup shows both previews, centred over the icon, on each monitor. Repeat with `pinnedApps` empty: unpinned previews still appear. | tariognatha |
| Monochrome tint | Toggle monochrome icons: pinned and running icons are desaturated and tinted together when on, full colour when off. | tariognatha |
| Now playing | Play audio in a player with cover art: the card appears with the cover, title and artist; play/pause and next work. Stop the player: the card and its separator disappear. | tariognatha |
| Options | Before touching anything, the four new switches show as on (the QML defaults fill the keys missing from `config.json`). Toggle each: the background, pin button, apps button and media card appear and disappear, and separators do not double up. | tariognatha |
| Disabled | Step 3 above. | all three hosts |

taractias checks wait until it has been verified on hardware, as in sub-project
1.

## Commits

In this repo: one commit per patch file (four), plus one for the docs. No
wiring change is needed; the first patch commit creates `patches/ii/03-dock/`.
Patch 1 is committed and tested before patches 2 to 4 (see "Prerequisites and
order").

## Open questions for the user

1. **Take the fork's whole dock rewrite, or only the fixes?** Default: all four
   patches, with the unpinned-preview regression fixed in patch 2. The smallest
   useful subset is patch 1 alone (fullscreen autohide on the upstream dock).
   A middle option, not chosen because it means writing new code rather than
   porting it, is to keep upstream `DockApps.qml` and hand-port only
   drag-to-reorder into it.
2. **Enable the dock declaratively?** Default: no; turn it on in Settings once
   per host. The alternative is a `krane.ii.dock.enable` option whose
   activation step sets `dock.enable` in `config.json` with `jq` on every
   switch, which would override the Settings switch.
3. **Defaults for the new options.** Default: all `true` (the fork's look). The
   user may prefer `showMedia: false` if the media card duplicates the bar's
   media widget.
4. **DocktoPanel.** Default: deferred to the settings or a bar sub-project,
   because it needs the fork's configurable bar.

Decided elsewhere, no longer open: the dock stays a patch series (the settings
spec's delivery decision and re-evaluation triggers), in its own
`patches/ii/03-dock/` directory (the shared layout from sub-project 1).
