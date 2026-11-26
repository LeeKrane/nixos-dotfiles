# Declarative Hyprland overrides for ii. ii is configured in Lua: hyprland.lua sources hyprland/*
# then custom/*.lua and monitors.lua. This module renders krane.hypr.* into Lua files in the store
# (krane.hypr._rendered); illogical-impulse.nix installs them after soymou's dotfiles copy.
# Sourcing order (dots/.config/hypr/hyprland.lua):
#   hyprland.lib -> hyprland.services -> hyprland.env -> custom.env
#   -> hyprland.{execs,general,rules,colors,keybinds} -> custom.execs
#   -> custom.general -> custom.rules -> custom.keybinds
#   -> workspaces.lua -> monitors.lua -> hyprland.shellOverrides.main
# custom/variables.lua is sourced from hyprland/keybinds.lua right after hyprland/variables.lua,
# so it overrides the terminal/browser/... globals. Monitor rules go in top-level monitors.lua.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.krane.hypr;

  # Nix -> Lua serialiser

  luaKeywords = [
    "and"
    "break"
    "do"
    "else"
    "elseif"
    "end"
    "false"
    "for"
    "function"
    "goto"
    "if"
    "in"
    "local"
    "nil"
    "not"
    "or"
    "repeat"
    "return"
    "then"
    "true"
    "until"
    "while"
  ];

  isLuaIdent =
    k: (builtins.match "[A-Za-z_][A-Za-z0-9_]*" k) != null && !(builtins.elem k luaKeywords);

  luaStr =
    s:
    ''"''
    + builtins.replaceStrings [ "\\" ''"'' "\n" "\t" "\r" ] [ "\\\\" ''\"'' "\\n" "\\t" "\\r" ] s
    + ''"'';

  # Hyprland's Lua config exposes every option with underscores: it rewrites `-` to
  # `_` and `:` to `.` when registering config keys, so settings keys here are plain
  # identifiers. The bracket form is kept only for keys that collide with Lua keywords.
  luaKey = k: if isLuaIdent k then k else "[${luaStr k}]";

  luaValue =
    indent: v:
    let
      padIn = indent + "    ";
    in
    if v == null then
      "nil"
    else if builtins.isBool v then
      (if v then "true" else "false")
    else if builtins.isInt v then
      toString v
    else if builtins.isFloat v then
      # toString renders 1.25 as "1.250000". toJSON keeps its shortest valid-Lua form instead.
      builtins.toJSON v
    else if builtins.isString v then
      luaStr v
    else if builtins.isList v then
      (
        if v == [ ] then
          "{}"
        else
          "{\n" + lib.concatMapStringsSep ",\n" (e: padIn + luaValue padIn e) v + "\n" + indent + "}"
      )
    else if builtins.isAttrs v then
      (
        if v == { } then
          "{}"
        else
          "{\n"
          + lib.concatStringsSep ",\n" (
            lib.mapAttrsToList (k: val: padIn + luaKey k + " = " + luaValue padIn val) v
          )
          + "\n"
          + indent
          + "}"
      )
    else
      throw "krane.hypr: cannot serialise a value of type ${builtins.typeOf v} to Lua";

  luaFields =
    indent: fields:
    let
      padIn = indent + "    ";
      kept = builtins.filter (f: f.value != null) fields;
    in
    if kept == [ ] then
      "{}"
    else
      "{\n"
      + lib.concatMapStringsSep ",\n" (f: padIn + luaKey f.name + " = " + luaValue padIn f.value) kept
      + "\n"
      + indent
      + "}";

  # File rendering

  header = target: ''
    -- GENERATED FILE -- DO NOT EDIT.
    -- Rendered from krane.hypr.* by modules/home/desktop/hypr-config.nix and installed
    -- as ~/.config/hypr/${target} by home.activation.kraneIiOverrides.
    -- Every `home-manager switch` overwrites (or re-appends) this content.
  '';

  # Color management and luminance fields, in the order krane-ii-settings renders them. Each name
  # was checked against Hyprland 0.56's Lua monitor parser (LuaBindingsConfigRules.cpp): an
  # unknown hl.monitor field is a hard error at Hyprland start.
  colorFields = [
    "cm"
    "sdrbrightness"
    "sdrsaturation"
    "sdr_min_luminance"
    "sdr_max_luminance"
    "min_luminance"
    "max_luminance"
    "max_avg_luminance"
  ];

  monitorLua =
    m:
    "hl.monitor("
    + luaFields "" (
      [
        {
          name = "output";
          value = m.output;
        }
        {
          name = "mode";
          value = m.mode;
        }
        {
          name = "position";
          value = if m.position == null then "auto" else m.position;
        }
        {
          name = "scale";
          value = m.scale;
        }
        {
          name = "transform";
          value = m.transform;
        }
        {
          name = "vrr";
          value = m.vrr;
        }
        {
          name = "mirror";
          value = m.mirror;
        }
        {
          name = "bitdepth";
          value = m.bitdepth;
        }
        {
          name = "disabled";
          value = if m.disabled then true else null;
        }
      ]
      ++ map (f: {
        name = f;
        value = m.${f};
      }) colorFields
    )
    + ")\n";

  deviceLua =
    d:
    "hl.device("
    + luaFields "" (
      [
        {
          name = "name";
          value = d.name;
        }
      ]
      ++ lib.mapAttrsToList (k: v: {
        name = k;
        value = v;
      }) d.settings
    )
    + ")\n";

  bindLua =
    b:
    let
      opts =
        lib.optional b.repeating "repeating = true"
        ++ lib.optional (b.description != null) "description = ${luaStr b.description}";
    in
    "hl.bind(${luaStr b.keys}, ${b.action}"
    + (lib.optionalString (opts != [ ]) ", { ${lib.concatStringsSep ", " opts} }")
    + ")\n";

  # The trailer loads the settings saved from the ii settings window (ii-settings.nix) last, after
  # every krane.hypr.* file and extraMonitorsLua, before ii's transient shellOverrides. A
  # krane_after_gui hook from extraMonitorsLua (e.g. hosts/tarmantria/display.nix's scale_internal)
  # runs after custom/krane_gui.lua so GUI-owned fields survive a reload or hotplug.
  monitorsFile =
    header "monitors.lua"
    + "\n"
    + lib.concatMapStrings monitorLua cfg.monitors
    + lib.optionalString (cfg.extraMonitorsLua != "") ("\n" + cfg.extraMonitorsLua + "\n")
    + ''

      if is_file_exists(HOME .. "/.config/hypr/custom/krane_gui.lua") then
          require("custom.krane_gui")
          if krane_after_gui then krane_after_gui() end
      end
    '';

  envFile =
    header "custom/env.lua"
    + "\n"
    + lib.concatStrings (lib.mapAttrsToList (k: v: "hl.env(${luaStr k}, ${luaStr v})\n") cfg.env);

  variablesFile =
    header "custom/variables.lua"
    + ''

      -- Plain Lua globals, read by hyprland/keybinds.lua after hyprland/variables.lua sets the
      -- upstream defaults.
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (
        k: v:
        # A Lua global can't be bracket-quoted like a table key: `["x-y"] = 1` is a syntax error at
        # file scope.
        if isLuaIdent k then
          "${k} = ${luaValue "" v}\n"
        else
          throw "krane.hypr.variables: ${builtins.toJSON k} is not a valid Lua identifier and cannot be a global"
      ) cfg.variables
    );

  generalFile =
    header "custom/general.lua"
    + "\n"
    + lib.optionalString (cfg.settings != { }) "hl.config(${luaValue "" cfg.settings})\n"
    + lib.optionalString (cfg.devices != [ ]) ("\n" + lib.concatMapStrings deviceLua cfg.devices)
    + lib.optionalString (cfg.extraGeneralLua != "") ("\n" + cfg.extraGeneralLua + "\n");

  keybindsFile =
    header "custom/keybinds.lua"
    + "\n"
    + lib.concatMapStrings (k: "hl.unbind(${luaStr k})\n") cfg.unbinds
    + lib.optionalString (cfg.extraKeybindsLua != "") ("\n" + cfg.extraKeybindsLua + "\n")
    + lib.concatMapStrings bindLua cfg.binds;

  execsFile =
    header "custom/execs.lua"
    + "\n"
    + lib.optionalString (cfg.execOnce != [ ]) (
      ''
        hl.on("hyprland.start", function()
      ''
      + lib.concatMapStrings (c: "    hl.exec_cmd(${luaStr c})\n") cfg.execOnce
      + "end)\n"
    );

  rulesFile =
    header "custom/rules.lua"
    + "\n"
    + lib.concatMapStrings (r: "hl.window_rule(${luaValue "" r})\n") cfg.windowRules;

  # Option types

  monitorType = lib.types.submodule {
    options = {
      output = lib.mkOption {
        type = lib.types.str;
        example = "DP-2";
        description = "Connector name; `hl.monitor` requires it and rejects a missing one.";
      };
      mode = lib.mkOption {
        type = lib.types.str;
        default = "preferred";
        example = "2560x1440@144";
        description = "Resolution and refresh rate, or `preferred`/`highres`/`highrr`.";
      };
      position = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "2560x0";
        description = ''
          Layout position, or `auto`/`auto-left`/.... null leaves it to the ii settings window
          (hosts/<host>/ii-settings.json) and renders `auto` here.
        '';
      };
      scale = lib.mkOption {
        type = lib.types.either lib.types.number lib.types.str;
        default = 1;
        example = 1.25;
        description = "Fractional scale, or the string `auto`.";
      };
      transform = lib.mkOption {
        type = lib.types.nullOr (lib.types.ints.between 0 7);
        default = null;
        description = "wl_output transform; 1 = 90 deg, 2 = 180 deg, 3 = 270 deg.";
      };
      vrr = lib.mkOption {
        type = lib.types.nullOr (lib.types.ints.between (-1) 3);
        default = null;
        description = "Per-monitor VRR override (-1 = follow the global setting).";
      };
      mirror = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Output to mirror.";
      };
      bitdepth = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "10 enables 10-bit output; anything else means 8-bit.";
      };
      disabled = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Disable this output.";
      };
      cm = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "auto"
            "srgb"
            "wide"
            "edid"
            "hdr"
            "hdredid"
            "dcip3"
            "dp3"
            "adobe"
          ]
        );
        default = null;
        description = "Color management preset. `hdr` needs `bitdepth = 10`.";
      };
      sdrbrightness = lib.mkOption {
        type = lib.types.nullOr lib.types.number;
        default = null;
        description = "SDR content brightness multiplier while in HDR mode.";
      };
      sdrsaturation = lib.mkOption {
        type = lib.types.nullOr lib.types.number;
        default = null;
        description = "SDR content saturation multiplier while in HDR mode.";
      };
      sdr_min_luminance = lib.mkOption {
        type = lib.types.nullOr lib.types.number;
        default = null;
        description = "SDR minimum luminance in nits, for SDR-to-HDR mapping.";
      };
      sdr_max_luminance = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "SDR maximum luminance in nits, for SDR-to-HDR mapping.";
      };
      min_luminance = lib.mkOption {
        type = lib.types.nullOr lib.types.number;
        default = null;
        description = "Override the EDID minimum luminance, in nits.";
      };
      max_luminance = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Override the EDID maximum luminance, in nits.";
      };
      max_avg_luminance = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Override the EDID maximum average luminance, in nits.";
      };
    };
  };
