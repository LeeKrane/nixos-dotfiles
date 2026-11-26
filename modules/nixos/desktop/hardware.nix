{ lib, ... }:
{
  # Non-free blobs: iwlwifi Wi-Fi/Bluetooth firmware and CPU microcode.
  # Off by default, breaking Wi-Fi on tarmantria.
  hardware.enableRedistributableFirmware = true;

  # mkDefault: taractias is AMD and sets false.
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
}
