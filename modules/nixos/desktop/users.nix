# Desktop-only groups for the login account (base groups: ../common/users.nix).
{ config, ... }:
{
  # `i2c` group already exists via hardware.i2c.enable. `plugdev` is
  # declared here since it's just a side effect of zsa.enable elsewhere.
  users.groups.plugdev = { };

  users.users.${config.krane.user.name}.extraGroups = [
    "networkmanager"
    "input"
    "i2c"
    "docker"
    "libvirtd"
    "plugdev"
    # Required by peripherals.nix's programs.ydotool.enable, for uinput access.
    "ydotool"
    # gamemode's polkit rule lets only this group run its governor and sysctl helpers;
    # without it gamemoded registers games but every privileged tweak is refused.
    "gamemode"
  ];
}
