# Port the end4-pC settings pages into the pinned illogical-impulse

Sub-project 5 in bringing pctrade/end4-pC work into this repo's ii setup. The
order is: fixes, translator, dock, AI/agent overview, settings pages (this
spec). Sub-project 3, the dock, was dropped; 1, 2 and 4 have landed. The
fixes spec (`2026-09-27-ii-fork-fixes-design.md`) defines the patch
mechanism and the `patches/ii/NN-<name>/` layout this spec builds on. The
patches-versus-fork decision for all four remaining sub-projects, and the
triggers for revisiting it, are made below.

## Background

Terms used below:

- **ii** (illogical-impulse) is end-4's Quickshell/QML desktop shell for
  Hyprland.
- **The pin** is the `dots-hyprland` flake input revision ii comes from
  (`97c5bc6`).
- **The soymou module** is the third-party home-manager module that copies ii
  into `$HOME` on every switch.
- **end4-pC** is a third-party rework of ii and the source of the pages.
- **`krane.hypr.*`** are this repo's options that render Hyprland Lua
  (`modules/home/hypr-config.nix`). **`display.nix`** is each host's use of
  them.
- **A switch** is `nixos-rebuild switch`.

Data flow in one line: repo files → Nix evaluation → home-manager
activation writes files under `~/.config` → Hyprland and ii read them at
runtime. The GUI writes both the repo file (persistence) and the runtime file
(live effect).

- ii's settings UI at the pin is a separate Quickshell window,
  `settings.qml`, started by `SUPER + I` (`settingsApp` in
  `hyprland/variables.lua`, `qs -p ~/.config/quickshell/ii/settings.qml`). It
  has eight pages under `modules/settings/`, and every page writes only
  `~/.config/illogical-impulse/config.json`.
- The pin already has a small Hyprland writer: `services/HyprlandConfig.qml`
  plus `scripts/hyprland/hyprconfigurator.py`, which rewrite
  `~/.config/hypr/hyprland/shellOverrides/main.lua`. That file is `require`d
  last by `hyprland.lua`. The game mode quick toggle and the anti-flashbang
  shader use it for temporary overrides.
- end4-pC (checked at `dc2ca2600ee6`, 2026-09-26) moved settings into the ii
  panel family (`modules/ii/settings/`). It rewrote every page and added
  a Hyprland page that edits monitors (including HDR and color management),
  input, idle, decoration, border colors, animation presets and autostart
  apps. It also added a Niri page and a Profile page.
- Everything under `~/.config/hypr` and `~/.config/quickshell` is wiped and
  copied again on every switch (`docs/II-INTEGRATION.md`). `monitors.lua` and
  `custom/*.lua` are rendered from `krane.hypr.*`
  (`modules/home/hypr-config.nix`). `hypridle.conf` is sed-patched when a host
  sets `krane.hypr.idleTimeouts = false`. `~/.config/illogical-impulse/` is
  excluded from the wipe, and its `config.json` is only seeded when it is
  missing.

So on this setup the fork's Hyprland page is broken in two ways. Every write
lands in a file the next switch deletes, and its monitor writer edits
`monitors.lua`, a file this repo owns and overwrites.

## Goal

Bring the fork's settings pages into ii so that each control either:

- changes a value that survives switches and reboots, and that lives in a
  file inside `/home/krane/.dotfiles` the user can review and commit; or
- is removed, because it cannot work on this setup, with the reason
  recorded.

The GUI never commits and never pushes. Committing stays manual.

### Success criteria

1. Every in-scope page opens in the settings window with no new QML errors in
   `qs log`, on all three hosts.
2. For each Hyprland-affecting control, the change is live within about a
   second. It shows up as a diff in `git -C ~/.dotfiles status`, and after two
   `nixos-rebuild switch` runs plus a reboot, `hyprctl getoption` (or
   `hyprctl monitors -j`, or `hypridle.conf`) still reports the changed value.
3. For each config.json control, the change appears as a diff under
   `hosts/<host>/illogical-impulse/` and survives a switch and a reboot.
4. Resetting a Hyprland control removes its key from the repo file. After a
   reload the value falls back to what `krane.hypr.*` or upstream ii set, with
   no switch needed.
5. Every key has exactly one owner. A control whose key is declared in Nix
   (`krane.hypr.*`, or `krane.hypr.guiLocked`) is shown disabled with "Set in
   Nix". The writer refuses that key, and a key present in both places fails
   evaluation.
6. `nix flake check` passes, including the new checks below.

## Constraints

- The user's rules: no commits or pushes by tools, no PRs, and no public fork
  of dots-hyprland.
- ii's code changes are delivered the way the fixes spec defines. Files in
  `~/.config/hypr` and `~/.config/quickshell` are never edited as the way to
  persist anything.
- Every repo file that Nix reads must be git-tracked, because a flake
  evaluation cannot see untracked files. Tracked files with uncommitted changes
  are seen (dirty tree), so the GUI only ever modifies files that already
  exist.
- Unknown `hl.config` keys or `hl.monitor` fields are hard errors at Hyprland
  start (`docs/II-INTEGRATION.md`). The GUI must never be able to write a key
  that has not been checked against Hyprland 0.56.
- No Niri, so no Niri code paths.
- Hosts: tariognatha (Nvidia, DP-2 3840x2160@240 scale 1.5 plus DP-1
  2560x1440@144), tarmantria (Nvidia Optimus laptop, eDP-1 on the iGPU) and
  taractias (AMD laptop, hardware not yet verified).

## Delivery mechanism: stay with patch series (decision)

The four sub-projects together carry well over 20 patches: this one alone
adds about 15, on top of the fixes' 9 and whatever sub-projects 2 and 4 add.
**Decision: keep `git format-patch` series applied by `applyPatches`, in the
layout described below. Do not switch the flake input to a private fork.**

Reasons:

1. **A fork input would have to be fetchable from everywhere the flake is
   evaluated.** That means three hosts, root's nix daemon during
   `nixos-rebuild`, the `just check` docker container, and `install.sh` on a
   fresh machine (which copies only this repo). A local `git+file:` fork fails
   on every machine but one. A private GitHub fork needs a push, which the user
   has not authorised, plus SSH keys or `access-tokens` on every host and
   inside the docker check. Its first fetch on a fresh install would then
   depend on secrets that sops can only decrypt after that install. The patch
   series needs none of this, because the repo carries everything.
