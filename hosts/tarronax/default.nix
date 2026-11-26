# tarronax: Raspberry Pi 4 (4 GB), 128 GB SD card. Spare node: the base server role plus its
# wg0 spoke (192.168.82.4).
#
# Image: nix build .#image-tarronax, then `zstd -d` and dd it to the SD card (or the Pi
# imager's "use custom"). The image is built from this config, so the first boot already has
# the account and ssh keys. The sops age key derives from this host's pre-generated SSH host key
# (stored encrypted in the password manager, recipient &host_tarronax in .sops.yaml):
# before first boot, copy ssh_host_ed25519_key (root:root 0600) and .pub (0644) from there
# into /etc/ssh on the flashed card's root partition. Secrets: wireguard/wg0-private-key;
# without that section wg0 stays unconfigured.
# krane's password is not in the repo or sops. On site, first boot with a monitor (Pi 4: micro-HDMI) and
# keyboard: log in as krane at the console without a password, then run `passwd`. Until then
# the account has an empty password (console login only, physical access; sudo, su and SSH
# password login are refused, SSH is key-only) and sudo is unusable, so deploys fail.
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
