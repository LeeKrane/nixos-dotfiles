# PLACEHOLDER hardware config for tarmantria. REPLACE at install time with the output of
# `nixos-generate-config --no-filesystems --root /mnt` (docs/INSTALL.md). Exists only so
# `nix flake check`/`nixosSystem` evaluates before the real disk layout is known. fileSystems
# and the bootloader are not defined here: disko.nix and modules/nixos/boot.nix do.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usb_storage"
    "sd_mod"
  ];
}