2. **Conflict cost is the same either way.** Rebasing a fork branch onto a new
   pin is the same operation as `git am -3` of the series. Both happen in a
   local clone with git's tools. Enabling `git rerere` in that clone records
   each resolution so it is reused on the next bump.
3. **Most of this port is new or wholesale-replaced files.** Of the roughly
   12,000 lines, about 3,000 are new files (widgets, scripts, and the
   Hyprland and Profile pages), and a patch that adds a file applies cleanly
   to any pin. About 6,000 are whole-file replacements of the seven upstream
   pages. When upstream changes one of those pages, the resolution is
   mechanical: keep ours, then read upstream's diff for anything worth
   carrying over. Real three-way merges only come from a short list of hot
   files: `Config.qml`, `ContentPage.qml`, `ContentSection.qml`,
   `ConfigSelectionArray.qml`, `settings.qml` and `HyprlandConfig.qml`. The
   design keeps each hot file's changes in its own small patch.
4. **This spec moves krane-specific logic out of ii.** The writer, schema,
   renderer and manifest live in this repo as Nix and Python (see Design). The
   ii patches only call them, so a pin bump that rewrites
   `HyprlandConfig.qml` costs a small re-port, not a redesign.

### Layout

Sub-project 1 introduces this layout from its first patch, so nothing has to
be moved later:

- **One local branch, one directory per sub-project.** A single branch
  `krane` in the disposable clone holds every sub-project's commits in order.
  Lightweight tags in the clone (`krane/01-fixes`, `krane/02-translator`,
  `krane/04-agents`, `krane/05-settings`) mark where each
  sub-project ends. Each range is exported to its own directory with
  `git format-patch --no-numbered -o patches/ii/<NN>-<name> <prev-tag>..<tag>` (the pin for
  `01-fixes`): `01-fixes`, `02-translator`, `04-agents`,
  `05-settings`. Sub-project 3 (the dock) was dropped, so there is no
  `krane/03-dock` tag and no `patches/ii/03-dock`. The tags only need to
  exist in the clone and are rebuilt when
  the series is re-applied.
- **Wiring.** `lib/mk-host.nix` reads `patches/ii/`, sorts the
  sub-directories, sorts the `.patch` files within each, and concatenates
  them after the cheatsheet patch. Sub-project 1 adds this loader; this
  sub-project only adds `patches/ii/05-settings/`.
- **`git rerere` in the clone.** Enable it (`git config rerere.enabled true`)
  so a resolution is recorded once and replayed on the next bump.

### New re-evaluation triggers

These apply to every sub-project; there is no patch-count threshold.
Re-evaluate if:

- a pin bump needs more than 5 hand-resolved conflict hunks, or more than one
  sitting; or
- the user sets up a private remote that every host and the docker check can
  already reach; or
- upstream ii ships its own rewrite of settings that overlaps this port.

Vendoring the whole ii tree into this repo (the
`docs/FALLBACK-VENDORING.md` route) was considered and rejected for this
purpose. It gives up cheap pin bumps entirely, and it is meant as an escape
from the soymou module, not as a way to carry features.

## Scope

### Port size (fork at `dc2ca2600ee6`, pin `97c5bc6`)

| Part | Files | Lines |
|---|---|---|
| Pages (About, Background, Bar, General, Hyprland, Interface, Profile, Quick, Services) | 9 | 7,517 |
| Niri page (out of scope) | 1 | 686 |
| Fork panel shell (`Settings.qml`, `SettingsContent.qml`), not ported, see below | 2 | 531 |
| Fork-only widgets, models and services the pages use directly (`AboutCard`, `Carousel`, `ColorSelectionArray`, `ConfigComboBox`, `ConfigSelectionShapeArray`, `ConfigTextArea`, `GroupedList`, `WidgetsMonitorSelector`, `LayoutSection`, `AndroidClock`, `AutostartApps`, `MonitorCanvas`, `MonitorConfigOption`, `WorldMap`, `MaterialShape`, `NavigationRailTabArray`, `Presets`) | 17 | ~2,200 |
| Shared widgets changed by the fork (`ContentPage` 205, `ContentSection` 113, `ConfigSelectionArray` 79 diff lines, others under 10) | ~10 | ~420 diff lines |
| `Config.qml` schema (fork 940 lines, pin 633) | 1 | ~300, only the used subset is ported |
| Python: `hyprconfigurator.py`, `hypridleconfigurator.py`, `monitor_configurator.py`, `monitor_caps.py`, `autostart.py` | 5 | 835 |

The widget count covers only direct references. Transitive dependencies are
counted when the first patch is built, and the count goes in the docs table.

Of the config paths the pages reference, many do not exist at the pin because
they belong to fork-only features: Background 30 of 64, Bar 31 of 59,
Interface 22 of 97, Profile 5 of 5, Services 2 of 22, Hyprland 30 of 30. The
Hyprland ones are replaced by this design, so they are not a problem.

### Porting rule for controls

A control is ported only if the feature it configures exists in the pin plus
the landed series of sub-projects 1, 2 and 4. Otherwise the control is dropped
and listed in the docs table as "fork-only feature". Examples of dropped
controls: centered wallpaper, the dynamic island in the bar, and the
visualizer styles. Sub-project 3 (the dock) was dropped, so the Interface
page ports only the Dock controls for upstream's keys; the fork's
`dock.showBackground`, `showPinButton`, `showAppsButton` and `showMedia`
controls are dropped as fork-only. This keeps the port to "all pages" and not "all fork
features". Fork-only features stay out (resolved decision 5).

Two rules protect what sub-projects 2 and 4 already changed, because this
sub-project replaces pages and ports a `Config.qml` subset on top of them:

