# taronychus: Raspberry Pi 5 (8 GB), boots from a 1 TB NVMe (Lexar NM710). Service node: the
# base server role plus its wg0 spoke (192.168.82.2), nothing else yet.
#
# First install (no image of this host exists, the NVMe is formatted by disko):
#   1. Build and flash the nixos-raspberrypi installer to an SD card:
#        nix build .#image-installer-rpi5   (nixos-raspberrypi's installer, cached)
#      then `zstd -d` the result and dd it to the card. Boot it, note its IP, and put your SSH
#      key in (the installer shows a root password on its console).
#   2. From a desktop (aarch64 closure from nixos-raspberrypi's cache):
#        nix run github:nix-community/nixos-anywhere -- --flake .#taronychus \
#          --phases kexec,disko,install \
#          --extra-files ~/server-migration/host-keys/taronychus \
#          --target-host root@<installer-ip>
#      disko partitions the NVMe per ./disko.nix. The sops age key derives from the
#      pre-generated SSH host key in --extra-files (recipient &host_taronychus in .sops.yaml).
#      Do not run scripts/bootstrap-sops.sh. Before rebooting, set krane's password:
#        ssh -t root@<installer-ip> "nixos-enter --root /mnt -c 'passwd krane'"
#      Without it sudo is unusable and deploys fail.
#   3. Check the EEPROM boot order prefers NVMe: `rpi-eeprom-config | grep BOOT_ORDER`
#      (0xf416 = SD, then NVMe, then USB; remove the SD card after installing).
# Later deploys: nixos-rebuild switch --flake .#taronychus --target-host krane@taronychus
#
# Secrets (secrets/taronychus.yaml): wireguard/wg0-private-key; without that section wg0 stays
# unconfigured.
{ ... }:
{
  imports = [ ./disko.nix ];

  system.stateVersion = "26.05";

  # Pi 5: the generational "kernel" bootloader (U-Boot cannot boot from NVMe/USB on a Pi 5).
  # Firmware, kernels and initrds sit on /boot/firmware (disko.nix). No other bootloader is
  # enabled: servers import no systemd-boot or grub config, checks.pi-eval asserts it.
  boot.loader.raspberry-pi.bootloader = "kernel";

  # Firewall: ssh only (server module). wg0 is outbound to the hub.
}
