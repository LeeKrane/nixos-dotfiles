# Declarative Hyprland overrides for ii. ii is configured in Lua, not hyprland.conf:
# hyprland.lua sources hyprland/* then custom/*.lua and monitors.lua. This module only renders
# krane.hypr.* into Lua files in the store (krane.hypr._rendered). Installing them into $HOME is
# modules/home/illogical-impulse.nix's job, since that must run after soymou's dotfiles copy.
# Sourcing order (dots/.config/hypr/hyprland.lua):
#   hyprland.lib -> hyprland.services -> hyprland.env -> custom.env
#   -> hyprland.{execs,general,rules,colors,keybinds} -> custom.execs
#   -> custom.general -> custom.rules -> custom.keybinds
#   -> workspaces.lua -> monitors.lua -> hyprland.shellOverrides.main
# custom/variables.lua is sourced from hyprland/keybinds.lua instead, right after
# hyprland/variables.lua, which is why it is the place to override terminal/browser/... globals.
# There is no custom/monitors.lua: monitor rules go in top-level monitors.lua instead.
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

  # Hyprland config keys are not all valid Lua identifiers, such as the dashed
  # `input:touchpad:tap-to-click`, so those become `["key"] = value` instead.
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

  # fields is an ordered list of { name, value } so output/name come first, not alphabetically.
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
    -- Rendered from krane.hypr.* by modules/home/hypr-config.nix and installed
    -- as ~/.config/hypr/${target} by home.activation.kraneIiOverrides.
    -- Every `home-manager switch` overwrites (or re-appends) this content.
  '';

  monitorLua =
    m:
    "hl.monitor("
    + luaFields "" [
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
        value = m.position;
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
    "hl.bind(${luaStr b.keys}, ${b.action}"
    + (lib.optionalString (b.description != null) ", { description = ${luaStr b.description} }")
    + ")\n";

  monitorsFile = header "monitors.lua" + "\n" + lib.concatMapStrings monitorLua cfg.monitors;

  envFile =
    header "custom/env.lua"
    + "\n"
    + lib.concatStrings (lib.mapAttrsToList (k: v: "hl.env(${luaStr k}, ${luaStr v})\n") cfg.env);

  variablesFile =
    header "custom/variables.lua"
    + ''

      -- These are plain Lua globals, read by hyprland/keybinds.lua after it has
      -- sourced hyprland/variables.lua (which sets the upstream defaults).
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (
        k: v:
        # A Lua global can't be bracket-quoted like a table key: `["x-y"] = 1` is a syntax
        # error at file scope, which luac -p only catches once someone has written it.
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

  keybindsFile = header "custom/keybinds.lua" + "\n" + lib.concatMapStrings bindLua cfg.binds;

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
        type = lib.types.str;
        default = "auto";
        example = "2560x0";
        description = "Layout position, or `auto`/`auto-left`/...";
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

    _rendered = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      internal = true;
      readOnly = true;
      description = ''
        Rendered Lua files, keyed by their path relative to ~/.config/hypr.
        Consumed by modules/home/illogical-impulse.nix (installation) and by
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
