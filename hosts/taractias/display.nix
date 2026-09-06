# home-manager module: laptop display / input layout for taractias, imported at the user level
# from hosts/taractias/default.nix, rendered to Lua by modules/home/hypr-config.nix.
# VERIFY ON TARGET: the IdeaPad 330S ships in more than one panel resolution. Some units are
# 1366x768, not the 1920x1080 `mode = "preferred"` would pick on a Full HD panel. Check
# `hyprctl monitors -j` after first login and adjust `scale` if text is illegible.
{ ... }:
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
        # Dashed key: Hyprland spells this input:touchpad:tap-to-click, not a bare Lua
        # identifier, so the renderer emits ["tap-to-click"] instead.
        "tap-to-click" = true;
      };
    };

    # Same as the desktop. See hosts/tariognatha/display.nix for why.
    variables = {
      terminal = "kitty";
      browser = "zen";
      codeEditor = "code";
      fileManager = "dolphin";
    };
  };
}
