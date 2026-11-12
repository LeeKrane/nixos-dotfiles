# Written by hand for the AZW SER (Ryzen 7 6800H, Radeon 680M, RTL8125 NIC, AX200 Wi-Fi).
# Regenerate on install day with the real hardware:
#   nixos-anywhere --generate-hardware-config nixos-generate-config ./hosts/taragarmr/hardware-configuration.nix ...
# and drop any fileSystems/swapDevices it emits: disko.nix owns those.
{
  config,
  lib,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ "amdgpu" ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.enableRedistributableFirmware = lib.mkDefault true;
}
