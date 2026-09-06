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
          inputs.illogical-flake.homeManagerModules.default
          inputs.nix-index-database.homeModules.nix-index
          ../modules/home
        ];
      };
    }
  ]
  ++ extraModules;
}
