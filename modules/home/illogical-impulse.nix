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
}
