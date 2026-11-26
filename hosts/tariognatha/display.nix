{ ... }:
{
  krane.hypr = {
    # Positions are GUI-owned (ii-settings.json, settings app > Displays); re-drag them after
    # changing DP-2's scale.
    monitors = [
      {
        output = "DP-2";
        mode = "3840x2160@240";
        scale = 1.5;
      }
      {
        output = "DP-1";
        mode = "2560x1440@144";
        scale = 1;
      }
    ];

    settings.input = {
      kb_layout = "at";
      kb_variant = "nodeadkeys";
    };

    settings.cursor.default_monitor = "DP-2";

    settings.render.cm_auto_hdr = 0;

    idleTimeouts = false;
    extraGeneralLua = ''
      hl.workspace_rule({ workspace = "1", monitor = "DP-2", default = true })
    '';

    devices = [
      {
        name = "logitech-gaming-mouse-g502";
        settings = {
          accel_profile = "flat";
          sensitivity = -0.9;
        };
      }
    ];

    # Naming the binaries skips upstream's launch_first_available.sh probe chains. Plain command
    # names: Hyprland runs them through a shell.
    variables = {
      terminal = "kitty";
      browser = "zen-beta";
      codeEditor = "kitty -1 nvim";
      textEditor = "zeditor";
      fileManager = "dolphin";
    };
  };
}
