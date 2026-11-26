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
