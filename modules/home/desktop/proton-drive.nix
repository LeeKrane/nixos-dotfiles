# Proton Drive via rclone, mounted on a plain directory under $HOME. rclone.conf is live state
# (2FA rewrites it in place). The wrapper is pkgs.proton-drive-mount, not an inline
# writeShellApplication; see its own comment.
{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  # A Nix path interpolated into a string is its store path, the LOGO_PATH format the script expects.
  logoPath = "${../../../scripts/assets/proton-drive-logo.png}";

  # Shared by ExecStart and ExecStop instead of systemd's %h, which isn't tied to config.home.homeDirectory.
  mountPath = "${config.home.homeDirectory}/ProtonDrive";
  rcloneConfigPath = "${config.home.homeDirectory}/.config/rclone/rclone.conf";

  # osConfig.sops.secrets has no rclone/config-seed until secrets/<host>.yaml exists; `?` tolerates that.
  hasRcloneSeed = osConfig.sops.secrets ? "rclone/config-seed";
in
{
  systemd.user.services.proton-drive-mount = {
    Unit = {
      Description = "Mount Proton Drive via rclone";
      PartOf = [ "graphical-session.target" ];
      # Skip (not fail) until rclone is configured, so an unconfigured host doesn't hit a config
      # error and a yad dialog on every login.
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
      ExecStop = "${pkgs.fuse}/bin/fusermount -u ${mountPath}";
    };
  };

  # Seed if absent: rclone.conf is live and rewritten in place on 2FA re-auth.
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

  # A home.file .keep would make the mountpoint non-empty, which rclone mount refuses without
  # --allow-non-empty.
  home.activation.ensureProtonDriveMountpoint = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "${mountPath}"
  '';

  home.packages = [ pkgs.proton-drive-mount ];
}
