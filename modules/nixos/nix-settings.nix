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

      # CUDA packages are unfree, not on cache.nixos.org, and slow to
      # compile from source. All three caches are pinned so nix.conf defaults can't drop them.
      substituters = [
        "https://cache.nixos.org/"
        "https://cuda-maintainers.cachix.org"
        "https://cache.nixos-cuda.org"
      ];
      # cache.nixos-cuda.org is the NixOS CUDA team's successor to cuda-maintainers, key
      # confirmed independently. Both kept so one being down does not force a from-source
      # rebuild.
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
        "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
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
