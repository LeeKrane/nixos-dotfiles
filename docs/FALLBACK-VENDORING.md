# Fallback: self-vendoring dots-hyprland

The soymou module is a single-maintainer project and has already gone
stale for a while. This repo depends on exactly one internal detail of
it, `home.activation.copyIllogicalImpulseConfigs` existing by that name,
and guards that dependency with an assertion
(`modules/home/illogical-impulse.nix`) so a rename or removal fails
loudly instead of silently misordering activation. If the soymou module
ever stops working entirely, rather than going quiet, this is the plan
to stop depending on it.

`krane.iiVendored.enable` (`modules/home/fallback-vendoring.nix`) is a
stub for this today: flipping it on fails the build with a pointer back
to this document. The steps below are what implementing it looks like.

## What doesn't change

- `dots-hyprland` (end-4's actual dotfiles) is already a pinned flake
  input (`flake.nix`). Only the layer that installs it, the soymou
  module, is being replaced.
- `modules/home/hypr-config.nix` and `modules/home/illogical-impulse.nix`'s
  DAG entry (`kraneIiOverrides`) stay exactly as they are: they run after
  whatever step puts the upstream dots on disk, and don't care how.
  `hosts/<host>/display.nix` doesn't change either.

## Steps

1. The copy step to replace is the soymou module's
   `home.activation.copyIllogicalImpulseConfigs`, which removes and
   recopies every top-level entry of `dots/.config` and
   `dots/.local/share` from `dots-hyprland`. Reimplement that as a plain
   `home.activation` entry, or as `home.file` symlinks per entry except
   `hypr`, which `kraneIiOverrides` still writes as regular files. Use
   the wipe-set table in
   [docs/II-INTEGRATION.md](II-INTEGRATION.md#wiped-on-every-switch) as
   the list to reproduce.
2. Once this repo owns the copy step, drop the DAG dependency:
   `kraneIiOverrides` can become a plain `entryAfter [ "writeBoundary" ]`
   instead of depending on an upstream name, and the
   `config.home.activation ? copyIllogicalImpulseConfigs` assertion can
   go with it.
3. Reproduce the env.lua truncation and general.lua append by porting
   both snippets verbatim from the soymou module's source at the pinned
   revision (see II-INTEGRATION.md) into this repo's copy step, ahead of
   where `kraneIiOverrides` appends its sentinel block. This ordering is
   the point of vendoring: re-read II-INTEGRATION.md's "Activation order"
   section while doing this.
4. The soymou module's package list also installs illogical-impulse
   (ii)'s runtime dependencies: Quickshell, matugen, the CLI tools ii's
   Lua and QML shells exec, and python packages for its own scripts. Port
   that list into a new `modules/home/` file, applying the `ii-fixes`
   overlay logic (`gnome-icon-theme` to `adwaita-icon-theme`, and
   whatever else has accumulated in `overlays/ii-fixes.nix`) directly,
   since no upstream input remains to intercept.
5. Pin `quickshell` as its own flake input at the revision the soymou
   module's `quickshell.nix` used, or the
   `github:quickshell-mirror/quickshell` mirror at that revision:
   upstream, `git.outfoxxed.me`, is occasionally slow or down. Reproduce
   the build flags, notably `-DSERVICE_POLKIT=ON`: with it set,
   quickshell compiles from source, so a real build is slow. Omitting it
   changes Quickshell's runtime behaviour, not only its build.
6. Reproduce whatever python environment,
   `python3.withPackages (ps: [ ... ])`, the soymou module wires up for
   ii's own scripts, rather than guessing at the package set.
7. For fonts, the soymou module's README lists the font families ii
   expects, already cross-referenced into `modules/nixos/fonts.nix`.
   Confirm that list stays complete once the module's own font side
   effects are gone.

## Rejected: patching the soymou module directly

nixpkgs dropped `gnome-icon-theme`. `overlays/ii-fixes.nix` aliases it
to `adwaita-icon-theme` instead. Patching the soymou module's source to
fix that throw was rejected: it forks the module and still breaks on
the next `flake.lock` update.

## What breaks, and what gets simpler

- Nothing breaks at the `krane.hypr.*` or `hosts/<host>/display.nix`
  layer: every option, the renderer, and `display.nix` are unchanged.
- Activation ordering stops depending on an external name: the
  `copyIllogicalImpulseConfigs` assertion goes away, since this repo owns
  the whole copy step.
- The `hypr/` custom files become fully ours: `kraneIiOverrides` becomes
  the only writer, not a corrective second pass after an upstream wipe.
- One more flake input to maintain directly (`quickshell`, previously
  indirect), a small increase in what `nix flake update` touches, in
  exchange for removing the single-maintainer dependency this document
  exists because of.
