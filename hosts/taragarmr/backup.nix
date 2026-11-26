# restic backup to the external drive (backup-drive.nix). CouchDB writes append-only files
# continuously, so the job stops its container for the run and the cleanup command restarts it,
# also after a failed backup. Pruning is a separate weekly unit so the stop lasts only as long
# as the backup. Secret `restic/repo-password`; without the `restic` section the job is off.
{
  config,
  lib,
  pkgs,
  hostName,
  ...
}:
let
  hostSecrets = import ../../lib/host-secrets.nix { inherit lib hostName; };
  home = config.users.users.${config.krane.user.name}.home;
  stage = "/var/lib/krane-backup-stage";
  systemctl = "${config.systemd.package}/bin/systemctl";
  repository = "/mnt/backup/restic/taragarmr";
  passwordFile = config.sops.secrets."restic/repo-password".path;
  retention = (import ../../lib/backup-retention.nix).primary;

  prepare = pkgs.writeShellScript "taragarmr-backup-prepare" ''
    set -u
    ${systemctl} stop docker-couchdb.service || true

    rm -rf ${stage}
    install -d -m 0700 ${stage}
    for root in spt-headless spt-headless-2; do
      install -d ${stage}/$root/game
      for f in HeadlessConfig.json* run-headless.sh setup-headless.sh sync-instances.sh; do
        cp -a ${home}/$root/$f ${stage}/$root/ 2>/dev/null || true
      done
      cp -a ${home}/$root/game/HeadlessConfig.json* ${stage}/$root/game/ 2>/dev/null || true
    done
    cp -a ${home}/.config/teamclaude.json ${stage}/ 2>/dev/null || true
    exit 0
  '';
  cleanup = pkgs.writeShellScript "taragarmr-backup-cleanup" ''
    ${systemctl} start docker-couchdb.service || true
    rm -rf ${stage}
  '';
in
{
  config = lib.mkIf (hostSecrets.hasSection "restic") {
    sops.secrets."restic/repo-password" = {
      owner = "root";
      mode = "0400";
    };

    systemd.services.restic-backups-default.unitConfig.RequiresMountsFor = [ "/mnt/backup" ];

    krane.backup = {
      enable = true;
      inherit repository passwordFile;
      # restic-prune below does this, outside the CouchDB downtime.
      pruneOpts = [ ];
      paths = [
        "/srv/couchdb"
        "${home}/spt-server"
        stage
      ];
      exclude = [
        "${home}/spt-server/_download"
        "${home}/spt-server/smoketest.*"
        "${home}/spt-server/SPT_Runtime/SPT_Data"
        "${home}/spt-server/SPT_Runtime/user/cache"
        "${home}/spt-server/SPT_Runtime/user/logs"
        "${home}/spt-server/SPT_Runtime/*.dll"
      ];
      # Only the prune takes an exclusive lock; bounds the CouchDB downtime if they overlap.
      retryLock = "10m";
      backupPrepareCommand = "${prepare}";
      backupCleanupCommand = "${cleanup}";
    };

    systemd.services.restic-prune = {
      description = "restic forget --prune of ${repository}";
      after = [ "restic-backups-default.service" ];
      unitConfig.RequiresMountsFor = [ "/mnt/backup" ];
      environment = {
        RESTIC_REPOSITORY = repository;
        RESTIC_PASSWORD_FILE = passwordFile;
        RESTIC_CACHE_DIR = "/var/cache/restic-prune";
      };
      serviceConfig = {
        Type = "oneshot";
        CacheDirectory = "restic-prune";
        ExecStart = "${pkgs.restic}/bin/restic forget --prune --retry-lock 2h ${lib.concatStringsSep " " retention}";
      };
    };
    systemd.timers.restic-prune = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun 05:30";
        Persistent = true;
      };
    };
  };
}
