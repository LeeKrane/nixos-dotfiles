# Fixture host for checks.server-eval in flake.nix: the least hardware a role = "server"
# config needs to evaluate, plus every optional server feature switched on with dummy
# /run/secrets paths (only evaluated, never built or run). Not under hosts/, so it is no
# nixosConfiguration. The check evaluates it under three host names: one outside lib/wireguard.nix,
# the hub (taragarmr) and a spoke (tarronax).
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

  # No secrets/<host>.yaml exists for the fixture names, so hand the interfaces their keys.
  krane.wireguard = {
    wg0PrivateKeyFile = "/run/secrets/wireguard/wg0-private-key";
    wg1PrivateKeyFile = "/run/secrets/wireguard/wg1-private-key";
  };
}
