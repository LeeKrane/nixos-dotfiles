{ config, ... }:
{
  # `i2c` exists via hardware.i2c.enable. `plugdev` is a side effect of zsa.enable.
  users.groups.plugdev = { };

  users.users.${config.krane.user.name}.extraGroups = [
    "networkmanager"
    "input"
    "i2c"
    "docker"
    "libvirtd"
    "plugdev"
    # uinput access for programs.ydotool.
    "ydotool"
    # gamemode's polkit rule lets only this group run its helpers; without it privileged tweaks
    # are refused.
    "gamemode"
  ];
}
