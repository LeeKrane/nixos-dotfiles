# restic backups, two halves, both off until a host enables them:
#   krane.backup        a client: one services.restic.backups job with this repo's defaults.
#   krane.backupServer  the repository host (taronychus): services.restic.server on wg0.
# Secrets are plain paths here; hosts point them at sops secrets.
{ config, lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
  cfg = config.krane.backup;
  srv = config.krane.backupServer;
  inherit (import ../../../lib/wireguard.nix) wg0;
  # The port is the last ":"-separated part of listenAddress.
  srvPort = lib.last (lib.splitString ":" srv.listenAddress);
in
{
  options.krane.backup = {
    enable = mkEnableOption "the restic backup job";
    repository = mkOption {
      type = types.str;
      example = "rest:http://backup@<taronychus wg0 IP>:8000/taragarmr";
      description = "restic repository URL.";
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
        `restic forget --prune` arguments run after each backup. An append-only server
        refuses deletes: set this to [ ] for such a repository and prune from the server side.
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

  options.krane.backupServer = {
    enable = mkEnableOption "the restic REST server";
    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/restic";
      description = "Directory holding the repositories.";
    };
    appendOnly = mkOption {
      type = types.bool;
      default = true;
      description = "Reject deletes and overwrites, so a compromised client cannot destroy its backups.";
    };
    listenAddress = mkOption {
      type = types.str;
      default = "${wg0.peers.taronychus.ip}:8000";
      defaultText = lib.literalExpression ''"<taronychus' wg0 IP>:8000"'';
      description = "ip:port to listen on (socket-activated). The port is opened on wg0 only.";
    };
    htpasswdFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/secrets/restic/htpasswd";
      description = "htpasswd file for client authentication; null disables authentication.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
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
      };
    })

    (lib.mkIf srv.enable {
      services.restic.server = {
        enable = true;
        inherit (srv) dataDir appendOnly listenAddress;
        htpasswd-file = srv.htpasswdFile;
      };
      # The address is wg0's, which may not exist yet when the socket is created at boot.
      systemd.sockets.restic-rest-server.socketConfig.FreeBind = true;
      networking.firewall.interfaces.${wg0.interface}.allowedTCPPorts = [ (lib.toInt srvPort) ];
    })
  ];
}
