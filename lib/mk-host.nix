# mkHost { hostName, system, role ? "desktop", hostDir ? ../hosts/<hostName>, extraModules ? [ ] }
#   -> nixosSystem
# Shared host builder: wires disko, sops-nix, home-manager and the soymou
# module, at the HM level to avoid a dconf eval error.
{ inputs }:
let
  # Servers follow the stable channel: the stable nixpkgs, home-manager and nixvim inputs
  # stand in under their usual names, so every module that reads inputs.nixpkgs (for
  # example the nix registry) sees stable on servers. Desktops get `inputs` unchanged.
  inputsFor =
    role:
    if role == "server" then
      inputs
      // {
        nixpkgs = inputs.nixpkgs-stable;
        home-manager = inputs.home-manager-stable;
        nixvim = inputs.nixvim-stable;
      }
    else
      inputs;
in
{
  hostName,
  system,
  # Picks modules/{nixos,home}/<role> next to common/; "desktop" also gets the
  # illogical-impulse home-manager module.
  role ? "desktop",
  # Host module directory; only the flake's server-eval check points this elsewhere.
  hostDir ? ../hosts/${hostName},
  extraModules ? [ ],
}:
let
  roleInputs = inputsFor role;
in
roleInputs.nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = {
    inherit hostName role;
    inputs = roleInputs;
  };
  modules = [
    {
      networking.hostName = hostName;
      # mkDefault: the desktops' hardware-configuration.nix set the same value at the same
      # priority (equal values merge without conflict). A non-x86 host would not import
      # such a file, or would override.
      nixpkgs.hostPlatform = roleInputs.nixpkgs.lib.mkDefault system;
      # useGlobalPkgs (not a second overlays list) gets ii-fixes to both
      # NixOS and home-manager pkgs.
      nixpkgs.overlays = import ../overlays;
      nixpkgs.config.allowUnfree = true;
    }
    roleInputs.disko.nixosModules.disko
    roleInputs.sops-nix.nixosModules.sops
    roleInputs.home-manager.nixosModules.home-manager
    # Role before common, so list-valued options (environment.systemPackages, extraGroups,
    # shell init text, ...) merge with the role's entries first, as the pre-split flat module
    # list ordered them for the modules where it matters. Common is not a strict prefix
    # of the old order: nix-settings, locale, users, user and keyboard used to load before
    # the desktop modules and now load after them, so only order-insensitive options may live
    # there. The home-manager side below has no such constraint, its order is free.
    ../modules/nixos/${role}
    ../modules/nixos/common
    hostDir
    (
      { config, ... }:
      {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          # Mandatory: soymou's activation step replaces ~/.config/fish
          # every switch. Without this, the next switch collides with it.
          backupFileExtension = "hm-bak";
          extraSpecialArgs = {
            inherit hostName role;
            inputs = roleInputs;
            # modules/nixos/common/user.nix's krane.user, so home-manager modules read the
            # account name and git identity from the same per-host place.
            kraneUser = config.krane.user;
          };
          users.${config.krane.user.name}.imports =
            roleInputs.nixpkgs.lib.optional (role == "desktop")
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
                  patched = roleInputs.nixpkgs.legacyPackages.${system}.applyPatches {
                    name = "illogical-flake-kde-platformtheme";
                    src = roleInputs.illogical-flake;
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
                      lib = roleInputs.nixpkgs.lib;
                      root = ../patches/ii;
                      sortedNames =
                        pred: dir: lib.sort lib.lessThan (builtins.attrNames (lib.filterAttrs pred (builtins.readDir dir)));
                      patchesIn =
                        dir: map (n: dir + "/${n}") (sortedNames (n: t: t == "regular" && lib.hasSuffix ".patch" n) dir);
                    in
                    lib.concatMap (d: patchesIn (root + "/${d}")) (sortedNames (_n: t: t == "directory") root);
                  patchedDotfiles = roleInputs.nixpkgs.legacyPackages.${system}.applyPatches {
                    name = "dots-hyprland-patched";
                    src = roleInputs.illogical-flake.inputs.dotfiles;
                    patches = [ ../patches/illogical-flake-cheatsheet-fkeys.patch ] ++ iiSeries;
                  };
                  iiInputs = {
                    inherit (roleInputs.illogical-flake.inputs) quickshell nur;
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
            ++ [
              roleInputs.nix-index-database.homeModules.nix-index
              ../modules/home/common
              ../modules/home/${role}
            ];
        };
      }
    )
  ]
  ++ extraModules;
}
