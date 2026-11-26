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
