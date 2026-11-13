# tarronax: Raspberry Pi 4 (4 GB), 128 GB SD card. Spare node: the base server role plus its
# wg0 spoke (192.168.82.4), nothing else.
#
# Image: nix build .#image-tarronax, then `zstd -d` and dd it to the SD card (or the Pi
# imager's "use custom"). The image is built from this config, so the first boot already has
# the account and ssh keys. The sops age key derives from this host's pre-generated SSH host key
# (~/server-migration/host-keys/tarronax/etc/ssh/, recipient &host_tarronax in .sops.yaml):
# before first boot, copy ssh_host_ed25519_key (root:root 0600) and .pub (0644) from there
# into /etc/ssh on the flashed card's root partition; sshd keeps an existing key. Do not run
# scripts/bootstrap-sops.sh. Secrets: wireguard/wg0-private-key;
# without that section wg0 stays unconfigured.
# krane's password is not in the repo or sops. On site, first boot with a monitor (Pi 4: micro-HDMI) and
# keyboard: log in as krane at the console without a password, then run `passwd`. Until then
# the account has an empty password (console login only, physical access; sudo, su and SSH
# password login are refused, SSH is key-only) and sudo is unusable, so deploys fail.
# Later deploys: nixos-rebuild switch --flake .#tarronax --target-host krane@tarronax
{ config, inputs, ... }:
{
  imports = [ inputs.nixos-raspberrypi.nixosModules.sd-image ];

  system.stateVersion = "26.05";

  # Never-booted SD image has no /etc yet, so the password cannot be set before first boot.
  # Empty initial password: console login works (login service allowNullPassword, nixpkgs
  # nixos/modules/programs/shadow.nix) and `passwd` needs no current password (pam_unix
  # nullok on the password stack); applied at user creation only (mutableUsers = true).
  users.users.${config.krane.user.name}.initialHashedPassword = "";

  # Pi 4: U-Boot (the base module's default), generational extlinux on the SD card. The sd-image
  # module defines the filesystems; no other bootloader is enabled for Pis.

  # Firewall: ssh only (server module). wg0 is outbound to the hub.
}
