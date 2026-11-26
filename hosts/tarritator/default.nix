# tarritator: Raspberry Pi 5, 128 GB SD card. Service node: the base server role plus its wg0
# spoke (192.168.82.3).
#
# Image: nix build .#image-tarritator, then `zstd -d` and dd it to the SD card. The sops age
# key derives from this host's pre-generated SSH host key
# (stored encrypted in the password manager, recipient &host_tarritator in .sops.yaml):
# before first boot, copy ssh_host_ed25519_key (root:root 0600) and .pub (0644) from there into
# /etc/ssh on the flashed card's root partition. Secrets: wireguard/wg0-private-key; without
# that section wg0 stays unconfigured.
# krane's password is not in the repo or sops. First boot with a monitor (Pi 5: micro-HDMI) and
# keyboard: log in as krane at the console without a password, then run `passwd`. Until then
# the account has an empty password (console login only, physical access; sudo, su and SSH
# password login are refused, SSH is key-only) and sudo is unusable, so deploys fail.
# Later deploys: nixos-rebuild switch --flake .#tarritator --target-host krane@tarritator
{ config, inputs, ... }:
{
  imports = [ inputs.nixos-raspberrypi.nixosModules.sd-image ];

  system.stateVersion = "26.05";

  # One host per hour: the Pis first, the WireGuard hub last.
  krane.autoUpgrade.rebootWindow = {
    lower = "02:59";
    upper = "04:00";
  };

  # Empty initial password: console login works (login service allowNullPassword) and `passwd`
  # needs no current password (pam_unix nullok); applied at user creation only
  # (mutableUsers = true).
  users.users.${config.krane.user.name}.initialHashedPassword = "";
}
