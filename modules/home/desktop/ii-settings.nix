# Hyprland settings saved from the ii settings window. The GUI writes them, through
# krane-ii-settings (pkgs/krane-ii-settings), as sparse deltas into hosts/<host>/ii-settings.json.
# This module renders that file into the owned custom/krane_gui.lua, which monitors.lua requires
# last, and gives the writer its manifest: which keys Nix owns, and the monitor and idle
# baselines. Every key has exactly one owner, Nix or the GUI file; a key set in both fails
# evaluation. See docs/II-INTEGRATION.md "Settings persistence".
{
  config,
  lib,
  pkgs,
  hostName,
  ...
}:
let
  cfg = config.krane.hypr;
  home = config.home.homeDirectory;
  writer = pkgs.callPackage ../../../pkgs/krane-ii-settings { };
  # One key list for Nix and the writer; read here without building anything.
  schema = lib.importJSON ../../../pkgs/krane-ii-settings/schema.json;

  where = "hosts/${hostName}/ii-settings.json";
  src = ../../../hosts + "/${hostName}/ii-settings.json";
  gui = if builtins.pathExists src then lib.importJSON src else { };
  guiHypr = gui.hyprland or { };
  guiMonitors = gui.monitors or { };

  # { input = { kb_layout = "at"; }; } -> [ "input:kb_layout" ]
  flatten =
    prefix: attrs:
    lib.concatLists (
      lib.mapAttrsToList (
        k: v:
        let
          key = if prefix == "" then k else "${prefix}:${k}";
        in
        if builtins.isAttrs v then flatten key v else [ key ]
      ) attrs
    );
  nixHyprKeys = lib.unique (flatten "" cfg.settings ++ cfg.guiLocked);

  # These have defaults, so every monitor Nix declares sets them.
  fixedMonitorFields = [
    "output"
    "mode"
    "position"
    "scale"
    "disabled"
  ];
  # Nix-owned only when non-null. `or null` keeps this valid for fields the monitor submodule
  # does not have yet.
  optionalMonitorFields = [
    "transform"
    "vrr"
    "mirror"
    "bitdepth"
    "cm"
    "sdrbrightness"
    "sdrsaturation"
    "sdr_min_luminance"
    "sdr_max_luminance"
    "min_luminance"
    "max_luminance"
    "max_avg_luminance"
  ];
  nixMonitors = lib.listToAttrs (
    map (
      m:
      let
        setFields = lib.filter (f: (m.${f} or null) != null) optionalMonitorFields;
      in
      lib.nameValuePair m.output {
        owned = fixedMonitorFields ++ setFields;
        baseline = {
          inherit (m)
            output
            mode
            position
            scale
            ;
        }
        // lib.optionalAttrs m.disabled { disabled = true; }
        // lib.genAttrs setFields (f: m.${f});
      }
    ) cfg.monitors
  );

  # krane.hypr.idle, or idleTimeouts = false as shorthand for all zeros. null: not set by Nix.
  nixIdle =
    if cfg.idle != null then
      { inherit (cfg.idle) lock screenOff suspend; }
    else if !cfg.idleTimeouts then
      {
        lock = 0;
        screenOff = 0;
        suspend = 0;
      }
    else
      null;
  # ii's own hypridle.conf listeners at the pinned revision.
  iiIdle = {
    lock = 300;
    screenOff = 600;
    suspend = 900;
  };

  # What activation writes into hypridle.conf: Nix's values, else the GUI file's over ii's
  # defaults, else nothing (ii's copied hypridle.conf stays as it is).
  idleValues =
    if nixIdle != null then
      nixIdle
    else if gui ? idle then
      iiIdle // gui.idle
    else
      null;

  manifest = {
    host = hostName;
    repoFile = "${config.krane.dotfilesDir}/${where}";
    liveFile = "${home}/.config/hypr/custom/krane_gui.lua";
    hypridleFile = "${home}/.config/hypr/hypridle.conf";
    idleConfigurator = "${home}/.config/quickshell/ii/scripts/hyprland/hypridleconfigurator.py";
    qsBin = "${config.home.profileDirectory}/bin/qs";
    settingsQml = "${home}/.config/quickshell/ii/settings.qml";
    nixOwned = {
      hyprland = lib.sort lib.lessThan nixHyprKeys;
      idle = nixIdle != null;
      monitors = lib.mapAttrs (_: v: lib.sort lib.lessThan v.owned) nixMonitors;
    };
    monitorBaselines = lib.mapAttrs (_: v: v.baseline) nixMonitors;
    idleBaseline = if nixIdle != null then nixIdle else iiIdle;
  };
  manifestFile = pkgs.writeText "krane-ii-settings-manifest-${hostName}.json" (
    builtins.toJSON manifest
  );

  # The writer with this host's manifest baked in; what the GUI calls.
  wrapped = pkgs.writeShellScriptBin "krane-ii-settings" ''
    export KRANE_II_SETTINGS_MANIFEST=${manifestFile}
    exec ${writer}/bin/krane-ii-settings "$@"
  '';

  # Same renderer as the GUI uses at runtime. Plain build-time runCommand on repo files, not
  # import-from-derivation: the result is only installed, never read back into evaluation.
  rendered = pkgs.runCommand "krane-hypr-custom-krane_gui.lua" { } ''
    ${writer}/bin/krane-ii-settings --manifest ${manifestFile} \
      render --json ${pkgs.writeText "ii-settings-${hostName}.json" (builtins.toJSON gui)} > $out
  '';

  unknownKeys =
    map (k: "${k} (top level)") (
      lib.filter (
        k:
        !(lib.elem k [
          "animationPreset"
          "hyprland"
          "idle"
          "monitors"
        ])
      ) (lib.attrNames gui)
    )
    ++ map (k: "hyprland.${k}") (lib.filter (k: !(schema.hyprland ? ${k})) (lib.attrNames guiHypr))
    ++ map (k: "idle.${k}") (lib.filter (k: !(schema.idle ? ${k})) (lib.attrNames (gui.idle or { })))
    ++ lib.concatLists (
      lib.mapAttrsToList (
        o: fields:
        map (f: "monitors.${o}.${f}") (lib.filter (f: !(schema.monitor ? ${f})) (lib.attrNames fields))
      ) guiMonitors
    );

  overlap =
    map (k: "hyprland.${k}") (lib.filter (k: lib.elem k nixHyprKeys) (lib.attrNames guiHypr))
    ++ lib.optional ((gui ? idle) && nixIdle != null) "idle"
    ++ lib.concatLists (
      lib.mapAttrsToList (
        o: fields:
        map (f: "monitors.${o}.${f}") (
          lib.filter (f: lib.elem f (nixMonitors.${o}.owned or [ ])) (lib.attrNames fields)
        )
      ) guiMonitors
    );