- **`Config.qml`: no key twice.** The ported subset adds only keys that do not
  exist after `04-agents`. It does not redeclare upstream's `dock.*` keys
  or `sidebar.agents` from `04-agents`, since a second
  declaration of a property is a QML error. It does not revert the
  `sidebar.translator.enable: true` default from `02-translator`, and it
  leaves the `lock.launchOnStartup` line untouched, because the
  `launchOnStartup` sed in `iiPatches` matches that exact line (see the fixes
  spec, "Patch series").
- **Replaced pages keep earlier controls.** The replacement Interface page
  keeps the "Enable translator" switch (the translator's acceptance checks use
  it) and upstream's four Dock switches (`dock.enable`, `hoverToReveal`,
  `pinnedOnStartup`, `monochromeIcons`). It also gains an "Agents tab" switch
  for `sidebar.agents.enable` from `04-agents`, next to the translator switch
  and in the same style (the fork's page has no control for it).

### Settings window: keep upstream's standalone window

The fork's panel-family overlay (`modules/ii/settings/Settings.qml`, a
full-screen layer-shell `PanelWindow` inside the main `qs` process) is **not**
ported. The fork's page files go into upstream's `settings.qml` page list
under `modules/settings/`. The reasons:

- A broken page crashes only the settings process, not the bar and lock
  screen.
- It avoids hot edits to `panelFamilies/IllogicalImpulseFamily.qml` and
  `GlobalStates.qml`.
- `SUPER + I` keeps working unchanged.

Fork references to `GlobalStates.settingsOpen` become `Qt.quit()` in the
standalone window. `Config.options.settings.style` ("minimal") is dropped.
Upstream's Advanced page, which the fork removed, stays.

### Prerequisites and effort

- **Sub-project 1 must land first.** `patches/ii/` does not exist yet. Its
  layout and wiring, and at least one pin bump done with its workflow, must be
  done and verified on the hosts before phase A starts. That bump is the
  first real measurement of what conflict resolution costs.
- Sub-projects 2 and 4 do not block phase A. Controls for their features are
  added when they land, by the porting rule. If one lands after settings work
  has started, its commits still go ahead of the settings commits on the
  `krane` branch (rebase in the clone, move the tags, export again), so the
  directory order stays `01` to `05` and the two `Config.qml` and page rules
  above are checked again against the result.
- Outside view: ports of this size onto a pinned upstream plus Nix
  integration usually take several weeks of part-time work, not days. Most of
  the surprises show up once the pages first run against real
  `Config.qml` state. Plan phase A as the calibration point. If phase A takes
  more than twice its estimate, re-scope phases B and C before starting them.

### Phases

Each phase is shippable on its own and passes its own tests before the next
one starts.

**Phase A: shell and config.json-only pages.**
- Shared widget changes, the `Config.qml` subset, and the settings window page
  list.
- Pages: Quick, General, Bar, Background, Interface, Services, About,
  Profile, each with its fork-only controls removed.
- `~/.config/illogical-impulse/` moves into the repo (see Design A).

**Phase B: Hyprland option writers.**
- The repo-side writer, schema, manifest and renderer.
- The Hyprland page's Layout, Input, Visual and Aesthetics, Animations, and
  Autostart sections.
- Border colors (derived at runtime).
- Idle.

**Phase C: displays.**
- The Hyprland page's Displays section: mode, scale, position, transform,
  enable, and HDR and color management.
- This comes last because it is the only part that can leave a screen
  unusable, and it needs the confirm-or-revert flow.

### Out of scope

- The Niri page, `NiriConfig`, the `niri` `MonitorConfigOption`, and the
  fork's `WM` abstraction. The pages use `WM` only for
  `compositor === "niri"` checks, which become constant.
- `get_keybinds.py`, which is used by the cheatsheet and not by settings.
- About's "Update dots" (clones end4-pC into `~/.config/quickshell`) and
  "System update" (`yay -Syu`).
- Profile's hostname field (`hostnamectl set-hostname` fights
  `networking.hostName`) and its online preset download (fetches third-party
  JSON from the network and applies it over config.json).
- Fork-only features behind dropped controls, as described above.

## Design

### Where each kind of value lives

| Kind | Source of truth (repo) | Consumed by | Live apply |
|---|---|---|---|
| ii shell options (config.json) | `hosts/<host>/illogical-impulse/config.json`, reached through a directory symlink | ii at runtime | ii's own `FileView` watcher |
| Hyprland options (`hl.config` keys) | `hosts/<host>/ii-settings.json`, `hyprland` object | Nix at build time, renders `custom/krane_gui.lua` | writer re-renders the same file, then `hyprctl reload config-only` |
| Monitor fields | `hosts/<host>/ii-settings.json`, `monitors` object | Nix at build time, same file | same file, full `hyprctl reload`, behind confirm-or-revert |
| Idle timeouts | `hosts/<host>/ii-settings.json`, `idle` object | Nix, `krane.hypr.idle`, applied to `hypridle.conf` at activation | writer edits live `hypridle.conf` and restarts hypridle |
| Animation preset | `hosts/<host>/ii-settings.json`, `animationPreset` | Nix, same file | same file, `config-only` reload |
| Border colors (role and opacity) | config.json (`hyprland.borderColor`) | ii at runtime | derived color written to `shellOverrides/main.lua` |
| Hyprlock 12h clock | config.json (existing time format key) | ii at runtime | derived: sed on `hyprlock.conf` |

