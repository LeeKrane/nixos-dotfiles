{ lib, ... }:
{
  hardware.enableRedistributableFirmware = true;

  # mkDefault: taractias is AMD and sets false.
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
}
