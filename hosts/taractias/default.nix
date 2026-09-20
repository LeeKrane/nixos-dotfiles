# Lenovo IdeaPad 330S, AMD variant: Ryzen 2xxxU APU (Vega iGPU, no dGPU), Qualcomm Atheros
# QCA9377 Wi-Fi (ath10k_pci), ELAN I2C touchpad. nixos-hardware applies here, not to
# tariognatha/tarmantria, since those are Intel and these AMD profiles would be no-ops there at best.
{
  inputs,
  pkgs,
  ...
}:
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

  # Boot straight into krane's Hyprland session; the session locks itself at start
  # (krane.hypr.execOnce in display.nix), so the ii lock screen is the first screen.
  # tuigreet stays as default_session for logout. The disk is not encrypted, so this
  # trades the greeter's password gate for the lock screen's. See docs/INSTALL.md.
  services.greetd.settings.initial_session = {
    command = "${pkgs.uwsm}/bin/uwsm start -e -D Hyprland hyprland.desktop";
    user = "krane";
  };

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

  # QCA9377 Wi-Fi on ath10k_pci floods AMD-Vi IO_PAGE_FAULT events and stalls under the
  # default IOMMU mode.
  boot.kernelParams = [ "iommu=pt" ];

  # VERIFY ON TARGET: dmesg | grep ath10k shows firmware loaded and no AMD-Vi IO_PAGE_FAULT storm.

  # VERIFY ON TARGET: the ELAN I2C touchpad should work via the in-kernel i2c-hid + libinput
  # stack with no extra config. Check `libinput list-devices` before adding overrides in display.nix.

  # VERIFY ON TARGET: no explicit backlight config here. modules/nixos/peripherals.nix already
  # covers brightnessctl udev rules for all hosts. Confirm brightness keys work before adding more.
}