Rule of thumb: **persist choices, derive consequences.** A value the user picks
is persisted in the repo. A value computed from other state (a border color
from the wallpaper palette, hyprlock's clock token from the time format) is
re-derived at runtime and never written to the repo. Persisting it would
change a tracked file on every wallpaper change.

### Design A: config.json pages

- **Directory symlink.** `~/.config/illogical-impulse` becomes a symlink
  (`home.file` with `config.lib.file.mkOutOfStoreSymlink`) to
  `~/.dotfiles/hosts/<host>/illogical-impulse` (`/home/<krane.user.name>/...`,
  since the user is per host). The repo path comes
  from a new option, `krane.dotfilesDir`, defaulting to
  `${config.home.homeDirectory}/.dotfiles`, which `install.sh` and
  `modules/nixvim/options.nix` already assume.
- **Why the directory and not the file.** `switchwall.sh` updates config.json
  with `jq ... > config.json.tmp && mv config.json.tmp config.json`, which
  replaces a file symlink with a regular file on every wallpaper change. With
  the directory symlinked, the temp file and the rename both happen inside the
  repo directory, so nothing is replaced.
- **What stays compatible.** The soymou module's `mkdir -p` and its
  `[ ! -f config.json ]` seed check both follow the symlink. Scripts that read
  `$XDG_CONFIG_HOME/illogical-impulse/config.json` keep working.
- **Migration.** A new activation entry, `kraneIiConfigMigrate`, runs before
  `writeBoundary`, so it runs before home-manager changes anything, like
  `checkLinkTargets` does. If `~/.config/illogical-impulse` is a real
  directory:
  - If the repo directory has no `config.json`, the entry copies the real
    directory into the repo with `cp -an` and logs that it did. The
    home-manager link step then moves the real directory aside as
    `illogical-impulse.hm-bak` (`backupFileExtension`), so nothing is lost.
  - If both exist and `config.json` differs (`cmp`), the entry **fails
    activation** before any change, with both paths and the instruction to
    keep one by hand.
  - If both exist and are identical, it proceeds.

  The entry honours `$DRY_RUN_CMD`. A dry run prints the planned copy or the
  conflict and changes nothing.
- **Ignore rules.** `hosts/<host>/illogical-impulse/.gitignore` ignores
  `*.tmp` and `ai/` (it may hold personal prompts). `actions/` is tracked
  (resolved decision 3).
- **New hosts.** Hosts are the directories under `hosts/`, and
  `install.sh --new-host` scaffolds one from `templates/host/`. The template
  carries both per-host files, `illogical-impulse/.gitignore` and
  `ii-settings.json` (`{}`), copied as is (no placeholders) by
  `render_host_templates`. `install.sh --self-test-check-scaffold` and
  `just check-new-host` check that both exist. Without them a new host's
  first activation warns about a missing repo directory, and every
  persistent Hyprland control fails, because the writer never creates
  `ii-settings.json`.
- **Privacy review before the first commit.** Before any host's `config.json`
  is committed for the first time, the user reads the whole file (not just a
  diff) for personal data, such as the weather city, a booru username, or
  `ai.extraModels` entries, and removes or resets what should not reach the
  GitHub remote. There is no automatic scrubbing (resolved decision 7). This
  is an explicit step in phase A's commit, below.
- **No Nix involvement.** Nix never reads config.json. The only effect of the
  file being in the repo is that it can be committed.
- **Per-page changes.**
  - General: the 12h/24h switch keeps writing its config.json key. Its
    `sed -i` on `~/.config/hypr/hyprlock.conf` moves to a small runtime sync
    in the main shell, run when Config becomes ready and on
    `configreloaded`, which makes `hyprlock.conf` match the key. A switch
    that recopies `hyprlock.conf` is followed by `kraneIiHyprReload`, which
    triggers the sync.
  - About: shows the pinned dots-hyprland revision, the number of applied
    patches (baked in at build time) and `krane.dotfilesDir`. The update
    buttons are removed.
  - Profile: display name, avatar and description (config.json) are kept.
    Hostname is shown read-only. Local preset import and export are kept.
    Online presets are removed.
  - Background, Bar, Interface, Quick, Services: fork page bodies, with
    controls for features that are not present removed (see the porting
    rule).
  - Autostart apps (on the Hyprland page, but config.json-only):
    `autostart.py`'s lock file moves from `/tmp/qs-autostart.lock` to
    `$XDG_RUNTIME_DIR`. This repo sets no `boot.tmp.*`, so `/tmp` is not
    cleared at boot. A lock file there would block autostart after the first
    boot, until tmpfiles ages it out.

### Design B: Hyprland option writers

#### Pieces

1. **Repo data file** `hosts/<host>/ii-settings.json`, committed as `{}` for
   every host in phase B's first commit, so it is always tracked. The format
   is sparse deltas: only keys the user has changed. Keys are sorted, indent
   is 2 spaces, and the file ends with a newline, so diffs stay small.

   ```json
   {
     "animationPreset": "normal",
     "hyprland": {
       "decoration:rounding": 12,
       "general:gaps_in": 4
     },
     "idle": { "lock": 600, "screenOff": 900, "suspend": 0 },
     "monitors": {
       "DP-2": { "bitdepth": 10, "cm": "hdr" }
     }
   }
   ```

2. **Schema and writer, in this repo.** `pkgs/krane-ii-settings/`, a
   `writers.writePython3Bin` using only the standard library, installed in
   `home.packages`. The schema is one Python table, the allowlist of keys the
   GUI may write. Each entry has a Hyprland type (bool, int with range, float
   with range, string enum, color) and is checked against Hyprland 0.56
   before it goes on the list. The writer has these subcommands:
   - `set <section> <key> <value>` and `reset <section> <key>`: validate
     against the schema and the manifest's Nix-owned key set, take a lock with `flock` on
     `$XDG_RUNTIME_DIR/krane-ii-settings.lock`, update the repo file
     atomically (temp file in the same directory, then `os.replace`), and do
     nothing if the content did not change. Then render the live file and
     reload.
   - `render --json <file> --manifest <file>`: print `krane_gui.lua`. Nix
     uses this same subcommand at build time (below), so one renderer serves
     both build time and runtime.
   - `get`: print the effective state as JSON (the repo file, the manifest
     baselines and the locked keys), so the page can show values that
     `hyprctl getoption` cannot return (idle, animation preset, lock state).

   - `apply`: re-render the live file from the repo file and reload. Use it
     after a hand edit or a `git checkout` of the repo file, so the change is
     live without waiting for a switch.

   The Nix wrapper bakes in a store path to the host's **manifest**, a JSON
   generated from Nix. It holds:
   - the host name;
   - the repo file path
     (`${krane.dotfilesDir}/hosts/${hostName}/ii-settings.json`);
   - the **Nix-owned key set**: every leaf of `krane.hypr.settings`,
     flattened to `a:b:c`, plus `krane.hypr.guiLocked`, plus the non-null
     fields of each `krane.hypr.monitors` entry, plus `idle` when Nix sets
     it;
   - the host's monitor baselines and the idle baseline.

   There is no mutable state file, and the manifest always matches the
   running generation. The writer calls `hyprctl`, `python3` and `flock` by
   absolute store paths.

3. **Nix consumption.** A new `modules/home/ii-settings.nix`:
   - reads the host's file with `lib.importJSON`, falling back to `{}` when
     the path does not exist;
   - builds the rendered file with
     `runCommand "krane-hypr-custom-krane_gui.lua" { } "${writer}/bin/krane-ii-settings render ... > $out"`
     and adds it to `krane.hypr._rendered."custom/krane_gui.lua"` (an **owned**
     file in `illogical-impulse.nix`, which the classification assertion then
     requires). This is plain build-time `runCommand` on repo files, not
     import-from-derivation, since the result is only installed and never read
     back into evaluation. `checks.lua-syntax` covers it automatically;
   - maps `idle` onto `krane.hypr.idle` (see Idle);
   - asserts that the file's keys and the Nix-owned key set do not overlap,
     naming both locations, and that every key is in the schema. The writer
     dumps the schema to JSON at build time, so Nix and the writer share one
     list.

4. **Load order.** `hypr-config.nix`'s `monitorsFile` renderer (Nix, at build
   time, on every host, even when the JSON is `{}`) appends this trailer to
   the owned `monitors.lua`, after the monitor rules and after
   `krane.hypr.extraMonitorsLua` (which stays, for tarmantria's hotplug
   scaling):

   ```lua
   if is_file_exists(HOME .. "/.config/hypr/custom/krane_gui.lua") then
       require("custom.krane_gui")
   end
   ```

   `monitors.lua` is the last file `hyprland.lua` loads before
   `hyprland.shellOverrides.main`. So GUI values load after everything
   `krane.hypr.*` renders (general, rules, keybinds and the monitor rules),
   and before ii's transient shell overrides.

