{ config, pkgs, ... }:
{
  services.xserver.videoDrivers = [ "nvidia" ];

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
    open = true;
    modesetting.enable = true;
    nvidiaSettings = true;
    powerManagement.enable = true;
    powerManagement.finegrained = false;
    # latest, not stable: stable 595 offers NVENC API 13.0, gpu-screen-recorder needs 13.1.
    package = config.boot.kernelPackages.nvidiaPackages.latest;
  };

  boot.blacklistedKernelModules = [ "nouveau" ];
  boot.kernelParams = [ "nvidia_drm.fbdev=1" ];

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    NVD_BACKEND = "direct";
  };

  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
  };
}
