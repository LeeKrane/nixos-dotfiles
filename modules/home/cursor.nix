# Cursor theme for every host. ii hardcodes `hyprctl setcursor Bibata-Modern-Classic 24` in
# hyprland/execs.lua but installs no cursor package, so Hyprland silently fell back to the stock
# X cursor. This installs the theme and re-applies it after ii's own exec (custom/execs.lua runs
# later), and exports XCURSOR_* through Hyprland so GTK/Qt/Electron clients agree.
# home.pointerCursor handles GTK settings.ini/dconf and ~/.icons/default; Hyprland is started by
# greetd without hm-session-vars, so the env goes through krane.hypr.env too.
# hyprcursor.enable stays off: Bibata ships no hyprcursor manifest, and Hyprland falls back to
# XCursor on its own.
{ pkgs, ... }:
let
  name = "Bibata-Modern-Classic";
  size = 24;
in
{
  home.pointerCursor = {
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
