# Core `nix.conf` / nix daemon settings shared by every host.
{ config, inputs, ... }:
{
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      trusted-users = [ config.krane.user.name ];

      # cache.nixos.org plus nixos-raspberrypi's cache (Pi kernels, firmware and images, which
      # the desktops build Pis' images from and the Pis themselves pull). The CUDA cache is
      # scoped to the CUDA host in modules/nixos/gpu/nvidia-desktop.nix (nix.settings lists
      # merge across modules).
      substituters = [
        "https://cache.nixos.org/"
        "https://nixos-raspberrypi.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      ];
    };

    # Pins the `nixpkgs` registry entry to this flake's own input.
    registry.nixpkgs.flake = inputs.nixpkgs;

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };
}
