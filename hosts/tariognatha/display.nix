# home-manager module: desktop display / input layout for tariognatha, imported at the user
# level from hosts/tariognatha/default.nix, rendered to Lua by modules/home/hypr-config.nix.
{ ... }:
{
  krane.hypr = {
    monitors = [
      # Primary, straight ahead.
      {
        output = "DP-2";
        mode = "3840x2160@240";
        position = "0x0";
        scale = 1.5;
      }
      {
        output = "DP-1";
        mode = "2560x1440@144";
		# If primary scaling is 1
        #position = "3840x0";
		# If primary scaling is 1.25
		#position = "3072x0";
		# If primary scaling is 1.25
        position = "2560x0";
        scale = 1;
      }
    ];

    settings.input = {
      kb_layout = "at";
      kb_variant = "nodeadkeys";
    };

    # Hyprland has no primary monitor: the cursor, focus and workspace 1 start on the lowest
    # monitor ID, which is DP-1 here. Pin them to DP-2 so the lock screen and startup land there.
    settings.cursor.default_monitor = "DP-2";

    # Desktop stays awake once booted: no idle lock, DPMS off or suspend.
    idleTimeouts = false;
    extraGeneralLua = ''
      hl.workspace_rule({ workspace = "1", monitor = "DP-2", default = true })
    '';

    devices = [
      # VERIFY ON TARGET: name must match `hyprctl devices` exactly (Hyprland lowercases and
      # dash-joins libinput's name). -0.4 flat-profile sensitivity carried over from the previous setup.
      {
        name = "logitech-gaming-mouse-g502";
        settings = {
          accel_profile = "flat";
          sensitivity = -0.9;
        };
      }
    ];

    # Upstream defaults these to launch_first_available.sh probe chains. Naming the binaries
    # skips that. Plain command names, not store paths: Hyprland runs them through a shell.
    variables = {
      terminal = "kitty";
      browser = "zen-beta";
      codeEditor = "kitty -1 nvim";
      textEditor = "kitty -1 nvim";
      fileManager = "dolphin";
    };
  };
}
