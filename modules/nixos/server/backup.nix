# krane.backup: one services.restic.backups job with this repo's defaults, off until a host
# enables it. Secrets are plain paths here; hosts point them at sops secrets.
{ config, lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
  cfg = config.krane.backup;
in
{
  options.krane.backup = {
    enable = mkEnableOption "the restic backup job";
    repository = mkOption {
      type = types.str;
      example = "/mnt/backup/restic/taragarmr";
      description = "restic repository: a local path or a restic URL (e.g. rest:http://...).";
    };
    passwordFile = mkOption {
      type = types.str;
      example = "/run/secrets/restic/password";
      description = "File with the repository password.";
    };
    environmentFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/run/secrets/restic/environment";
      description = "KEY=value file for the job, e.g. RESTIC_REST_USERNAME and RESTIC_REST_PASSWORD for a REST repository.";
    };
    paths = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Paths to back up.";
    };
    exclude = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Exclude patterns.";
    };
    timerConfig = mkOption {
      type = types.attrsOf types.anything;
      default = {
        OnCalendar = "04:00";
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
      description = "systemd timer for the job.";
    };
    pruneOpts = mkOption {
      type = types.listOf types.str;
      default = (import ../../../lib/backup-retention.nix).primary;
      defaultText = lib.literalExpression "(import lib/backup-retention.nix).primary";
      description = ''
        `restic forget --prune` arguments run after each backup. Set this to [ ] for a
        repository the client may not delete from (e.g. an append-only server).
      '';
    };
    retryLock = mkOption {
      type = types.str;
      default = "2h";
      example = "10m";
      description = ''
        How long `restic backup` waits for the repository lock (`--retry-lock`). Only an
        exclusive lock (a prune) blocks a backup; a host whose prepare command takes a
        service down for the run wants this short, so the outage stays bounded.
      '';
    };
    backupPrepareCommand = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Command run before the backup, e.g. a database dump.";
    };
    backupCleanupCommand = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Command run after the backup.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.restic.backups.default = {
      inherit (cfg)
        repository
        passwordFile
        environmentFile
        paths
        exclude
        timerConfig
        pruneOpts
        backupPrepareCommand
        backupCleanupCommand
        ;
      initialize = true;
      # A prune holds an exclusive repository lock now and then (other backups take shared
      # ones, which do not block); wait for it instead of failing the run (restic >= 0.16).
      extraBackupArgs = [ "--retry-lock ${cfg.retryLock}" ];
    };
  };
}
