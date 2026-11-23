# Misc hardware/peripheral support: ZSA keyboard, RGB, camera, I2C, udisks2.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  hardware.keyboard.zsa.enable = true;

  # mkDefault: off here, overridden true on tariognatha only.
  services.hardware.openrgb = {
    enable = lib.mkDefault false;
    motherboard = "intel";
  };

  boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
  boot.kernelModules = [
    "v4l2loopback"
    "i2c-dev"
    "uinput"
  ];

  services.printing.enable = true;
  services.smartd = {
    enable = true;
    # Exit 0 instead of 17 when no disk exposes SMART, as on virtio disks in a VM,
    # so the unit does not fail every switch.
    extraOptions = [ "-q nodev0" ];
  };
  hardware.i2c.enable = true;

  programs.ydotool.enable = true;
  # Escape hatch if programs.ydotool.enable is ever removed upstream: uncomment the udev rule below.
  # services.udev.extraRules = ''
  #   KERNEL=="uinput", GROUP="uinput", MODE="0660", OPTIONS+="static_node=uinput"
  # '';
  # users.groups.uinput = { };
  # users.users.${config.krane.user.name}.extraGroups = [ "uinput" ];

  services.udisks2.enable = true;

  services.udev.packages = [
    # brightnessctl's udev rules live only here, for normal-user backlight access.
    pkgs.brightnessctl
    # MonsGeek keyboard (VID 342d, wired and 2.4G dongle): give the active session
    # access to its hidraw nodes so VIA (usevia.app) can open them over WebHID.
    # Own file numbered below 73: 73-seat-late.rules applies the uaccess tag, so
    # extraRules (99-local.rules) would set it too late.
    (pkgs.writeTextDir "lib/udev/rules.d/70-monsgeek.rules" ''
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="342d", TAG+="uaccess"
    '')
  ];

  environment.systemPackages = [ pkgs.lm_sensors ];
}
