# Core `nix.conf` / nix daemon settings shared by every host.
{ inputs, ... }:
{
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      trusted-users = [ "krane" ];

      # cache.nixos.org only; the CUDA cache is scoped to the CUDA host in
      # modules/nixos/gpu/nvidia-desktop.nix (nix.settings lists merge across modules).
      substituters = [
        "https://cache.nixos.org/"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
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