5. **ii-side patch (small).** `services/HyprlandConfig.qml`'s persistent
   callers (`HyprlandConfigOption.setValue`/`reset` and the Hyprland page)
   call `krane-ii-settings set|reset hyprland <key> <value>` through a
   `Process`, not `execDetached`, so the exit code and stderr are captured.
   The existing `set/setMany/resetMany` that write `shellOverrides/main.lua`
   stay for transient callers: game mode, the anti-flashbang shader, and
   border colors.

   The fork page's `Component.onCompleted` `setMany` is **removed**. It pushes
   the fork's config.json mirror (`Config.options.hyprland.*`) into Hyprland
   every time the page opens. Its defaults (for example `kbLayout`) would
   silently override the values set in `display.nix`. Controls read live
   values through upstream's `HyprlandConfigOption` (`hyprctl getoption -j`)
   and refresh on `configreloaded`. The fork's `hyprland.*` config.json
   subtree is not ported, except `borderColor` and `autostartApps`.

   The page also watches the repo file (`FileView` with `watchChanges`, path
   taken from `krane-ii-settings get`). When the file changes outside the GUI
   (hand edit, `git checkout`, a rebase), the page shows "ii-settings.json
   changed outside settings: Apply now". Apply runs `krane-ii-settings apply`.
   Nothing is applied automatically, so checking out another branch never
   silently changes the running session.

#### Ownership (one rule)

**Every key has exactly one owner: Nix or the GUI file, never both.**

- Nix owns every key it sets: any `krane.hypr.settings` leaf, the non-null
  fields of a `krane.hypr.monitors` entry, and `idle` when a host sets it.
  Nix also owns anything in `krane.hypr.guiLocked`, a new `listOf str` option
  for keys Nix wants left at the upstream default. The page shows Nix-owned
  controls disabled with "Set in Nix (hosts/<host>/display.nix or
  modules/home)". The writer refuses them.
- The GUI owns every other schema key, as a sparse delta in its file.
- The overlap check is an eval-time assertion (Nix, above), not a runtime
  precedence rule. A later `display.nix` edit that sets a key the GUI file
  already holds fails `nix flake check` with both locations named, instead of
  being silently shadowed. The fix is to delete one of the two. A plain
  module-system merge would also error on differing values, but not on
  identical ones, and it would put the GUI values into `custom/general.lua`,
  which breaks live reset (next point).
- The GUI's values live in their own file, `custom/krane_gui.lua`, not merged
  into `custom/general.lua`. Resetting a key removes it from that file, and a
  `config-only` reload re-evaluates the whole Lua config, so the Nix or
  upstream value comes back without a switch. If GUI values were merged into
  `custom/general.lua`, a reset could not take effect until the next switch.
- Consequence for today's hosts: every host sets `input:kb_layout` and
  `input:kb_variant` in `display.nix`, and `qwertz-binds.nix` depends on
  them, so the GUI cannot change them. On tariognatha, `idleTimeouts = false`
  makes idle Nix-owned, and `input:*` device settings stay in Nix. To hand a
  key to the GUI, delete it from Nix. See resolved decision 4.
- Game mode keeps working. It writes `shellOverrides/main.lua`, which loads
  after `krane_gui.lua`, so it overrides GUI values while active, and its
  `resetMany` falls back to the GUI value.

#### Border colors

The fork's `applyBorderColors` writes resolved rgba values into
`shellOverrides/main.lua` when Config becomes ready and on every palette
change. That file is wiped at switch. The patch adds one more trigger: on
`configreloaded`, re-apply if the option is enabled. Every switch ends in
`kraneIiHyprReload`, so borders come back without restarting the shell.

To avoid a reload loop (write, then autoreload, then `configreloaded`, then
write again), `hyprconfigurator.py` is patched to skip the write when the
content is unchanged. The config.json keys `hyprland.borderColor.*` (role and
opacity) are the persisted choice.

#### Animation presets

The fork keeps the preset Lua as Python strings and tells the user to add a
`require` line to `hyprland.lua` by hand. The port moves the three presets
into Lua files in the dots-hyprland series (`hypr/hyprland/animationPresets/`
with `fast.lua`, `normal.lua` and `niri.lua`), and deletes the Python copies
and the notice box. `animationPreset` in the JSON renders to
`require("hyprland.animationPresets.<name>")` inside `krane_gui.lua`. The
schema enum is `fast`, `normal` and `niri`. Absent means ii's stock
animations. `animations:enabled` is an ordinary `hyprland` key.

