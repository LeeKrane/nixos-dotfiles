# Wrapper around the soymou module (end-4's illogical-impulse shell), imported in lib/mk-host.nix.
# Its activation entry copyIllogicalImpulseConfigs does rm -rf + cp -r over ~/.config/hypr on
# every switch, so home.file symlinks there die. Our overrides are written as plain files by a
# later DAG entry instead. See docs/II-INTEGRATION.md.
# OWNED files (monitors.lua, custom/{variables,keybinds,execs,rules}.lua) replace the upstream
# copy with install -Dm644. APPENDED files (custom/env.lua, custom/general.lua) are also written
# by the soymou module, so our block goes behind a sentinel and is replaced, never duplicated.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  rendered = config.krane.hypr._rendered;

  # Start-of-block marker for appended files. Must match the replace logic below and
  # docs/VERIFY.md's on-target check exactly, as a whole line.
  sentinel = "-- >>> krane overrides >>>";

  ownedFiles = [
    "monitors.lua"
    "custom/variables.lua"
    "custom/keybinds.lua"
    "custom/execs.lua"
    "custom/rules.lua"
  ];

  appendedFiles = [
    "custom/env.lua"
    "custom/general.lua"
  ];

  # Hardcoded $HOME/.config, not config.xdg.configHome: must agree with the soymou module's
  # own hardcoded targetPath, or our overrides land somewhere ii never reads.
  hyprDir = "${config.home.homeDirectory}/.config/hypr";

  # Files this repo sed-patches after ii (re)writes them, since ii's copy step recreates
  # each one from scratch every switch. See docs/II-INTEGRATION.md "Patched files".
  iiPatches = [
    {
      # ii pins dots-hyprland at a revision whose generate_colors_material.py still reads
      # material_colors['primary_paletteKeyColor'], but nixpkgs' python3Packages.materialyoucolor
      # (3.0.4) renamed that key to primaryPaletteKeyColor, so every switchwall.sh run throws
      # KeyError and leaves material_colors.scss (and kitty's generated theme) empty. Remove this
      # once ii's pinned rev or the packaged materialyoucolor version makes the names agree again.
      file = "${config.home.homeDirectory}/.config/quickshell/ii/scripts/colors/generate_colors_material.py";
      sed = "s/primary_paletteKeyColor/primaryPaletteKeyColor/g";
      why = "materialyoucolor 3.0.4 renamed primary_paletteKeyColor to primaryPaletteKeyColor";
    }
    {
      # modules/nixos/shells.nix aliases cat to bat at NixOS level (/etc/fish loads first);
      # ii's config.fish must bypass that alias to print raw OSC sequences, not a bat frame.
      file = "${config.home.homeDirectory}/.config/fish/config.fish";
      sed = ''s|^\(\s*\)cat \(~/.local/state/quickshell/user/generated/terminal/sequences.txt\)|\1command cat \2|'';
      why = "modules/nixos/shells.nix aliases cat to bat; bypass it for raw OSC sequences";
    }
  ];

  patchFile = entry: ''
    if [ -f "${entry.file}" ]; then
      $DRY_RUN_CMD ${pkgs.gnused}/bin/sed -i '${entry.sed}' "${entry.file}"
    fi
  '';

  # Drops everything from the sentinel to EOF first, so a stale block from an older generation
  # never sits above the fresh one. A store script, not inline: a shell redirect can't be
  # prefixed with $DRY_RUN_CMD, so dry-run mode would still write. `cat`, not `mv`, preserves
  # the file's mode.
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

  # Written even when the rendered body is empty, so docs/VERIFY.md's sentinel check means the
  # same thing on every host regardless of whether it sets the option.
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
        modules/home/illogical-impulse.nix: every file rendered by
        krane.hypr._rendered must be classified as owned or appended.
        Rendered: ${toString (lib.attrNames rendered)}
        Classified: ${toString (ownedFiles ++ appendedFiles)}
      '';
    }
    {
      # home-manager's DAG sorter silently ignores an unknown name in `after`, so a renamed or
      # removed copyIllogicalImpulseConfigs would misorder us with no error. This assertion
      # turns that into a loud build failure instead.
      assertion = config.home.activation ? copyIllogicalImpulseConfigs;
      message = ''
        illogical-flake no longer defines home.activation.copyIllogicalImpulseConfigs
        (pinned rev changed?), kraneIiOverrides ordering would be undefined. See
        docs/II-INTEGRATION.md.
      '';
    }
  ];

  programs.illogical-impulse = {
    enable = true;

    dotfiles = {
      # fish/starship on means HM writes ~/.config/fish/config.fish, which the copy step
      # replaces with a regular file, hence lib/mk-host.nix's backupFileExtension. Our own
      # fish lives in NixOS `programs.fish.*` (/etc/fish), outside the wiped set.
      fish.enable = true;
      kitty.enable = true;
      starship.enable = true;
    };

    # Empty on purpose: ii ships its own Quickshell overview instead of hyprexpo, which also
    # isn't in nixpkgs' hyprland-plugins.
    hyprland.plugins = [ ];
  };

  # Runs after copyIllogicalImpulseConfigs rewrites custom/env.lua and custom/general.lua.
  # The assertion above catches a renamed upstream entry as a build failure, not silent
  # misordering.
  home.activation.kraneIiOverrides = lib.hm.dag.entryAfter [ "copyIllogicalImpulseConfigs" ] (
    ''
      # Declarative Hyprland overrides (krane.hypr.*, modules/home/hypr-config.nix).
      # Regular files, not symlinks: the copy step above rm -rf's ~/.config/hypr.
    ''
    + lib.concatMapStrings installOwned ownedFiles
    + lib.concatMapStrings appendBlock appendedFiles
  );

  # Sibling to kraneIiOverrides rather than folded into it: these patch files ii itself
  # writes or wipes, not a Hyprland file, and don't fit the owned/appended/assertion
  # machinery above.
  home.activation.kraneIiPatches = lib.hm.dag.entryAfter [ "copyIllogicalImpulseConfigs" ] (
    lib.concatMapStrings patchFile iiPatches
  );

  # copyIllogicalImpulseConfigs rm -rf's ~/.config/fish before recopying it, taking
  # fish_variables (universal vars, incl. __fish_initialized) with it. That retriggers
  # fish's 4.3 upgrade notice and conf.d/fish_frozen_key_bindings.fish every activation.
  # Save it before the wipe, restore it after. See docs/II-INTEGRATION.md "Preserved files".
  # A fish instance that runs set -U between the save and ii's rm -rf loses that write; acceptable.
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
