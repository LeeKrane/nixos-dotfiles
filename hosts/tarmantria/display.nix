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
        tap_to_click = true;
      };
    };

    # Same as the desktop. See hosts/tariognatha/display.nix for why.
    variables = {
      terminal = "kitty";
      browser = "zen-beta";
      codeEditor = "kitty -1 nvim";
      textEditor = "kitty -1 nvim";
      fileManager = "dolphin";
    };
  };
}