#### Idle

- `krane.hypr.idle` is a new option with `lock`, `screenOff` and `suspend` as
  ints in seconds, where 0 disables. The defaults are ii's 300, 600 and 900.
- `krane.hypr.idle` defaults to `null`, meaning not set by Nix.
  `idleTimeouts = false` keeps working as a compatibility shorthand that sets
  it to all zeros, which makes idle Nix-owned. When Nix leaves it `null`,
  the JSON `idle` object, if present, is used. Otherwise ii's defaults apply.
  Setting both is the eval error from the ownership rule.
- Activation replaces the `hypridle.conf` sed entry in `iiPatches` with a run
  of the copied `hypridleconfigurator.py`, invoked with the absolute path of
  `pkgs.python3`, `--file hypridle.conf`, and the three values. It is guarded
  by `[ -f ]` and honours `$DRY_RUN_CMD`.
- Live: the writer runs the same script on the live file, then runs
  `pkill -x hypridle; setsid -f hypridle`. The fork's `setIdle` already does
  this, and ii starts hypridle through a plain `hl.exec_cmd`, so there is no
  systemd unit to restart instead.
- tariognatha keeps `idleTimeouts = false` (resolved decision 4), so its idle
  controls are shown as "never" and disabled, with the "Set in Nix" reason.

#### Python on NixOS

The fork calls `python3` from `PATH`. The port runs the scripts directly
through upstream's venv shebang
(`source $ILLOGICAL_IMPULSE_VIRTUAL_ENV/bin/activate`). The soymou module
backs that path with a fake venv over its `pythonEnv`, so there is one
interpreter and no dependence on `PATH`. All the ported scripts are
standard-library only.

### Design C: displays

- `hypr-config.nix`'s monitor submodule gains `cm` (enum), `sdrbrightness`,
  `sdrsaturation`, `sdr_min_luminance`, `sdr_max_luminance`, `min_luminance`,
  `max_luminance` and `max_avg_luminance`. All are `nullOr` and omitted when
  null. **Each field name is checked against Hyprland 0.56's Lua monitor
  parser before it is added**, because an unknown field is a hard error at
  start.
- The JSON `monitors.<output>` holds fields for that output. Ownership
  follows the one rule, per field:
  - **For an output in `krane.hypr.monitors`,** Nix owns every field that is
    non-null there. `output`, `mode`, `position` and `scale` always count as
    set, since they have defaults. The GUI may only fill the null fields
    (`transform`, `vrr`, `bitdepth`, `cm`, the SDR and HDR luminance
    fields). So on any host today, HDR and color management are
    GUI-editable, while resolution, scale and position are shown with "Set
    in Nix".
  - **For an output not in `krane.hypr.monitors`,** the GUI owns the whole
    rule, and the writer stores a complete rule (output, mode, position,
    scale) taken from `hyprctl monitors all -j`. If that output is later
    added to `display.nix`, evaluation fails on the overlap, so a frozen GUI
    rule can never silently shadow a new Nix one.
  - **Rendering.** The renderer emits one complete `hl.monitor` rule per
    output in the file: the manifest baseline plus the GUI fields. It emits a
    complete rule because a later `hl.monitor` for the same output replaces
    the earlier rule rather than merging fields.
- `monitor_configurator.py` is not ported. Its only job was editing
  `monitors.lua`, which the writer replaces. `monitor_caps.py` is ported
  unchanged; it reads EDID from `/sys/class/drm`.
  `MonitorConfigOption.save` calls `krane-ii-settings set monitor ...`, and
  its `--dump-all` read of `monitors.lua` becomes `krane-ii-settings get`.
- **Confirm or revert, with the timer outside the UI.**
  - `krane-ii-settings try monitor ...` applies the change to the live
    `krane_gui.lua` only, followed by a full `hyprctl reload`. The monitor
    reapply needs a full reload, because `config-only` skips it.
  - It then starts a detached revert timer
    (`systemd-run --user --on-active=15s krane-ii-settings apply`), which
    re-renders the live file from the unchanged repo file.
  - The page shows "Keep these display settings? Reverting in 15 s". "Keep"
    calls `krane-ii-settings confirm`, which stops the timer unit and writes
    the repo file.
  - The timer lives outside the settings process, so a crash of the settings
    window, or a screen too broken to click on, still reverts.
- **First-boot check.** A display change that was kept is written with
  `"bootConfirmed": false` on that output. Hyprland reads the live
  `krane_gui.lua` at boot, which survives reboots and is replaced only at a
  switch. So the next login checks it:
  - A `krane.hypr.execOnce` entry, `krane-ii-settings boot-check`, runs after
    the session is unlocked, detected by waiting for the lock IPC to report
    unlocked, the same way `lock-on-start.nix` waits for it.
  - If any output is unconfirmed, it shows the same confirm dialog with the
    same detached timer. On timeout it removes the unconfirmed fields from the
    repo file and the live file, then reloads.
  - On Keep it drops the flag.
  - Unlock works blind (type the password, Enter), so a black screen after
    reboot recovers by itself within 15 s of unlocking.
  - The flag is part of the schema and is ignored by the renderer.
- **HDR on Nvidia (tariognatha, DP-2).** The HDR controls are shown only when
  `monitor_caps.py` reports HDR from the EDID. Turning HDR on sets
  `cm = "hdr"` and `bitdepth = 10` together. 3840x2160@240 at 10 bits needs
  DSC. If the link cannot carry it, Hyprland falls back or fails the mode, and
  confirm-or-revert covers both cases. tarmantria's panel is on the iGPU, and
  HDR is expected to be unavailable there. taractias is untested.

### Hyprland reload behaviour

- `config-only` reloads re-run the whole Lua config, including
  `require("custom.krane_gui")`, and do not re-run `hyprland.start` execs.
  `execs.lua` keeps every exec inside that event, and `kraneIiHyprReload`
  already relies on this.
