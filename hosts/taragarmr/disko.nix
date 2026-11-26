# No swap partition: RAM plus zram (modules/nixos/server/zram.nix); the SPT units carry MemoryMax.
{ ... }:
let
  opts = [
    "compress=zstd:1"
    "noatime"
  ];
in
{
  disko.devices.disk.main = {
    device = "/dev/disk/by-id/nvme-512GB_SSD_MQ25B04103756";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          priority = 1;
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];
            subvolumes = {
              "@" = {
                mountpoint = "/";
                mountOptions = opts;
              };
              "@home" = {
                mountpoint = "/home";
                mountOptions = opts;
              };
              "@nix" = {
                mountpoint = "/nix";
                mountOptions = opts;
              };
              "@srv" = {
                mountpoint = "/srv";
                mountOptions = opts;
              };
            };
          };
        };
      };
    };
  };
}
