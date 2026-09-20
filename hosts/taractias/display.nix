# home-manager module: laptop display / input layout for taractias, imported at the user level
# from hosts/taractias/default.nix, rendered to Lua by modules/home/hypr-config.nix.
# VERIFY ON TARGET: the IdeaPad 330S ships in more than one panel resolution. Some units are
# 1366x768, not the 1920x1080 `mode = "preferred"` would pick on a Full HD panel. Check
# `hyprctl monitors -j` after first login and adjust `scale` if text is illegible.
{ pkgs, ... }:
let
  # Boot autologins straight into Hyprland (hosts/taractias/default.nix); this locks the
  # session immediately so the ii lock screen, not a bare desktop, is the first thing shown.
  # ii's own execs.lua starts hypridle and quickshell in the same hyprland.start hook with no
  # ordering guarantee, so poll for both before locking.
  lockOnStart = pkgs.writeShellScript "krane-lock-on-start" ''
    for _ in $(${pkgs.coreutils}/bin/seq 1 50); do
      ${pkgs.procps}/bin/pidof qs quickshell >/dev/null 2>&1 && ${pkgs.procps}/bin/pidof hypridle >/dev/null 2>&1 && break
      ${pkgs.coreutils}/bin/sleep 0.2
    done
    ${pkgs.coreutils}/bin/sleep 1
    ${pkgs.systemd}/bin/loginctl lock-session
  '';
in
{
  krane.hypr = {
    monitors = [
      # Internal panel only. Docked outputs are left to Hyprland's defaults.
      {
        output = "eDP-1";
        mode = "preferred";
        position = "auto";
        scale = 1;
      }
    ];

    settings.input = {
      kb_layout = "at";
      kb_variant = "nodeadkeys";
      touchpad = {
        natural_scroll = true;
        tap_to_click = true;
      };
    };

    # Same as the desktop. See hosts/tariognatha/display.nix for why.
    variables = {
      terminal = "kitty";
      browser = "zen";
      codeEditor = "code";
      fileManager = "dolphin";
    };

    execOnce = [ "${lockOnStart}" ];
  };
}