- Only display changes use a full reload.
- The writer detects the running instance the same way `kraneIiHyprReload`
  does. When no Hyprland is running, it skips the reload and still writes the
  file.

## Error handling

- **Repo file cannot be parsed** (for example, a merge conflict in progress):
  the writer refuses to write, exits non-zero with the parse error, and the
  page shows it in a `NoticeBox`. The live value is not changed either. The
  GUI never overwrites a file it cannot read.
- **Repo file missing** (repo not at `krane.dotfilesDir`, or the file is not
  tracked yet): refuse with "not persisted: <path> missing". The writer never
  creates the file, because a new untracked file would be invisible to Nix
  and would silently not persist.
- **Nix-owned or unknown key:** refused with a message. Nix asserts the same
  thing at eval time, so a hand-edited JSON fails `nix flake check`, not
  Hyprland start.
- **A value Hyprland rejects at runtime:** after a reload, the writer checks
  `hyprctl configerrors`. If it is non-empty and names `krane_gui.lua`, it
  reverts the repo and live file to the previous content and reports the
  error.
- **A display config that is broken at boot** (confirmed, but for example the
  cold-boot HDR link fails): the first-boot check reverts it 15 s after a
  blind unlock. If that also fails (for example, the session never reaches
  unlock), from a TTY, remove the `monitors.<output>` entry
  from `hosts/<host>/ii-settings.json` and switch. As a faster escape
  without a rebuild, `rm ~/.config/hypr/custom/krane_gui.lua && hyprctl reload`
  drops every GUI delta until the next switch. Both go into
  `docs/II-INTEGRATION.md`.
- **A concurrent editor** (nvim, git checkout) replacing the file while the
  writer runs: the atomic `os.replace` means readers see either the old or
  the new file. The flock serialises GUI writers. Edits from outside the GUI
  are kept, because the writer re-reads the file under the lock before each
  write. They reach the running session on "Apply now" (the page's file
  watch), on `krane-ii-settings apply`, or at the next switch, whichever
  comes first. Nix only reads the repo at a switch, so this lag is inherent.
- **A pin bump breaks a settings patch:** `applyPatches` fails and names the
  patch. Resolve it in the clone as the fixes spec describes.

## Testing

### Build and static (every phase)

1. `nix flake check`. It includes `lua-syntax` (now covering
   `custom/krane_gui.lua` for every host) and two new checks:
   - `ii-settings-writer`: runs the writer's Python unit tests (schema
     validation, sparse write, no-op on unchanged content, refusal on bad
     JSON, locked key, unknown key, render golden files);
   - `ii-settings-render`: renders a fixture JSON with every schema key and
     every monitor field against one fixed stock host's manifest
     (`taractias`, reached as `home-manager.users.${cfg.krane.user.name}`
     like `lua-syntax`), then runs `luac -p`. A fixed host, so a new host
     that sorts first cannot break it.
2. `nixos-rebuild dry-build --flake .#<host>` for all three hosts.
   After the render commit and after the monitor-field commit, also
   `just check-new-host` (committed work only: it tests a worktree of
   `HEAD`), which evaluates a host scaffolded from `templates/host/` with a
   catch-all `output = ""` monitor and a user other than `krane`.
3. `nix eval` of the rendered `custom/krane_gui.lua` for all three hosts
   with `{}`. Each must contain only the header.

### Runtime, every phase and every host

4. After the switch: no new QML errors in `qs log`, and `hyprctl configerrors`
   is empty. Run two consecutive switches, per `docs/VERIFY.md`.

### Acceptance checks per page

