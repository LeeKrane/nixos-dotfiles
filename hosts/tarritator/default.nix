# tarritator: Raspberry Pi 5, 128 GB SD card, located OFFSITE as the secondary backup. A 2 TB
# USB HDD holds a copy of the backups; tarritator PULLS it from taronychus over wg0, so a
# compromised primary cannot delete the offsite copy.
#
# Image: nix build .#image-tarritator, then `zstd -d` and dd it to the SD card. Set it up at
# home first with the HDD attached, then move it. The sops age key derives from the SSH host
# key generated at first boot: add it with scripts/bootstrap-sops.sh to enable
# secrets/tarritator.yaml. Later deploys:
#   nixos-rebuild switch --flake .#tarritator --target-host krane@192.168.82.3
#
# Secrets (secrets/tarritator.yaml): wireguard/wg0-private-key, users/krane-password-hash,
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
