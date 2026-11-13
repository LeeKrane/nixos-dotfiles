# tarritator: Raspberry Pi 5, 128 GB SD card, located OFFSITE as the secondary backup. A 2 TB
# USB HDD holds a copy of the backups; tarritator PULLS it from taronychus over wg0, so a
# compromised primary cannot delete the offsite copy.
#
# Image: nix build .#image-tarritator, then `zstd -d` and dd it to the SD card. Set it up at
# home first with the HDD attached, then move it. The sops age key derives from this host's
# pre-generated SSH host key (~/server-migration/host-keys/tarritator/etc/ssh/, recipient
# &host_tarritator in .sops.yaml): before first boot, copy ssh_host_ed25519_key (root:root
# 0600) and .pub (0644) from there into /etc/ssh on the flashed card's root partition, so
# sshd keeps it instead of generating one. Do not run scripts/bootstrap-sops.sh. Later deploys:
#   nixos-rebuild switch --flake .#tarritator --target-host krane@192.168.82.3
#
# Secrets (secrets/tarritator.yaml): wireguard/wg0-private-key,
# restic/{rest-env,repo-password-taragarmr,repo-password-taronychus,offsite-repo-password}.
{ inputs, ... }:
{
  imports = [
    inputs.nixos-raspberrypi.nixosModules.sd-image
    ./offsite-copy.nix
  ];

  system.stateVersion = "26.05";

  # Pi 5: the sd-image module selects the generational "kernel" bootloader. No other
  # bootloader is enabled for Pis.

  # Firewall: ssh only (server module). The copy job and wg0 are outbound.
}
