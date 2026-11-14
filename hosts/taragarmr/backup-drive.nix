# External USB backup drive (ext4, the 2 TB HDD), the restic repository's home (backup.nix).
# Mounted by label, on first access (automount), and never blocks boot: with the drive
# unplugged the host boots normally and the backup job fails instead (backup.nix refuses to
# stop CouchDB then).
{ ... }:
let
  # Filesystem label of the drive. Change this if the drive is relabelled (e2label).
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
