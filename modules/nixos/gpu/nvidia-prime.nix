# tarmantria, the laptop: Intel iGPU and NVIDIA dGPU, PRIME offload.
# Imported only by hosts/tarmantria/default.nix.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.krane.prime = {
    intelBusId = lib.mkOption {
      type = lib.types.str;
      description = "PCI bus ID of the Intel iGPU, as reported by `lspci`. FILL AT INSTALL.";
    };
    nvidiaBusId = lib.mkOption {
      type = lib.types.str;
      description = "PCI bus ID of the NVIDIA dGPU, as reported by `lspci`. FILL AT INSTALL.";
    };
  };

  config = {
    # hardware.nvidia is entirely gated on "nvidia" being in this list.
    # Without it, offload and finegrained PM below are silently inert.
    services.xserver.videoDrivers = [ "nvidia" ];

    # No default on this nixpkgs rev, must be set explicitly.
    hardware.nvidia.open = true;
    hardware.nvidia.powerManagement.enable = true;

    # nouveau must never load alongside the nvidia kernel module.
    boot.blacklistedKernelModules = [ "nouveau" ];

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
      # No `hardware.intel-media-driver` option on this rev. iHD is just a package.
      extraPackages = [ pkgs.intel-media-driver ];
    };

    hardware.nvidia = {
      modesetting.enable = true;
      powerManagement.finegrained = true;
      prime = {
        offload = {
          enable = true;
          enableOffloadCmd = true;
        };
        intelBusId = config.krane.prime.intelBusId;
        nvidiaBusId = config.krane.prime.nvidiaBusId;
      };
    };

    hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;

    environment.sessionVariables = {
      LIBVA_DRIVER_NAME = "iHD";
    };

    # power-profiles-daemon: set once in desktop.nix, common to every host.
  };
}
