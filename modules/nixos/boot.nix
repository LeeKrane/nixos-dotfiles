# Bootloader, initrd, kernel and swap. Plymouth uses the custom "lone"
# theme from pkgs/plymouth-lone.
{
  lib,
  pkgs,
  ...
}:
{
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 10;
    editor = false;
    edk2-uefi-shell.enable = false;

    # Windows dual-boot template, disabled. Uncomment and fill in real
    # values if Windows gets its own separate ESP:
    #
    # extraEntries = {
    #   "windows.conf" = ''
    #     title Windows
    #     efi /EFI/Microsoft/Boot/bootmgfw.efi
    #   '';
    # };
  };

  boot.loader.efi.canTouchEfiVariables = true;

  boot.plymouth = {
    enable = true;
    theme = "lone";
    themePackages = [ pkgs.plymouth-lone ];
  };

  boot.initrd.systemd.enable = true;

  boot.kernelParams = [
    "quiet"
    "splash"
    "boot.shell_on_fail"
    "udev.log_level=3"
    "rd.systemd.show_status=auto"
  ];
  boot.consoleLogLevel = 0;

  # mkDefault: NVIDIA GPU modules may need to pin a specific kernel series.
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
  boot.supportedFilesystems = [
    "btrfs"
    "ntfs"
  ];

  # Weekly TRIM for the btrfs-on-SSD/NVMe layout disko.nix sets up.
  services.fstrim.enable = true;

  zramSwap = {
    enable = true;
    memoryPercent = 25;
    algorithm = "zstd";
  };
}
