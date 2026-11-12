# disko layout for taragarmr's 512 GB NVMe: GPT, 1 GiB ESP, btrfs for the rest.
# Subvolumes: @ /, @home /home (SPT data, restored backups), @nix /nix, @srv /srv (CouchDB).
# No swap partition: 27 GiB of RAM plus zram (modules/nixos/server/zram.nix), and a server
# does not hibernate. A disk swap would only slow an OOM down; the SPT units carry MemoryMax.
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
