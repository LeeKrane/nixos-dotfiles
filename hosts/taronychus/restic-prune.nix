# Server-side pruning of the repositories under /srv/restic. The clients (krane.backup) talk to
# an append-only REST server and so cannot delete snapshots; they run with pruneOpts = [ ],
# which makes the module skip `restic forget`. Retention is applied here instead, directly on
# the repository files, where the REST server's append-only flag does not apply.
#
# Each repository's password sits on this host, which is inherent to server-side pruning:
# restic/repo-password-taragarmr, and restic/repo-password for taronychus' own repository (the
# password backup.nix's self-backup uses). The service runs as the `restic` user so the files
# keep the ownership the REST server expects.
#
# Schedule: Sunday 01:00 (+ up to 15 min), clear of the 02:30 gym-league dump, the 03:30
# self-backup, taragarmr's 04:00(+30 min) backup and tarritator's 06:00 copy. The jobs that
# still collide with a long prune wait on the repository lock (--retry-lock).
{
  config,
  lib,
  pkgs,
  hostName,
  ...
}:
let
  hostSecrets = import ../../lib/host-secrets.nix { inherit lib hostName; };
  hasRestic = hostSecrets.hasSection "restic";

  # Repository names under krane.backupServer.dataDir, one per client host.
  repos = [
    "taragarmr"
    "taronychus"
  ];

  dataDir = config.krane.backupServer.dataDir;
  secretName = repo: if repo == "taronychus" then "restic/repo-password" else "restic/repo-password-${repo}";
  passwordFile = repo: config.sops.secrets.${secretName repo}.path;
  retention = lib.concatStringsSep " " (import ../../lib/backup-retention.nix).primary;

  prune = pkgs.writeShellScript "restic-prune" ''
    set -u
    rc=0
    ${lib.concatMapStringsSep "\n" (repo: ''
      if [ -e "${dataDir}/${repo}/config" ]; then
        echo "== ${repo}"
        ${lib.getExe pkgs.restic} forget --prune \
          --repo "${dataDir}/${repo}" \
          --password-file "${passwordFile repo}" \
          --retry-lock 2h ${retention} || rc=1
      else
        echo "== ${repo}: not initialised yet, skipped"
      fi
    '') repos}
    exit $rc
  '';
in
{
  sops.secrets = lib.mkIf hasRestic (
    lib.genAttrs (map secretName repos) (_: {
      owner = "restic";
      mode = "0400";
    })
  );

  systemd.services.restic-prune = lib.mkIf hasRestic {
    description = "restic forget --prune on the local repositories";
    serviceConfig = {
      Type = "oneshot";
      User = "restic";
      Group = "restic";
      ExecStart = prune;
      CacheDirectory = "restic-prune";
      Environment = "RESTIC_CACHE_DIR=/var/cache/restic-prune";
      ReadWritePaths = [ dataDir ];
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
  systemd.timers.restic-prune = lib.mkIf hasRestic {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 01:00";
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
  };
}
