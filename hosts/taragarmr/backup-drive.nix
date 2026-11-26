# External USB drive for the restic repository (backup.nix). nofail + automount: with the drive
# unplugged the host still boots and the backup job fails instead.
{ ... }:
let
  label = "backup2tb";
in
{
  fileSystems."/mnt/backup" = {
    device = "/dev/disk/by-label/${label}";
    fsType = "ext4";
    options = [
      "nofail"
      "x-systemd.automount"
      "x-systemd.device-timeout=5"
      "noatime"
    ];
  };
}
