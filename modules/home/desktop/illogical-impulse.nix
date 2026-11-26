# Wrapper around the soymou ii module. Its copyIllogicalImpulseConfigs does rm -rf + cp -r over
# ~/.config/hypr on every switch, so home.file symlinks there die; overrides are written as plain
# files by a later DAG entry (docs/II-INTEGRATION.md). OWNED files replace the upstream copy.
# APPENDED files (custom/env.lua, custom/general.lua) are also written by the soymou module, so
# our block goes behind a sentinel and is replaced, never duplicated.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  rendered = config.krane.hypr._rendered;

  sentinel = "-- >>> krane overrides >>>";

  ownedFiles = [
    "monitors.lua"
    "custom/variables.lua"
    "custom/keybinds.lua"
    "custom/execs.lua"
    "custom/rules.lua"
    "custom/krane_gui.lua"
  ];

  appendedFiles = [
    "custom/env.lua"
    "custom/general.lua"
  ];

  hyprDir = "${config.home.homeDirectory}/.config/hypr";

  # Files sed-patched after ii's copy step recreates them (docs/II-INTEGRATION.md "Patched files").
  iiPatches = [
    {
      file = "${config.home.homeDirectory}/.config/fish/config.fish";
      sed = ''s|^\(\s*\)cat \(~/.local/state/quickshell/user/generated/terminal/sequences.txt\)|\1command cat \2|'';
      why = "modules/nixos/common/shells.nix aliases cat to bat; bypass it for raw OSC sequences";
    }
    {
      # pkill -f matches the full command line; [q] stops it matching the sh -c wrapper Hyprland
      # spawns for the keybind itself.
      file = "${hyprDir}/hyprland/keybinds.lua";
      sed = ''s|killall ydotool qs quickshell|killall ydotool; pkill -f '"'"'[q]s-wrapped -c ii'"'"'|'';
      why = "nix-wrapped quickshell truncates comm to .quickshell-wra, so killall qs quickshell never matches";
    }
    {
      # Fresh hosts seed config.json from this QML default; it stays ii-owned afterwards, so the
      # GUI can flip it back. Autologin goes straight to Hyprland (modules/nixos/desktop/desktop.nix)
      # with no session picker, so ii locks on startup.
      file = "${config.home.homeDirectory}/.config/quickshell/ii/modules/common/Config.qml";
      sed = "s/property bool launchOnStartup: false/property bool launchOnStartup: true/";
      why = "fresh hosts seed config.json from ii's QML defaults; want ii to lock immediately under greetd autologin";
    }
    {
      # No schemas are on the session's XDG_DATA_DIRS, so each call fails with "No schemas
      # installed"; point each call at them directly.
      file = "${config.home.homeDirectory}/.config/quickshell/ii/scripts/colors/switchwall.sh";
      # `#` delimiter, not `|`: `\|` is the alternation inside the pattern.
      sed = "s#gsettings \\(set\\|get\\) org.gnome.desktop.interface#GSETTINGS_SCHEMA_DIR=${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas ${pkgs.glib.bin}/bin/gsettings \\1 org.gnome.desktop.interface#g";
      why = "gsettings finds no schemas in the ii session, so the dark/light toggle never reaches the portal";
    }
  ];

  patchFile = entry: ''
    if [ -f "${entry.file}" ]; then
      $DRY_RUN_CMD ${pkgs.gnused}/bin/sed -i '${entry.sed}' "${entry.file}"
    fi
  '';

  # Drops everything from the sentinel to EOF first, so a stale block never sits above the fresh
  # one. A store script so $DRY_RUN_CMD can prefix it (a shell redirect can't be); `cat`, not
  # `mv`, preserves the file's mode.
  appendScript = pkgs.writeShellScript "krane-ii-override-block" ''
    set -eu
    target="$1"
    chunk="$2"
    sentinel="$3"
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$target")"
    if [ -e "$target" ]; then
      tmp="$target.krane-override.tmp"
      ${pkgs.gawk}/bin/awk -v s="$sentinel" '$0 == s { exit } { print }' "$target" > "$tmp"
      ${pkgs.coreutils}/bin/cat "$tmp" > "$target"
      ${pkgs.coreutils}/bin/rm -f "$tmp"
    fi
    { ${pkgs.coreutils}/bin/printf '\n%s\n' "$sentinel"; ${pkgs.coreutils}/bin/cat "$chunk"; } >> "$target"
  '';

  installOwned = name: ''
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -Dm644 ${rendered.${name}} "${hyprDir}/${name}"
  '';

  # Written even when the rendered body is empty, so the sentinel check in docs/VERIFY.md means
  # the same on every host.
  appendBlock = name: ''
    $DRY_RUN_CMD ${appendScript} "${hyprDir}/${name}" ${rendered.${name}} '${sentinel}'
  '';