in
{
  options.krane.hypr.guiLocked = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "general:layout" ];
    description = ''
      Hyprland keys (`section:key`, as in pkgs/krane-ii-settings/schema.json) that Nix wants
      left at the upstream default. The ii settings window shows them disabled with "Set in
      Nix", like any key set in krane.hypr.settings.
    '';
  };

  options.krane.iiSettings.manifestFile = lib.mkOption {
    type = lib.types.path;
    internal = true;
    readOnly = true;
    description = "The krane-ii-settings manifest for this host; used by checks.ii-settings-render.";
  };

  config = {
    krane.hypr._rendered."custom/krane_gui.lua" = rendered;
    krane.iiSettings.manifestFile = manifestFile;
    home.packages = [ wrapped ];

    # Display changes kept before this boot carry bootConfirmed = false. After the first
    # unlock, ask again and revert them 15 s later unless kept (krane-ii-settings boot-check).
    krane.hypr.execOnce = [ "${wrapped}/bin/krane-ii-settings boot-check" ];

    # Replaces the old hypridle.conf sed in illogical-impulse.nix. Runs ii's own
    # hypridleconfigurator.py (patches/ii/05-settings) with a pinned interpreter; the script is
    # standard-library only. hypridle reads its config at start: the change applies from the
    # next login, or at once when the GUI's writer restarts hypridle.
    home.activation.kraneIiIdle = lib.mkIf (idleValues != null) (
      lib.hm.dag.entryAfter [ "copyIllogicalImpulseConfigs" ] ''
        conf=${lib.escapeShellArg manifest.hypridleFile}
        script=${lib.escapeShellArg manifest.idleConfigurator}
        if [ -f "$conf" ] && [ -f "$script" ]; then
          $DRY_RUN_CMD ${pkgs.python3}/bin/python3 "$script" --file "$conf" \
            --lock ${toString idleValues.lock} \
            --screen-off ${toString idleValues.screenOff} \
            --suspend ${toString idleValues.suspend} >/dev/null
        fi
      ''
    );

    assertions = [
      {
        assertion = unknownKeys == [ ];
        message = ''
          ${where}: ${lib.concatStringsSep ", " unknownKeys} not in
          pkgs/krane-ii-settings/schema.json. Only keys checked against Hyprland 0.56 may be
          written; remove them, or add them to the schema after checking them.
        '';
      }
      {
        assertion = overlap == [ ];
        message = ''
          ${where} sets ${lib.concatStringsSep ", " overlap}, which Nix also sets
          (krane.hypr.settings, krane.hypr.guiLocked, krane.hypr.monitors or idle, in
          hosts/${hostName}/display.nix or modules/home). Every key has one owner: delete it
          from one of the two.
        '';
      }
      {
        assertion = cfg.idle == null || cfg.idleTimeouts;
        message = ''
          krane.hypr.idle and krane.hypr.idleTimeouts = false are both set; idleTimeouts = false
          is shorthand for idle = { lock = 0; screenOff = 0; suspend = 0; }. Keep one.
        '';
      }
      {
        assertion = lib.all (k: schema.hyprland ? ${k}) cfg.guiLocked;
        message = ''
          krane.hypr.guiLocked: ${
            lib.concatStringsSep ", " (lib.filter (k: !(schema.hyprland ? ${k})) cfg.guiLocked)
          } not in pkgs/krane-ii-settings/schema.json.
        '';
      }
    ];
  };
}
