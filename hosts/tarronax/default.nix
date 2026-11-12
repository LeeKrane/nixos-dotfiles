# tarronax: Raspberry Pi 4 (4 GB), 128 GB SD card. Spare node: the base server role plus its
# wg0 spoke (192.168.82.4), nothing else.
#
# Image: nix build .#image-tarronax, then `zstd -d` and dd it to the SD card (or the Pi
# imager's "use custom"). The image is built from this config, so the first boot already has
# the account and ssh keys. The sops age key derives from the SSH host key generated at first
# boot: add it with scripts/bootstrap-sops.sh to enable secrets/tarronax.yaml
# (wireguard/wg0-private-key); without that section wg0 stays unconfigured.
# Later deploys: nixos-rebuild switch --flake .#tarronax --target-host krane@tarronax
{ inputs, ... }:
{
  imports = [ inputs.nixos-raspberrypi.nixosModules.sd-image ];

  system.stateVersion = "26.05";

  # Pi 4: U-Boot (the base module's default), generational extlinux on the SD card. The sd-image
  # module defines the filesystems; no other bootloader is enabled for Pis.

  # Firewall: ssh only (server module). wg0 is outbound to the hub.
}
