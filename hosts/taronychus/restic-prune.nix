# Server-side pruning of the repositories under /srv/restic. The clients (krane.backup) talk to
# an append-only REST server and so cannot delete snapshots; they run with pruneOpts = [ ],
# which makes the module skip `restic forget`. Retention is applied here instead, directly on
# the repository files, where the REST server's append-only flag does not apply.
#
# Each repository's password sits on this host (sops secret restic/repo-password-<repo>),
# which is inherent to server-side pruning. The service runs as the `restic` user so the files
# keep the ownership the REST server expects.
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
  repos = [ "taragarmr" ];

  dataDir = config.krane.backupServer.dataDir;
  passwordFile = repo: config.sops.secrets."restic/repo-password-${repo}".path;

  prune = pkgs.writeShellScript "restic-prune" ''
    set -u
    rc=0
    ${lib.concatMapStringsSep "\n" (repo: ''
      if [ -e "${dataDir}/${repo}/config" ]; then
        echo "== ${repo}"
        ${lib.getExe pkgs.restic} forget --prune \
          --repo "${dataDir}/${repo}" \
          --password-file "${passwordFile repo}" \
          --keep-daily 7 --keep-weekly 4 --keep-monthly 6 || rc=1
      else
        echo "== ${repo}: not initialised yet, skipped"
      fi
    '') repos}
    exit $rc
  '';
in
{
  sops.secrets = lib.mkIf hasRestic (
    lib.genAttrs (map (r: "restic/repo-password-${r}") repos) (_: {
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
      OnCalendar = "Sun 03:00";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