| Page / control | Check | Hosts |
|---|---|---|
| Settings window | `SUPER + I` opens it. All in-scope pages load. Closing it leaves the bar running. | all |
| Quick, General, Bar, Background, Interface, Services | Change one control per page. `git -C ~/.dotfiles diff hosts/<host>/illogical-impulse/config.json` shows exactly that key. The value survives a switch and a reboot. | all |
| Directory symlink | `readlink ~/.config/illogical-impulse` points at the repo. After a wallpaper change (`switchwall.sh`) it is still a symlink, and `config.json` in the repo has the new `wallpaperPath`. | all |
| Migration | On a host with a real `~/.config/illogical-impulse`, the first switch copies it into the repo, and `illogical-impulse.hm-bak` exists. | tarmantria first |
| General 12h clock | Toggle to 12h and lock with hyprlock (`hyprlock` directly). The clock shows AM/PM. After a switch, the setting is still correct without opening settings. | any host |
| About | Shows the pin rev and `~/.dotfiles`. There are no update buttons. | all |
| Profile | Display name persists in the repo config.json. The hostname field is read-only and shows the current host's name. | any host |
| Autostart | Add an app, reboot. It starts on the next boot and the one after, and there is no lock file in `/tmp`. | any host |
| Visual (gaps, rounding, blur, opacity, border size) | Set `general:gaps_in` to 12. `hyprctl getoption general:gaps_in` shows 12 within 1 s, and the repo JSON shows the key. Reset: the key is gone and the value is back to the baseline without a switch. Set it again, switch twice, reboot: still 12. | all |
| Input (repeat, follow mouse, numlock, touchpad) | As for Visual. Touchpad keys on the laptops only. | all, touchpad on laptops |
| Ownership | The keyboard layout control is disabled with "Set in Nix". `krane-ii-settings set hyprland input:kb_layout us` exits non-zero. A hand-edited JSON with that key fails `nix flake check`, naming both files. Also: set gaps in the GUI, then add `general.gaps_in` to `display.nix`. `nix flake check` fails naming both. | all |
| External edit | Change `general:gaps_in` in the repo JSON by hand while settings is open. The "changed outside settings" notice appears. Apply now sets the live value. With no Apply, nothing changes until a switch. | any host |
| Migration conflict | With differing `config.json` in both the real dir and the repo dir, the switch fails before changing anything and names both paths. A dry run prints the same thing. | tarmantria |
| Game mode interplay | With gaps set to 12 in the GUI, toggle game mode on (gaps 0) and off: gaps are back to 12. | any host |
| Border colors | Enable custom colors, change the wallpaper: borders follow the palette. The repo `ii-settings.json` has no diff. After a switch, the custom colors are back with no qs restart. `shellOverrides/main.lua` is not rewritten in a loop (`inotifywait` shows at most one write per change). | any host |
| Animation presets | Pick "fast": `krane_gui.lua` contains the require, and window-open animations change. There is no "add a require line" notice. Switch: it persists. | any host |
| Idle | On a laptop, set lock 60 and suspend 0. `hypridle.conf` has one lock listener at 60 and no suspend listener. hypridle restarted (new PID). Idle 60 s locks. Switch twice: still so. On tariognatha, the idle controls are disabled with "Set in Nix". | tarmantria, tariognatha |
| Displays: ownership | On any host, a Nix-declared output's resolution, scale and position are disabled ("Set in Nix"), and its HDR and color fields are editable. | any host |
| Displays: revert | With a monitor that is not in `display.nix` (tarmantria's `HDMI-A-1` and tariognatha's `DP-1` and `DP-2` are declared, so a further output), change its position (on a laptop's Nix-declared eDP-1, change its transform instead: position is Nix-owned) and wait 15 s: it reverts and the repo has no diff. Change it again, then `pkill -f settings.qml` inside the window: it still reverts (the timer is outside the UI). Change it and confirm: the repo JSON has the entry with `bootConfirmed: false`. Reboot and unlock: the dialog appears. Keep clears the flag. Let a second change time out after reboot: it is removed from the repo. | tarmantria; any host with an extra display output beyond those in `display.nix` |
| Displays: hotplug | tarmantria's `extraMonitorsLua` (`scale_internal`) re-sends eDP-1's rule with only output, mode, position and scale on every monitor add or remove. With a kept GUI transform on eDP-1, unplug and replug `HDMI-A-1`: the scale follows, and the transform either stays or is lost until the next reload. If it is lost, `docs/II-INTEGRATION.md` records it as a known limitation. | tarmantria |
| Displays: HDR | On an HDR-capable output, turn on HDR: `hyprctl monitors -j` shows `colorManagementPreset` `hdr` and a 10-bit format, or the change is reverted by the timer. If kept, it survives a cold boot (first-boot check confirmed). SDR brightness changes are visible. | any host with an HDR-capable display |
| Displays: laptop | eDP-1 scale, mode and position are disabled ("Set in Nix"); a transform change and its revert work. HDR controls are hidden (no EDID HDR). | tarmantria; taractias once verified |
| Parse error | Put a conflict marker in `ii-settings.json` and change gaps in the GUI. An error is shown, the file is untouched, and gaps are unchanged. | any host |
| Hyprland rejects a value | Temporarily add a bad key to the schema in a dev build and set it. The writer reverts and reports the error, and `hyprctl configerrors` ends empty. | any host, dev only |

taractias checks wait until its hardware is verified, as in the fixes spec.

## Commits

Planned structure for the implementation. The user commits by hand.

1. Phase A: `patches/ii/05-settings/` (widgets, `Config.qml` subset, window
   list, one patch per page), `krane.dotfilesDir`, the directory symlink and
   migration entry, and the per-host `illogical-impulse/` directories
   including their `.gitignore`, also in `templates/host/` (with the
   `install.sh` and `check-new-host` changes). Each host's `config.json` is first committed
   only after the privacy review in Design A.
2. Phase B:
   - one commit adding `hosts/*/ii-settings.json` and
     `templates/host/ii-settings.json` as `{}`, `pkgs/krane-ii-settings`
     and its checks;
   - one for `modules/home/ii-settings.nix`, `guiLocked`, the `monitors.lua`
     trailer and the `krane_gui.lua` owned file;
   - one for idle (`krane.hypr.idle` replacing the sed entry);
   - one for the ii patches (`HyprlandConfig`, page, presets, border-color
     trigger).
3. Phase C: monitor submodule fields, then the display patches plus
   confirm-or-revert.
4. Docs: `docs/II-INTEGRATION.md` gets a "Settings persistence" section (the
   value table, the ownership rule, the escape hatches) and the ported and
   dropped control table. Its existing text that calls
   `~/.config/illogical-impulse` excluded, ii-owned state (the copy-step
   section and the `launchOnStartup` bullet under "Patched files") is updated
   to say the directory is now a symlink into the repo. It also records the
   tarmantria hotplug limitation if the acceptance check finds one.
   `docs/VERIFY.md` gets the per-page checks. `README.md` and `LICENSE`
   credit pctrade/end4-pC for the `05-settings` port, next to the
   `01-fixes` backports.

## Resolved decisions

1. **Track `~/.config/illogical-impulse` in the repo.** Yes, per host, even
   though config.json changes on every wallpaper switch (`wallpaperPath`) and
   will show up in `git status` often. It is the only way config.json pages
   persist in the repo. The user commits selectively.
2. **Per-host config.** One settings file per host (`config.json` and
   `ii-settings.json` under `hosts/<host>/`). A shared
   `modules/home/ii-settings.common.json` layer can be added later without
   changing the ownership rule.
3. **`ai/` and `actions/` under the config dir.** Track `actions/`, ignore
   `ai/`, which may hold personal prompts.
4. **Keys stay in Nix.** Whatever `display.nix` sets stays locked in the GUI:
   keyboard layout everywhere, tariognatha's idle (`idleTimeouts = false`),
   and every output's resolution, scale and position, including the monitor
   keys. The GUI edits everything else, plus HDR and color on Nix-owned
   outputs. Moving a key later means deleting it from `display.nix` in the
   same commit that adds it to `ii-settings.json`. Keyboard layout stays in
   Nix regardless, because `qwertz-binds.nix` depends on it.
5. **Fork-only features behind dropped controls** (centered wallpaper,
   dynamic island, visualizer styles, and similar) are not ported. Each would
   be its own follow-up spec.
6. **Profile page.** Keep name, avatar, description and local preset import
   and export.
7. **Privacy.** config.json holds fields such as the weather city and a booru
   username, and the repo has a GitHub remote. The user reviews each host's
   `config.json` before its first commit, as an explicit step (Design A,
   Commits). There is no automatic scrubbing.
