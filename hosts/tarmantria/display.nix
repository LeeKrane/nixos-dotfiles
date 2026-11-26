{ ... }:
let
  internalOutputs = [
    "eDP-1"
    "eDP-2"
  ];
  internal = {
    mode = "2560x1440@240";
  };
in
{
  krane.hypr = {
    monitors = [
      # Positions are GUI-owned (ii-settings.json, settings app > Displays); re-drag them after
      # changing a scale here.
      {
        output = "HDMI-A-1";
        mode = "2560x1440@144";
        scale = 1;
      }
      # External Dell U2724DE over DisplayPort.
      {
        output = "DP-1";
        scale = 1;
      }
    ]
    ++ map (
      output:
      internal
      // {
        inherit output;
        scale = 1.25;
      }
    ) internalOutputs;

    # Internal panel scale: 1.25 alone, 1.6 with another output connected. Hyprland needs a scale
    # that divides the mode into whole logical pixels: 1.6 gives 1600x900, 1.25 gives 2048x1152.
    # Position: the GUI file, else the other internal name (eDP-1 or eDP-2 depending on the GPU
    # mux), else 0x0.
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
                  local gui = KRANE_GUI_MONITORS and KRANE_GUI_MONITORS[m.name]
                  local other = KRANE_GUI_MONITORS
                      and KRANE_GUI_MONITORS[m.name == "eDP-1" and "eDP-2" or "eDP-1"]
                  -- A GUI entry without its own position carries Nix's "auto" baseline: skip it.
                  local function gui_position(e)
                      return e and e.position ~= "auto" and e.position or nil
                  end
                  local rule = {
                      output = m.name,
                      mode = "${internal.mode}",
                      position = gui_position(gui) or gui_position(other) or "0x0",
                      scale = external and 1.6 or 1.25,
                  }
                  -- Carry over GUI-set fields (color management, HDR, transform, vrr, ...) so a
                  -- reload does not clobber them; output, mode, scale and position stay Nix's.
                  if gui then
                      for k, v in pairs(gui) do
                          if k ~= "output" and k ~= "mode" and k ~= "position" and k ~= "scale" then
                              rule[k] = v
                          end
                      end
                  end
                  hl.monitor(rule)
              end
          end
      end

      scale_internal()
      hl.on("monitor.added", function() scale_internal() end)
      hl.on("monitor.removed", function(m) scale_internal(m and m.name) end)
      -- custom/krane_gui.lua loads after this file; re-run so GUI-owned fields are merged back in.
      krane_after_gui = scale_internal
    '';

    settings.input = {
      kb_layout = "at";
      kb_variant = "nodeadkeys";
      touchpad = {
        natural_scroll = true;
        tap_to_click = true;
      };
    };

    # Fn+F10 sends KEY_TOUCHPAD_TOGGLE. Both the -touchpad and -mouse devices are toggled; the
    # off state is a marker file, so it survives reloads, logout and reboot.
    extraKeybindsLua = ''
      local kraneTouchpadMarker = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state"))
          .. "/hypr-touchpad-disabled"
      local function kraneSetTouchpad(on)
          for _, name in ipairs({ "asup1205:00-093a:2008-touchpad", "asup1205:00-093a:2008-mouse" }) do
              hl.device({ name = name, enabled = on })
          end
      end
      local marker = io.open(kraneTouchpadMarker, "r")
      local kraneTouchpadOn = marker == nil
      if marker then marker:close() end
      kraneSetTouchpad(kraneTouchpadOn)
      local function kraneToggleTouchpad()
          kraneTouchpadOn = not kraneTouchpadOn
          kraneSetTouchpad(kraneTouchpadOn)
          if kraneTouchpadOn then
              os.remove(kraneTouchpadMarker)
          else
              local f = io.open(kraneTouchpadMarker, "w")
              if f then f:close() end
          end
          hl.exec_cmd("notify-send -a Hyprland -t 1500 'Touchpad "
              .. (kraneTouchpadOn and "enabled" or "disabled") .. "'")
      end
    '';
    binds = [
      {
        keys = "XF86TouchpadToggle";
        action = "kraneToggleTouchpad";
        description = "Input: Toggle touchpad";
      }
    ];

    variables = {
      terminal = "kitty";
      browser = "zen-beta";
      codeEditor = "kitty -1 nvim";
      textEditor = "zeditor";
      fileManager = "dolphin";
    };
  };
}
