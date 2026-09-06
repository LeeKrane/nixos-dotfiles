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
  services.smartd.enable = true;
  hardware.i2c.enable = true;

  programs.ydotool.enable = true;
  # Escape hatch if programs.ydotool.enable is ever removed upstream: uncomment the udev rule below.
  # services.udev.extraRules = ''
  #   KERNEL=="uinput", GROUP="uinput", MODE="0660", OPTIONS+="static_node=uinput"
  # '';
  # users.groups.uinput = { };
  # users.users.krane.extraGroups = [ "uinput" ];

  services.udisks2.enable = true;

  # brightnessctl's udev rules live only here, for normal-user backlight access.
  services.udev.packages = [ pkgs.brightnessctl ];

  environment.systemPackages = [ pkgs.lm_sensors ];
}
