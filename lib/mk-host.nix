{ inputs }:
let
  # Servers get the stable nixpkgs, home-manager and nixvim under the usual input names, so modules
  # reading inputs.nixpkgs see stable. nixpkgs-unstable keeps the desktop pin reachable.
  inputsFor =
    role:
    if role == "server" then
      inputs
      // {
        nixpkgs-unstable = inputs.nixpkgs;
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
  role ? "desktop",
  # Raspberry Pi board ("rpi4" | "rpi5", from hosts/<name>/host.nix) or null for everything
  # else. A board adds the nixos-raspberrypi modules; hosts add sd-image or disko themselves.
  # Needs system = "aarch64-linux" and role = "server".
  board ? null,
  hostDir ? ../hosts/${hostName},
  extraModules ? [ ],
}:
let
  roleInputs = inputsFor role;
  rpi = roleInputs.nixos-raspberrypi;
  # Per RPi board: the module that sets variant, kernel and firmware. Only the plain
  # overlays are injected (not inject-overlays-global, page-size-16k or a kernel override),
  # which would miss nixos-raspberrypi's cache and need emulated kernel builds.
  boardModules = {
    rpi4 = rpi.nixosModules.raspberry-pi-4.base;
    rpi5 = rpi.nixosModules.raspberry-pi-5.base;
  };
in
assert roleInputs.nixpkgs.lib.assertMsg (board == null || boardModules ? ${board})
  "mkHost ${hostName}: unknown board \"${toString board}\", expected one of ${toString (builtins.attrNames boardModules)}";
assert roleInputs.nixpkgs.lib.assertMsg (
  board == null || (system == "aarch64-linux" && role == "server")
) "mkHost ${hostName}: board ${toString board} needs system aarch64-linux and role server";
roleInputs.nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = {
    inherit hostName role;
    inputs = roleInputs;
  }
  // roleInputs.nixpkgs.lib.optionalAttrs (board != null) { nixos-raspberrypi = rpi; };
  modules = [
    {
      networking.hostName = hostName;
      # Read by `nixos-version --configuration-revision`; the server upgrade hooks compare it with `deploy`.
      system.configurationRevision = inputs.self.rev or "dirty";
      # mkDefault: the desktops' hardware-configuration.nix set the same value.
      nixpkgs.hostPlatform = roleInputs.nixpkgs.lib.mkDefault system;
      # useGlobalPkgs: ii-fixes reaches both NixOS and home-manager pkgs.
      nixpkgs.overlays = import ../overlays;
      nixpkgs.config.allowUnfree = true;
    }
    roleInputs.disko.nixosModules.disko
    roleInputs.sops-nix.nixosModules.sops
    roleInputs.home-manager.nixosModules.home-manager
    # Role before common so list-valued options merge the role's entries first.
    ../modules/nixos/${role}
    ../modules/nixos/common
    hostDir
  ]
  ++ roleInputs.nixpkgs.lib.optionals (board != null) [
    rpi.lib.inject-overlays
    rpi.nixosModules.nixpkgs-rpi
    rpi.nixosModules.trusted-nix-caches
    boardModules.${board}
  ]
  ++ [
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
            kraneUser = config.krane.user;
          };
          users.${config.krane.user.name}.imports =
            roleInputs.nixpkgs.lib.optional (role == "desktop")
              # HM level, not NixOS: soymou #19 dconf error.
              # Patched copy of the flake source, not homeManagerModules.default: illogical-flake pins Qt to
              # qt6ct, which detaches Qt apps from ii's kdeglobals theming
              # (patches/illogical-flake-kde-platformtheme.patch).
              # applyPatches comes from bare nixpkgs: deriving it from the module `pkgs` (which depends on
              # `config`) recurses infinitely.
              (
                let
                  patched = roleInputs.nixpkgs.legacyPackages.${system}.applyPatches {
                    name = "illogical-flake-kde-platformtheme";
                    src = roleInputs.illogical-flake;
                    patches = [ ../patches/illogical-flake-kde-platformtheme.patch ];
                  };
                  # Patches dots-hyprland (`inputs.dotfiles`), which home-modules/dotfiles.nix copies to ~/.config:
                  # - illogical-flake-cheatsheet-fkeys.patch: the number-key regex mangles F1/F10/F11 labels and drops F9.
                  # - patches/ii/<dir>/*.patch: fork changes, applied in lexical order.
                  # `lib` is bare nixpkgs lib, same reason as applyPatches.
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
                    # Read by the settings window's About page (patches/ii/05-settings).
                    postPatch = ''
                      printf '{"rev":"%s","patches":%d}\n' \
                        ${roleInputs.dots-hyprland.rev} ${toString (builtins.length iiSeries)} \
                        > dots/.config/quickshell/ii/krane-build.json
                    '';
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
