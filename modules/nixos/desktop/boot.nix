{
  lib,
  pkgs,
  ...
}:
{
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 3;
    editor = false;
    edk2-uefi-shell.enable = false;
  };

  boot.loader.efi.canTouchEfiVariables = true;

  boot.plymouth = {
    enable = true;
    theme = "lone";
    themePackages = [ pkgs.plymouth-lone ];
  };

  boot.kernelParams = [
    "quiet"
    "splash"
    "boot.shell_on_fail"
    "udev.log_level=3"
    "rd.systemd.show_status=auto"
  ];
  boot.consoleLogLevel = 0;

  # mkDefault: NVIDIA modules may pin a kernel series.
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
  boot.supportedFilesystems = [
    "btrfs"
    "ntfs"
  ];

  services.fstrim.enable = true;

  zramSwap = {
    enable = true;
    memoryPercent = lib.mkDefault 100;
    algorithm = lib.mkDefault "zstd";
  };

  # Swap-on-zram tuning (Arch wiki zram page): compressed RAM beats re-reading evicted file
  # cache, so prefer swap (swappiness > 100). page-cluster 0 disables readahead: zram has no
  # seek cost.
  boot.kernel.sysctl = {
    "vm.swappiness" = 180;
    "vm.page-cluster" = 0;
    "vm.watermark_boost_factor" = 0;
    "vm.watermark_scale_factor" = 125;
  };
}
