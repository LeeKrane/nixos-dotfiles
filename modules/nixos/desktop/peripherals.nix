{
  config,
  pkgs,
  lib,
  ...
}:
{
  hardware.keyboard.zsa.enable = true;

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
    # Exit 0 instead of 17 when no disk exposes SMART (virtio disks in a VM).
    extraOptions = [ "-q nodev0" ];
  };
  hardware.i2c.enable = true;

  programs.ydotool.enable = true;

  services.udisks2.enable = true;

  services.udev.packages = [
    pkgs.brightnessctl
    # MonsGeek keyboard (VID 342d): uaccess on its hidraw nodes so VIA can open it over WebHID.
    # Numbered below 73: 73-seat-late.rules applies uaccess, so extraRules (99-local.rules) is too late.
    (pkgs.writeTextDir "lib/udev/rules.d/70-monsgeek.rules" ''
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="342d", TAG+="uaccess"
    '')
  ];

  environment.systemPackages = [ pkgs.lm_sensors ];
}
