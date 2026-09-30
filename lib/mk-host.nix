# mkHost { hostName, system, extraModules ? [ ] } -> nixosSystem
# Shared host builder: wires disko, sops-nix, home-manager and the soymou
# module, at the HM level to avoid a dconf eval error.
{ inputs }:
{
  hostName,
  system,
  extraModules ? [ ],
}:
inputs.nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = {
    inherit inputs hostName;
  };
  modules = [
    {
      networking.hostName = hostName;
      # useGlobalPkgs (not a second overlays list) gets ii-fixes to both
      # NixOS and home-manager pkgs.
      nixpkgs.overlays = import ../overlays;
      nixpkgs.config.allowUnfree = true;
    }
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops
    inputs.home-manager.nixosModules.home-manager
    ../modules/nixos
    ../hosts/${hostName}
    {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        # Mandatory: soymou's activation step replaces ~/.config/fish
        # every switch. Without this, the next switch collides with it.
        backupFileExtension = "hm-bak";
        extraSpecialArgs = {
          inherit inputs hostName;
        };
        users.krane.imports = [
          # HM level, not NixOS: soymou #19 dconf error.
          # Imported from a patched copy of the flake source rather than
          # homeManagerModules.default: illogical-flake pins Qt to qt6ct in three
          # places (quickshell wrapper --set, home.sessionVariables, custom/env.lua),
          # which detaches every Qt app from ii's kdeglobals theming. See
          # patches/illogical-flake-kde-platformtheme.patch. `inputs` mirrors the
          # flakeInputs set that illogical-flake's flake.nix hands to home-module.nix.
          # applyPatches comes from the bare nixpkgs for `system`, not the module
          # `pkgs` arg: the imported module's `imports` list is built from the
          # patched path, and deriving it from `pkgs` (which depends on `config`)
          # is an infinite recursion.
          (
            let
              patched = inputs.nixpkgs.legacyPackages.${system}.applyPatches {
                name = "illogical-flake-kde-platformtheme";
                src = inputs.illogical-flake;
                patches = [ ../patches/illogical-flake-kde-platformtheme.patch ];
              };
              # dots-hyprland (`inputs.dotfiles` below), not illogical-flake
              # itself: home-modules/dotfiles.nix copies ~/.config from
              # `inputs.dotfiles` at HM activation, so everything patched here
              # lives in that separate source, not the one `patched` above
              # rewrites. Two things are patched in:
              # - Cheatsheet's number-key collapsing regex matches F-keys
              #   containing a "1" digit (F1, F10, F11), mangling their
              #   rendered label, and drops F9 entirely (digit 9, no "1").
              #   See patches/illogical-flake-cheatsheet-fkeys.patch.
              # - Changes carried from pctrade/end4-pC and this repo's own ii
              #   work, kept as `git format-patch` series, one directory per
              #   sub-project under patches/ii/ (01-fixes, 02-translator, ...).
              #   Directories apply in lexical order, and the patches in each
              #   directory in lexical (= commit) order. A new sub-project only
              #   adds a directory. See docs/II-INTEGRATION.md
              #   "Backported fork fixes" for the workflow.
              # `lib` is the bare nixpkgs lib for the same reason
              # `applyPatches` is taken from bare nixpkgs above: anything
              # derived from the module's `config` would recurse infinitely.
              iiSeries =
                let
                  lib = inputs.nixpkgs.lib;
                  root = ../patches/ii;
                  sortedNames =
                    pred: dir: lib.sort lib.lessThan (builtins.attrNames (lib.filterAttrs pred (builtins.readDir dir)));
                  patchesIn =
                    dir: map (n: dir + "/${n}") (sortedNames (n: t: t == "regular" && lib.hasSuffix ".patch" n) dir);
                in
                lib.concatMap (d: patchesIn (root + "/${d}")) (sortedNames (_n: t: t == "directory") root);
              patchedDotfiles = inputs.nixpkgs.legacyPackages.${system}.applyPatches {
                name = "dots-hyprland-patched";
                src = inputs.illogical-flake.inputs.dotfiles;
                patches = [ ../patches/illogical-flake-cheatsheet-fkeys.patch ] ++ iiSeries;
              };
              iiInputs = {
                inherit (inputs.illogical-flake.inputs) quickshell nur;
                dotfiles = patchedDotfiles;
              };
            in
            {
              config,
              lib,
              pkgs,
              ...
            }:
            (import "${patched}/home-module.nix") {
              inherit config lib pkgs;
              inputs = iiInputs;
            }
          )
          inputs.nix-index-database.homeModules.nix-index
          ../modules/home
        ];
      };
    }
  ]
  ++ extraModules;
}
