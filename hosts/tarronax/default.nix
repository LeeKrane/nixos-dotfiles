# tarronax: Raspberry Pi 4 spare node (base server role plus its wg0 spoke).
#
# Image: nix build .#image-tarronax, then `zstd -d` and dd it to the SD card. The sops age
# key derives from this host's pre-generated SSH host key (in the password manager; &host_tarronax in
# .sops.yaml): before first boot, copy ssh_host_ed25519_key (root:root 0600) and .pub (0644)
# into /etc/ssh on the card's root partition; sshd keeps an existing key.
# scripts/bootstrap-sops.sh is not run. Secrets: wireguard/wg0-private-key.
# krane's password is not in the repo or sops: first boot with a monitor and keyboard, log in
# as krane at the console without a password, then run `passwd`. Until then the account has
# an empty password (console only) and sudo is unusable, so deploys fail.
# Later deploys: nixos-rebuild switch --flake .#tarronax --target-host krane@tarronax
{
  config,
  inputs,
  pkgs,
  ...
}:
let
  wol = (import ../../lib/lan.nix).wol.tariognatha;
in
{
  imports = [ inputs.nixos-raspberrypi.nixosModules.sd-image ];

  system.stateVersion = "26.05";

  # One host per hour: the Pis first, the WireGuard hub last.
  krane.autoUpgrade.rebootWindow = {
    lower = "01:59";
    upper = "03:00";
  };

  # Empty initial password: console login works (login service allowNullPassword) and `passwd`
  # needs no current password (pam_unix nullok); applied at user creation only
  # (mutableUsers = true).
  users.users.${config.krane.user.name}.initialHashedPassword = "";

  # Wakes tariognatha from suspend: `ssh tarronax wake-tariognatha`.
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "wake-tariognatha";
      runtimeInputs = [ pkgs.wakeonlan ];
      text = "wakeonlan -i ${wol.broadcast} ${wol.mac}";
    })
  ];
}
