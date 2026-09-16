# tariognatha, the desktop: single NVIDIA GPU, RTX 4070 Ti class, no
# PRIME offload. Imported only by hosts/tariognatha/default.nix.
{ config, pkgs, ... }:
{
  services.xserver.videoDrivers = [ "nvidia" ];

  # CUDA packages are unfree, not on cache.nixos.org, and slow to compile from
  # source. Pinned here (not in nix-settings.nix) so only the CUDA host trusts it.
  # cache.nixos-cuda.org is the NixOS CUDA team's cache, key confirmed
  # independently. Do not re-add the cachix-hosted CUDA cache: it
  # returns 401 on every request.
  nix.settings = {
    substituters = [ "https://cache.nixos-cuda.org" ];
    trusted-public-keys = [
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  hardware.nvidia = {
    # Open-source kernel module: required for this Turing/Ada-class card.
    open = true;
    modesetting.enable = true;
    nvidiaSettings = true;
    powerManagement.enable = true;
    # finegrained only helps a PRIME laptop. Explicit false for this single-GPU desktop.
    powerManagement.finegrained = false;
    # Follows boot.nix's kernelPackages mkDefault, not hardcoded here.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # nouveau must never load alongside the proprietary/open nvidia module.
  boot.blacklistedKernelModules = [ "nouveau" ];
  boot.kernelParams = [ "nvidia_drm.fbdev=1" ];

  # NIXOS_OZONE_WL is set once in desktop.nix, not here.
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    NVD_BACKEND = "direct";
  };

  # services.ollama.acceleration is deprecated. package selection replaces it.
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
  };
}
