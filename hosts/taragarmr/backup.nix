# restic backup to a local repository on the external drive mounted at /mnt/backup
# (backup-drive.nix; modules/nixos/server/backup.nix). The repository is created on the first
# run. Pruning is a separate weekly unit (restic-prune, below), so the nightly CouchDB stop only
# lasts as long as the backup itself.
#
# What goes in:
#   /srv/couchdb               Obsidian LiveSync data. A running CouchDB writes its append-only
#                              files continuously, so the job stops the container for the run
#                              and starts it again afterwards (also after a failed backup, as
#                              cleanup is ExecStopPost). Downtime: the length of the run, a
#                              minute or so after the first one; sync clients retry. With the
#                              drive missing the unit fails on RequiresMountsFor before the
#                              prepare command runs, so CouchDB is never stopped for nothing.
#   /srv/gymleague/dumps       the nightly pg_dump of gym-league (02:30, gymleague.nix); only
#                              while gym-league is enabled (its secrets section exists).
#   /home/krane/spt-server     profiles, mods and their configs (SPT_Runtime/user), the profile
#                              archives in backups/, web-admin-credentials.txt, the scripts. The
#                              reproducible server runtime and download cache are excluded.
#   /var/lib/krane-backup-stage  small files copied in before each run: the headless clients'
#                              HeadlessConfig.json and scripts (the 73 GB game/pfx trees are
#                              reproducible and stay out) and teamclaude's config. Copies are
#                              best effort, so a file that does not exist yet fails nothing.
# Not backed up: /var/lib/caddy (certificates reissue), docker images, ~/.claude.
#
# Secrets (secrets/taragarmr.yaml, section `restic`): repo-password (the repository's
# password). Without the section the job is off.
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

    # The repository is on the external drive: do not run without it mounted.
    systemd.services.restic-backups-default.unitConfig.RequiresMountsFor = [ "/mnt/backup" ];

    krane.backup = {
      enable = true;
      inherit repository passwordFile;
      # restic-prune below does it, outside the CouchDB downtime.
      pruneOpts = [ ];
      paths = [
        "/srv/couchdb"
        "${home}/spt-server"
        stage
      ]
      # restic exits non-zero on a missing path; the dumps dir only exists with gym-league on.
      ++ lib.optional (hostSecrets.hasSection "gymleague") "/srv/gymleague/dumps";
      exclude = [
        "${home}/spt-server/_download"
        "${home}/spt-server/smoketest.*"
        "${home}/spt-server/SPT_Runtime/SPT_Data"
        "${home}/spt-server/SPT_Runtime/user/cache"
        "${home}/spt-server/SPT_Runtime/user/logs"
        "${home}/spt-server/SPT_Runtime/*.dll"
      ];
      # Only the weekly prune takes an exclusive lock; keep the wait (and so the CouchDB
      # downtime) bounded if the two ever overlap.
      retryLock = "10m";
      backupPrepareCommand = "${prepare}";
      backupCleanupCommand = "${cleanup}";
    };

    # Weekly forget + prune with the primary retention, CouchDB untouched.
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
