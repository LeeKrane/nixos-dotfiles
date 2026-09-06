# Proton Drive via rclone, replacing the previous host's btrfs subvolume mount (`/@protondrive`)
# with a plain directory under $HOME. See docs/MIGRATION-NOTES.md. rclone.conf is a live,
# not-declarative file: 2FA rewrites happen in place, so losing it means re-authenticating, not
# a config regression.
# The wrapper is `pkgs.proton-drive-mount`, not an inline writeShellApplication: its own comment
# explains why (in short, the default `set -euo pipefail` breaks its retry/2FA flow, and it needs
# to build and shellcheck independently).
{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  # Interpolating a Nix path into a string yields its store path as plain text, the LOGO_PATH
  # format scripts/proton-drive-rclone-mount.sh expects.
  logoPath = "${../../scripts/assets/proton-drive-logo.png}";

  # Shared by ExecStart and ExecStop, rather than ExecStop's old systemd specifier `%h`, which
  # happens to match config.home.homeDirectory today but isn't kept in sync with it.
  mountPath = "${config.home.homeDirectory}/ProtonDrive";
  rcloneConfigPath = "${config.home.homeDirectory}/.config/rclone/rclone.conf";

  # osConfig.sops.secrets has no `rclone/config-seed` attribute until secrets/<host>.yaml exists
  # and is encrypted (secrets/README.md). `?` tolerates that instead of throwing.
  hasRcloneSeed = osConfig.sops.secrets ? "rclone/config-seed";
in
{
  systemd.user.services.proton-drive-mount = {
    Unit = {
      Description = "Mount Proton Drive via rclone";
      PartOf = [ "graphical-session.target" ];
      # Skip the unit (not fail it) until rclone is configured, so an unconfigured host doesn't
      # hit proton-drive-mount's config-file error and a yad dialog on every login.
      ConditionPathExists = rcloneConfigPath;
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [
        "MOUNT_PATH=${mountPath}"
        "RCLONE_REMOTE=ProtonDrive"
        "RCLONE_CONFIG=${rcloneConfigPath}"
        "LOGO_PATH=${logoPath}"
      ];
      ExecStart = "${pkgs.proton-drive-mount}/bin/proton-drive-mount";
      # `fuse` (2.x) not `fuse3`: fuse3 ships `fusermount3`, and rclone's mount here needs the
      # classic `fusermount` ABI.
      ExecStop = "${pkgs.fuse}/bin/fusermount -u ${mountPath}";
    };
  };

  # Seed-if-absent: rclone.conf is live, rewritten in place on 2FA re-auth. Overwriting it every
  # switch would lose that session's 2FA state. Runs only once a config-seed secret exists.
  home.activation.seedRcloneConfig = lib.mkIf hasRcloneSeed (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      target="${rcloneConfigPath}"
      if [ ! -e "$target" ]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$target")"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 "${
          osConfig.sops.secrets."rclone/config-seed".path
        }" "$target"
      fi
    ''
  );

  # Plain directory, not a btrfs subvolume. See docs/MIGRATION-NOTES.md. A home.file .keep here
  # would make the mountpoint non-empty, and rclone mount refuses that without --allow-non-empty.
  # A later switch could also symlink .keep into the live mount. `mkdir -p` here only ensures
  # the directory exists, nothing more.
  home.activation.ensureProtonDriveMountpoint = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "${mountPath}"
  '';

  # rclone and yad are already home.packages'd in apps.nix (rclone drives the script, yad shows
  # its 2FA dialogs).
  home.packages = [ pkgs.proton-drive-mount ];
}
