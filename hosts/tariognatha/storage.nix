# Secondary 4 TB HDD, left over from Windows dual-boot: an NTFS data partition ("Kranische Daten")
# and a btrfs partition. Both mount at boot, so udisks/Dolphin see them as mounted and
# never ask for a password. nofail keeps boot from waiting on the disk.
{ ... }:
let
  hddOptions = [
    "x-systemd.device-timeout=30s"
    "nofail"
    "noatime"
  ];
in
{
  fileSystems."/mnt/hdd-ntfs" = {
    device = "/dev/disk/by-uuid/C262609862609349";
    fsType = "ntfs3";
    noCheck = true;
    # NTFS has no POSIX owners: map everything to krane.
    options = hddOptions ++ [
      "uid=1000"
      "gid=100"
      "umask=022"
    ];
  };

  # Top-level subvolume, so any subvolumes on it show up as directories.
  fileSystems."/mnt/hdd-btrfs" = {
    device = "/dev/disk/by-uuid/499c0ea0-0fbd-4e1d-b12e-d08f51cce283";
    fsType = "btrfs";
    options = hddOptions ++ [ "compress=zstd:1" ];
  };
}
