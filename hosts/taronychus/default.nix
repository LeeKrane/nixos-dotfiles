# taronychus: Raspberry Pi 5 (8 GB), boots from a 1 TB NVMe (Lexar NM710). Service node: the
# base server role plus its wg0 spoke (192.168.82.2).
#
# Image: nix build .#image-taronychus, then write it straight to the NVMe (USB-NVMe adapter on a
# desktop): `zstd -dc ... | dd of=/dev/sdX`. The sd-image module mounts / by label (NIXOS_SD),
# so the same image boots from NVMe, and its root partition grows to fill the disk on first
# boot. BOOT_ORDER is read right to left: 0xf461 (SD, NVMe, USB) and 0xf416 both reach the NVMe
# without an SD card. The sops age key derives from this host's pre-generated SSH host key
# (stored encrypted in the password manager, recipient &host_taronychus in .sops.yaml):
# before first boot, copy ssh_host_ed25519_key (root:root 0600) and .pub (0644) from there into
# /etc/ssh on the flashed root partition. Secrets: wireguard/wg0-private-key; without that
# section wg0 stays unconfigured.
# krane's password is not in the repo or sops. After first boot, ssh in as krane (key auth) and
# run `passwd`: the empty initial password needs no current one (pam_unix nullok). Until then
# sudo is unusable, so deploys fail.
# Later deploys: nixos-rebuild switch --flake .#taronychus --target-host krane@taronychus
{ config, inputs, ... }:
{
  imports = [ inputs.nixos-raspberrypi.nixosModules.sd-image ];

  system.stateVersion = "26.05";

  # One host per hour: the Pis first, the WireGuard hub last.
  krane.autoUpgrade.rebootWindow = {
    lower = "03:59";
    upper = "05:00";
  };

  # Empty initial password (a never-booted image has no /etc to set one); applied at user
  # creation only (mutableUsers = true).
  users.users.${config.krane.user.name}.initialHashedPassword = "";
}
