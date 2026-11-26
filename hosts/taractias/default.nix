# Lenovo IdeaPad 330S, AMD variant
{
  config,
  inputs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix

    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-gpu-amd
    inputs.nixos-hardware.nixosModules.common-pc-laptop
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
  ];

  system.stateVersion = "26.05";

  home-manager.users.${config.krane.user.name}.imports = [ ./display.nix ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  environment.sessionVariables.LIBVA_DRIVER_NAME = "radeonsi";

  # desktop/hardware.nix defaults Intel microcode on; this host is AMD.
  hardware.cpu.intel.updateMicrocode = false;

  zramSwap.memoryPercent = 200;

  boot.kernelParams = [ "iommu=pt" ];
}
