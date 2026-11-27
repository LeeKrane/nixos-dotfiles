{ ... }:
{
  krane.hypr = {
    monitors = [
      {
        output = "eDP-1";
        mode = "preferred";
        scale = 1;
      }
    ];

    defaults.input = {
      kb_layout = "at";
      kb_variant = "nodeadkeys";
    };

    settings.input = {
      touchpad = {
        natural_scroll = true;
        tap_to_click = true;
      };
    };

    variables = {
      terminal = "kitty";
      browser = "zen-beta";
      codeEditor = "kitty -1 nvim";
      textEditor = "zeditor";
      fileManager = "dolphin";
    };
  };
}
