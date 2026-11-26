# Activates graphical-session.target for the non-UWSM Hyprland session: nothing in the greetd
# autologin path starts it, and xdg-desktop-portal has Requisite=graphical-session.target, so
# portal calls fail with "Dependency failed". The target refuses manual start, so a bound target
# is started instead, after the env import (portal-hyprland needs WAYLAND_DISPLAY in the systemd
# environment).
{ ... }:
{
  systemd.user.targets.hyprland-session.Unit = {
    Description = "Hyprland compositor session";
    BindsTo = [ "graphical-session.target" ];
    Wants = [ "graphical-session-pre.target" ];
    After = [ "graphical-session-pre.target" ];
  };

  krane.hypr.execOnce = [
    "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE && systemctl --user start hyprland-session.target"
  ];
}
