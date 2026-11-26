# ii runs `hyprctl setcursor Bibata-Modern-Classic 24` (hyprland/execs.lua) but installs no cursor
# package. This installs the theme, re-applies it after ii's exec, and exports XCURSOR_* through
# krane.hypr.env because greetd starts Hyprland without hm-session-vars.
# hyprcursor stays off: Bibata ships no hyprcursor manifest.
{ pkgs, ... }:
let
  name = "Bibata-Modern-Classic";
  size = 24;
in
{
  home.pointerCursor = {
    enable = true;
    package = pkgs.bibata-cursors;
    inherit name size;
    gtk.enable = true;
  };

  krane.hypr = {
    env = {
      XCURSOR_THEME = name;
      XCURSOR_SIZE = toString size;
    };
    execOnce = [ "hyprctl setcursor ${name} ${toString size}" ];
  };
}