in
{
  assertions = [
    {
      assertion =
        lib.sort lib.lessThan (ownedFiles ++ appendedFiles)
        == lib.sort lib.lessThan (lib.attrNames rendered);
      message = ''
        modules/home/desktop/illogical-impulse.nix: every file rendered by
        krane.hypr._rendered must be classified as owned or appended.
        Rendered: ${toString (lib.attrNames rendered)}
        Classified: ${toString (ownedFiles ++ appendedFiles)}
      '';
    }
    {
      # home-manager's DAG sorter silently ignores an unknown name in `after`; this turns a
      # renamed copyIllogicalImpulseConfigs into a build failure.
      assertion = config.home.activation ? copyIllogicalImpulseConfigs;
      message = ''
        illogical-flake no longer defines home.activation.copyIllogicalImpulseConfigs
        (pinned rev changed?), kraneIiOverrides ordering would be undefined. See
        docs/II-INTEGRATION.md.
      '';
    }
  ];

  # Default portal color-scheme until ii's toggle changes it; unset, apps following the system
  # preference fall back to light. Rewritten on every activation.
  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

  programs.illogical-impulse = {
    enable = true;

    dotfiles = {
      # fish/starship on makes HM write ~/.config/fish/config.fish, which the copy step replaces
      # with a regular file, hence backupFileExtension in lib/mk-host.nix. Our fish lives in NixOS
      # programs.fish (/etc/fish).
      fish.enable = true;
      kitty.enable = true;
      starship.enable = true;
    };

    # Empty: ii ships its own Quickshell overview, and hyprexpo isn't in nixpkgs' hyprland-plugins.
    hyprland.plugins = [ ];
  };

  home.activation.kraneIiOverrides = lib.hm.dag.entryAfter [ "copyIllogicalImpulseConfigs" ] (
    ''
      # Regular files, not symlinks: the copy step rm -rf's ~/.config/hypr.
    ''
    + lib.concatMapStrings installOwned ownedFiles
    + lib.concatMapStrings appendBlock appendedFiles
  );

  home.activation.kraneIiPatches = lib.hm.dag.entryAfter [ "copyIllogicalImpulseConfigs" ] (
    lib.concatMapStrings patchFile iiPatches
  );

  # copyIllogicalImpulseConfigs recopies ~/.config/hypr non-atomically; a running Hyprland reloads
  # mid-copy, hits `module 'hyprland.lib' not found` and latches emergency mode (no binds). Reload
  # once the tree is complete. `config-only` skips the monitor reapply. home-manager-<user>.service
  # lacks HYPRLAND_INSTANCE_SIGNATURE, so scan the runtime dir; `-S` is also true for a crashed
  # instance's socket, so the reload itself is the liveness test.
  home.activation.kraneIiHyprReload =
    lib.hm.dag.entryAfter [ "kraneIiOverrides" "kraneIiPatches" "kraneIiActivate" ]
      ''
        runtime="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
        reloadSig() {
          [ -S "$1/.socket.sock" ] || return 1
          HYPRLAND_INSTANCE_SIGNATURE="$(${pkgs.coreutils}/bin/basename "$1")" \
            ${pkgs.hyprland}/bin/hyprctl reload config-only >/dev/null
        }
        if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
          $DRY_RUN_CMD reloadSig "$runtime/hypr/$HYPRLAND_INSTANCE_SIGNATURE" || true
        elif [ -d "$runtime/hypr" ]; then
          for d in "$runtime"/hypr/*/; do
            [ -d "$d" ] || continue
            $DRY_RUN_CMD reloadSig "''${d%/}" && break || true
          done
        fi
      '';

  # copyIllogicalImpulseConfigs rm -rf's ~/.config/fish, taking fish_variables (incl.
  # __fish_initialized) with it and retriggering fish's 4.3 upgrade notice every activation. Saved
  # before the wipe, restored after (docs/II-INTEGRATION.md "Preserved files"). A `set -U` between
  # save and wipe is lost.
  home.activation.kraneIiSaveFishVars =
    lib.hm.dag.entryBetween [ "copyIllogicalImpulseConfigs" ] [ "writeBoundary" ]
      ''
        src="${config.home.homeDirectory}/.config/fish/fish_variables"
        dst="${config.home.homeDirectory}/.local/state/krane/fish_variables"
        if [ -f "$src" ]; then
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$dst")"
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -f "$src" "$dst"
        fi
      '';

  home.activation.kraneIiRestoreFishVars = lib.hm.dag.entryAfter [ "copyIllogicalImpulseConfigs" ] ''
    src="${config.home.homeDirectory}/.config/fish/fish_variables"
    dst="${config.home.homeDirectory}/.local/state/krane/fish_variables"
    if [ -f "$dst" ]; then
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "${config.home.homeDirectory}/.config/fish"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -f "$dst" "$src"
    fi
  '';
}
