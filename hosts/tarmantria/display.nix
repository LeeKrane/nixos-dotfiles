# home-manager module: laptop display / input layout for tarmantria, imported at the user level
# from hosts/tarmantria/default.nix, rendered to Lua by modules/home/hypr-config.nix.
{ ... }:
let
  # The panel is eDP-1 on the Intel iGPU in hybrid mode and eDP-2 on the NVIDIA dGPU once
  # gpu-mux.nix's MUX is set to dgpu. A rule for the absent name matches nothing.
  internalOutputs = [
    "eDP-1"
    "eDP-2"
  ];
  internal = {
    mode = "2560x1440@240";
    position = "0x0";
  };
in
{
  krane.hypr = {
    monitors = [
      # External MSI MAG322CQRV, to the left of the internal panel. EDID advertises
      # 143.97 Hz over HDMI; Hyprland otherwise picks the 59.95 Hz preferred mode.
      {
        output = "HDMI-A-1";
        mode = "2560x1440@144";
        position = "-2560x-360";
        scale = 1;
      }
    ]
    # Internal panel, to the right of the external one. Scale 1 when it is the only
    # output; extraMonitorsLua below raises it while an external monitor is attached.
    ++ map (
      output:
      internal
      // {
        inherit output;
        scale = 1;
      }
    ) internalOutputs;

    # Scale the internal panel up only while another output is connected. Hyprland
    # needs a scale that divides the mode into whole logical pixels; 1.6 gives
    # 1600x900 logical.
    # The external monitor sits at a negative x, so the panel keeps its 0x0 origin.
    extraMonitorsLua = ''
      local function is_internal(name)
          return name:match("^eDP%-") ~= nil
      end
      local function scale_internal(removed)
          local external = false
          for _, m in ipairs(hl.get_monitors()) do
              if not is_internal(m.name) and m.name ~= removed then
                  external = true
              end
          end
          for _, m in ipairs(hl.get_monitors()) do
              if is_internal(m.name) then
                  hl.monitor({
                      output = m.name,
                      mode = "${internal.mode}",
                      position = "${internal.position}",
                      scale = external and 1.6 or 1,
                  })
              end
          end
      end

      scale_internal()
      hl.on("monitor.added", function() scale_internal() end)
      hl.on("monitor.removed", function(m) scale_internal(m and m.name) end)
    '';

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
