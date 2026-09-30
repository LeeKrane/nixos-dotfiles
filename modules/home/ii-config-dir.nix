# ~/.config/illogical-impulse (ii's config.json, actions/ and presets/) lives in this repo, one
# directory per host, so settings changed in the ii settings window can be reviewed and committed.
# The directory is linked, not the file: switchwall.sh rewrites config.json with
# `jq ... > config.json.tmp && mv config.json.tmp config.json`, which would replace a file symlink
# with a regular file on every wallpaper change. Nix never reads config.json.
# See docs/II-INTEGRATION.md "Settings persistence".
{
  config,
  lib,
  pkgs,
  hostName,
  ...
}:
let
  target = "${config.home.homeDirectory}/.config/illogical-impulse";
  repoDir = "${config.krane.dotfilesDir}/hosts/${hostName}/illogical-impulse";
in
{
  options.krane.dotfilesDir = lib.mkOption {
    type = lib.types.str;
    default = "${config.home.homeDirectory}/.dotfiles";
    description = ''
      Absolute path of this repo's checkout on the host. install.sh and
      modules/nixvim/options.nix already assume ~/.dotfiles. Settings the ii settings
      window persists are written under it, so it must be the live checkout.
    '';
  };

  config = {
    home.file.".config/illogical-impulse".source = config.lib.file.mkOutOfStoreSymlink repoDir;

    # Before writeBoundary, so it runs before home-manager changes anything (like
    # checkLinkTargets). linkGeneration then moves a real directory aside as
    # illogical-impulse.hm-bak (backupFileExtension in lib/mk-host.nix).
    home.activation.kraneIiConfigMigrate = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
      src=${lib.escapeShellArg target}
      dst=${lib.escapeShellArg repoDir}
      if [ -d "$src" ] && [ ! -L "$src" ]; then
        if [ ! -d "$dst" ]; then
          echo "kraneIiConfigMigrate: $dst does not exist, so $src cannot be moved into the repo." >&2
          echo "Check out this repo at ${config.krane.dotfilesDir} (krane.dotfilesDir). Nothing was changed." >&2
          exit 1
        elif [ ! -e "$dst/config.json" ]; then
          echo "kraneIiConfigMigrate: copying $src into $dst"
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -an "$src/." "$dst/"
        elif [ -e "$src/config.json" ] && ! ${pkgs.diffutils}/bin/cmp -s "$src/config.json" "$dst/config.json"; then
          echo "kraneIiConfigMigrate: $src/config.json and $dst/config.json differ." >&2
          echo "Keep one by hand (move the other away), then switch again. Nothing was changed." >&2
          exit 1
        fi
      elif [ ! -d "$dst" ]; then
        # The VM check target has no checkout. Create the directory anyway: a dangling link would
        # make the soymou copy step's `mkdir -p ~/.config/illogical-impulse` fail and abort the
        # whole activation (set -e). ii then runs on its defaults into this stub directory.
        echo "kraneIiConfigMigrate: warning: $dst does not exist; creating it. ii settings are not in a checkout until this repo is at ${config.krane.dotfilesDir}." >&2
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$dst"
      fi
    '';

    # The link must exist before the soymou copy step runs its `mkdir -p` and config.json seed
    # check through it. Both are entryAfter writeBoundary, so pin the order instead of relying on
    # the DAG's tie-breaking. A second definition of copyIllogicalImpulseConfigs cannot add an
    # `after` (hm's dagEntryOf would treat it as a conflicting str), so this empty entry sits
    # between the two, like kraneIiSaveFishVars in illogical-impulse.nix.
    home.activation.kraneIiConfigLinkFirst =
      lib.hm.dag.entryBetween [ "copyIllogicalImpulseConfigs" ] [ "linkGeneration" ]
        ":";
  };
}
