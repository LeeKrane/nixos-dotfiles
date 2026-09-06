# Firmware and microcode nixos-generate-config doesn't enable by default.
{ lib, ... }:
{
  # Non-free blobs: iwlwifi Wi-Fi/Bluetooth firmware and CPU microcode.
  # Off by default, breaking Wi-Fi on tarmantria.
  hardware.enableRedistributableFirmware = true;

  # mkDefault: tariognatha/tarmantria are Intel. taractias sets a plain
  # `false` in its own default.nix and gets AMD microcode from common-cpu-amd.
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
}
