# disko layout for taronychus' 1 TB NVMe (Lexar NM710): GPT, a 1 GiB FAT firmware partition at
# /boot/firmware (the Pi firmware, kernels and initrds of every generation live there, hence
# 1 GiB, as in nixos-raspberrypi's own sd-image) and ext4 for the rest.
{ ... }:
{
  disko.devices.disk.main = {
    # TODO: use the stable name once known: ls -l /dev/disk/by-id/ | grep nvme on the Pi
    # (nvme-Lexar_SSD_NM710_1TB_<serial>). The inventory only has the kernel name.
    device = "/dev/nvme0n1";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        firmware = {
          size = "1024M";
          type = "0700";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot/firmware";
            mountOptions = [
              "noatime"
              "umask=0077"
            ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = [ "noatime" ];
          };
        };
      };
    };
  };
}
