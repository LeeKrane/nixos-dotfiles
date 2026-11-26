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
    # hardware.nvidia is gated on "nvidia" being in this list; without it offload and finegrained
    # PM below are inert.
    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.nvidia.open = true;
    hardware.nvidia.powerManagement.enable = true;

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

    hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.latest;

    # glxinfo, used by the install.sh VERIFY check `nvidia-offload glxinfo`.
    environment.systemPackages = [ pkgs.mesa-demos ];

    environment.sessionVariables = {
      LIBVA_DRIVER_NAME = "iHD";
    };
  };
}
