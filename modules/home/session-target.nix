# Activates graphical-session.target for the plain (non-UWSM) Hyprland session. greetd
# autologins into start-hyprland (modules/nixos/desktop.nix), and nothing in that path starts
# the target. xdg-desktop-portal has Requisite=graphical-session.target, so without it every
# portal call fails with "Dependency failed" and screen sharing, file pickers etc. never open.
# graphical-session.target refuses manual start, so a bound target is started instead. The env
# import runs first because portal-hyprland needs WAYLAND_DISPLAY in the systemd environment.
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
