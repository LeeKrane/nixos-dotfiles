{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./caddy.nix
    ./ntfy.nix
    ./couchdb.nix
    ./spt.nix
    ./services.nix
    ./backup.nix
    ./backup-drive.nix
  ];

  system.stateVersion = "26.05";

  # One host per hour: the Pis first, the WireGuard hub last.
  krane.autoUpgrade.rebootWindow = {
    lower = "04:59";
    upper = "06:00";
  };

  boot.loader.systemd-boot = {
    enable = true;
    # The ESP holds every generation's kernel and initrd.
    configurationLimit = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;
}