in
{
  options.krane.hypr = {
    monitors = lib.mkOption {
      type = lib.types.listOf monitorType;
      default = [ ];
      description = "Monitor rules rendered into ~/.config/hypr/monitors.lua.";
    };

    extraMonitorsLua = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Verbatim Lua appended to the end of monitors.lua. monitors.lua is sourced last,
        so this is the place for hotplug hooks that must override the static rules.
      '';
    };

    env = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        GDK_SCALE = "1";
      };
      description = ''
        Environment variables rendered as `hl.env(k, v)` and appended to
        ~/.config/hypr/custom/env.lua. Appended, not owned: illogical-flake
        truncates that file on every switch to inject the Nix PATH/XDG_DATA_DIRS
        fixes, so our block has to land after it.
      '';
    };

    variables = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.oneOf [
          lib.types.str
          lib.types.int
          lib.types.bool
        ]
      );
      default = { };
      example = {
        terminal = "kitty";
      };
      description = ''
        Lua globals rendered into ~/.config/hypr/custom/variables.lua. Upstream
        names (dots/.config/hypr/hyprland/variables.lua): terminal, fileManager,
        browser, codeEditor, officeSoftware, textEditor, volumeMixer,
        settingsApp, taskManager, workspaceGroupSize. Values are raw shell
        commands, not package paths.
      '';
    };

    unbinds = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "SUPER + Period" ];
      description = ''
        Upstream ii binds to remove, in `hl.bind` key syntax. Rendered as
        `hl.unbind(...)` before `binds`, since Hyprland fires every bind that
        matches a key and custom/keybinds.lua loads after the upstream file.
      '';
    };

    extraKeybindsLua = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Raw Lua inserted into custom/keybinds.lua after `unbinds` and before
        `binds`, for local helper functions referenced from `binds.*.action`.
      '';
    };

    binds = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            keys = lib.mkOption {
              type = lib.types.str;
              example = "SUPER + T";
              description = "Key combination, in `hl.bind` syntax.";
            };
            action = lib.mkOption {
              type = lib.types.str;
              example = "hl.dsp.exec_cmd(terminal)";
              description = "Raw Lua expression for the dispatcher; inserted verbatim.";
            };
            description = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Shown in the ii cheatsheet.";
            };
            repeating = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Repeat while held (Hyprland `bind` flag `e`).";
            };
          };
        }
      );
      default = [ ];
      description = "Keybinds rendered into ~/.config/hypr/custom/keybinds.lua.";
    };

    execOnce = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Commands run once per session, wrapped in
        `hl.on("hyprland.start", function() ... end)` in
        ~/.config/hypr/custom/execs.lua.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      example = {
        input = {
          kb_layout = "at";
        };
      };
      description = ''
        Nested `hl.config` tree appended to ~/.config/hypr/custom/general.lua.
        Keys are Hyprland config paths with `:` replaced by nesting; unknown
        keys are a hard error at Hyprland start, not at eval time.
      '';
    };

    devices = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              example = "logitech-gaming-mouse-g502";
              description = ''
                Device name as Hyprland sees it (`hyprctl devices`); spaces are
                turned into dashes by Hyprland itself.
              '';
            };
            settings = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
              example = {
                sensitivity = -0.4;
              };
              description = "Per-device options (sensitivity, accel_profile, natural_scroll, ...).";
            };
          };
        }
      );
      default = [ ];
      description = "Per-device overrides rendered as `hl.device({...})` into custom/general.lua.";
    };

    windowRules = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = [ ];
      example = [
        {
          match = {
            class = "^(kitty)$";
          };
          float = true;
        }
      ];
      description = "Rules rendered as `hl.window_rule({...})` into custom/rules.lua.";
    };

    extraGeneralLua = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Verbatim Lua appended to the end of custom/general.lua.";
    };

    idleTimeouts = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        false is shorthand for `idle = { lock = 0; screenOff = 0; suspend = 0; }`: the session
        never locks, blanks or suspends on its own; manual lock and lock-before-sleep stay. Kept
        for compatibility; do not combine with `idle`.
      '';
    };

    idle = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = lib.genAttrs [ "lock" "screenOff" "suspend" ] (
            _:
            lib.mkOption {
              type = lib.types.ints.between 0 86400;
              description = "Seconds idle before this hypridle listener fires; 0 removes it.";
            }
          );
        }
      );
      default = null;
      example = {
        lock = 600;
        screenOff = 900;
        suspend = 0;
      };
      description = ''
        hypridle timeouts. null (the default) leaves them to the ii settings window
        (hosts/<host>/ii-settings.json) or ii's own 300/600/900. Setting this makes idle
        Nix-owned: the settings window shows it disabled. Written into
        ~/.config/hypr/hypridle.conf at activation by modules/home/desktop/ii-settings.nix.
      '';
    };

    _rendered = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      internal = true;
      description = ''
        Rendered Lua files, keyed by their path relative to ~/.config/hypr.
        Set here and by modules/home/desktop/ii-settings.nix (custom/krane_gui.lua).
        Consumed by modules/home/desktop/illogical-impulse.nix (installation) and by
        the flake's `lua-syntax` check (`luac -p`).
      '';
    };
  };

  config.krane.hypr._rendered = {
    "monitors.lua" = pkgs.writeText "krane-hypr-monitors.lua" monitorsFile;
    "custom/env.lua" = pkgs.writeText "krane-hypr-custom-env.lua" envFile;
    "custom/variables.lua" = pkgs.writeText "krane-hypr-custom-variables.lua" variablesFile;
    "custom/general.lua" = pkgs.writeText "krane-hypr-custom-general.lua" generalFile;
    "custom/keybinds.lua" = pkgs.writeText "krane-hypr-custom-keybinds.lua" keybindsFile;
    "custom/execs.lua" = pkgs.writeText "krane-hypr-custom-execs.lua" execsFile;
    "custom/rules.lua" = pkgs.writeText "krane-hypr-custom-rules.lua" rulesFile;
  };
}
