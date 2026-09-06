# home-manager module: laptop display / input layout for tarmantria, imported at the user level
# from hosts/tarmantria/default.nix, rendered to Lua by modules/home/hypr-config.nix.
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
