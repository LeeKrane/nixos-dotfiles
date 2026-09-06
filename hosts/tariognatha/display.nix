# home-manager module: desktop display / input layout for tariognatha, imported at the user
# level from hosts/tariognatha/default.nix, rendered to Lua by modules/home/hypr-config.nix.
{ ... }:
{
  krane.hypr = {
    monitors = [
      # Primary, straight ahead.
      {
        output = "DP-2";
        mode = "2560x1440@144";
        position = "0x0";
        scale = 1;
      }
      # Rotated 90 deg clockwise (transform 3, Hyprland's 270 deg). Logical size after rotation
      # and the 1.25 scale is 1152x2048, so 2560x0 sits it right of DP-2. VERIFY ON TARGET: use
      # position = "-1152x0" for the left instead.
      {
        output = "DP-1";
        mode = "2560x1440@60";
        position = "2560x0";
        scale = 1.25;
        transform = 3;
      }
    ];

    settings.input = {
      kb_layout = "at";
      kb_variant = "nodeadkeys";
    };

    devices = [
      # VERIFY ON TARGET: name must match `hyprctl devices` exactly (Hyprland lowercases and
      # dash-joins libinput's name). -0.4 flat-profile sensitivity carried over from the previous setup.
      {
        name = "logitech-gaming-mouse-g502";
        settings = {
          accel_profile = "flat";
          sensitivity = -0.4;
        };
      }
    ];

    # Upstream defaults these to launch_first_available.sh probe chains. Naming the binaries
    # skips that. Plain command names, not store paths: Hyprland runs them through a shell.
    variables = {
      terminal = "kitty";
      browser = "zen";
      codeEditor = "code";
      fileManager = "dolphin";
    };
  };
}
