# Fixture for checks.server-eval: minimal server config, optional features on with dummy secret paths.
{ ... }:
{
  system.stateVersion = "26.05";
  boot.loader.grub.enable = false;
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  krane.autoUpgrade.rebootWindow = {
    lower = "01:59";
    upper = "03:00";
  };

  krane.backup = {
    enable = true;
    repository = "/mnt/backup/restic/fixture";
    passwordFile = "/run/secrets/restic/password";
    paths = [ "/var/lib" ];
    exclude = [ "/var/lib/docker" ];
    backupPrepareCommand = "true";
  };

  # No secrets/<host>.yaml exists for the fixture names.
  krane.wireguard = {
    wg0PrivateKeyFile = "/run/secrets/wireguard/wg0-private-key";
    wg1PrivateKeyFile = "/run/secrets/wireguard/wg1-private-key";
  };
}
