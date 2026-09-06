# Lenovo IdeaPad 330S, AMD variant: Ryzen 2xxxU APU (Vega iGPU, no dGPU), in-kernel RTL8821CE
# Wi-Fi (rtw88), ELAN I2C touchpad. nixos-hardware applies here, not to tariognatha/tarmantria,
# since those are Intel and these AMD profiles would be no-ops there at best.
{ inputs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix

    # Sets hardware.cpu.amd.updateMicrocode = mkDefault enableRedistributableFirmware, already true.
    inputs.nixos-hardware.nixosModules.common-cpu-amd

    # Sets videoDrivers/hardware.graphics/amdgpu.initrd as mkDefault, matched below, no conflict.
    inputs.nixos-hardware.nixosModules.common-gpu-amd

    # Sets services.tlp.enable = mkDefault (!power-profiles-daemon.enable), so tlp stays disabled.
    inputs.nixos-hardware.nixosModules.common-pc-laptop

    # Same as common-pc-ssd (fstrim only), redundant with boot.nix's services.fstrim.enable = true.
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
  ];

  system.stateVersion = "26.05";

  # display.nix is a home-manager module (sets krane.hypr.*), so it is imported at the user level.
  home-manager.users.krane.imports = [ ./display.nix ];

  # Explicit rather than left to common-gpu-amd's mkDefault, so this reads correctly standalone.
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Vega iGPU (amdgpu): VA-API decode goes through Mesa's radeonsi, not the NVIDIA hosts' shim.
  environment.sessionVariables.LIBVA_DRIVER_NAME = "radeonsi";

  # modules/nixos/hardware.nix sets hardware.cpu.intel.updateMicrocode = mkDefault true (both
  # other hosts are Intel). This host is AMD, so plain `false` overrides it. AMD microcode uses
  # common-cpu-amd's mkDefault above.
  hardware.cpu.intel.updateMicrocode = false;

  # VERIFY ON TARGET: RTL8821CE (rtw88_8821ce) can hit power-saving firmware bugs (dropped
  # associations). If that happens, uncomment this ASPM-disable fallback instead of an
  # out-of-tree driver:
  # boot.extraModprobeConfig = "options rtw88_8821ce disable_aspm=1";

  # VERIFY ON TARGET: the ELAN I2C touchpad should work via the in-kernel i2c-hid + libinput
  # stack with no extra config. Check `libinput list-devices` before adding overrides in display.nix.

  # VERIFY ON TARGET: no explicit backlight config here. modules/nixos/peripherals.nix already
  # covers brightnessctl udev rules for all hosts. Confirm brightness keys work before adding more.
}
