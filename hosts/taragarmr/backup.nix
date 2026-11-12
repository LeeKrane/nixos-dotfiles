# restic backup to taronychus' append-only REST server over wg0 (modules/nixos/server/backup.nix).
# The server prunes itself, so the client sends no forget/prune (pruneOpts = [ ]).
#
# What goes in:
#   /srv/couchdb               Obsidian LiveSync data. A running CouchDB writes its append-only
#                              files continuously, so the job stops the container for the run
#                              and starts it again afterwards (also after a failed backup, as
#                              cleanup is ExecStopPost). Downtime: the length of the run, a
#                              minute or so after the first one; sync clients retry. CouchDB is
#                              only stopped once the repository answers and holds no exclusive
#                              lock (waited for up to 10 minutes first), so a prune on
#                              taronychus or an unreachable wg0 does not take it down.
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
# password, init'ed on first run) and rest-env (RESTIC_REST_USERNAME=taragarmr,
# RESTIC_REST_PASSWORD=..., matching taronychus' restic/htpasswd). Without the section the
# job is off.
{
  config,
  lib,
  pkgs,
  hostName,
  ...
}:
let
  inherit (import ../../lib/wireguard.nix) wg0;
  hostSecrets = import ../../lib/host-secrets.nix { inherit lib hostName; };
  home = config.users.users.${config.krane.user.name}.home;
  stage = "/var/lib/krane-backup-stage";
  systemctl = "${config.systemd.package}/bin/systemctl";

  restic = "${pkgs.restic}/bin/restic";
  jq = "${pkgs.jq}/bin/jq";

  # Runs before CouchDB is stopped, in the backup unit (so RESTIC_REPOSITORY, the password file
  # and the REST credentials are in its environment). Waits, at most 10 minutes, until the
  # repository answers and holds no exclusive lock (the weekly server-side prune, Sun 01:00;
  # shared locks from the offsite copy or other backups do not block a backup), and fails
  # otherwise: with taronychus down or pruning, CouchDB (Obsidian sync) stays up.
  waitForRepo = pkgs.writeShellScript "taragarmr-backup-wait-for-repo" ''
    set -u
    deadline=$((SECONDS + 600))
    while true; do
      if ids=$(${restic} list locks --no-lock 2>/dev/null); then
        exclusive=0
        for id in $ids; do
          if ${restic} cat lock "$id" --no-lock 2>/dev/null | ${jq} -e '.exclusive == true' >/dev/null; then
            exclusive=1
          fi
        done
        [ "$exclusive" = 0 ] && exit 0
        reason="exclusive lock held"
      else
        reason="repository unreachable"
      fi
      if [ "$SECONDS" -ge "$deadline" ]; then
        echo "backup: $reason after 10 minutes, not stopping CouchDB" >&2
        exit 1
      fi
      ${pkgs.coreutils}/bin/sleep 15
    done
  '';

  prepare = pkgs.writeShellScript "taragarmr-backup-prepare" ''
    set -u
    ${waitForRepo} || exit 1
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
    sops.secrets = {
      "restic/rest-env" = {
        owner = "root";
        mode = "0400";
      };
      "restic/repo-password" = {
        owner = "root";
        mode = "0400";
      };
    };

    # The repository is on taronychus, reachable over wg0 only.
    systemd.services.restic-backups-default = {
      after = [ "wg-quick-wg0.service" ];
      wants = [ "wg-quick-wg0.service" ];
    };

    krane.backup = {
      enable = true;
      repository = "rest:http://taragarmr@${wg0.peers.taronychus.ip}:8000/taragarmr";
      passwordFile = config.sops.secrets."restic/repo-password".path;
      environmentFile = config.sops.secrets."restic/rest-env".path;
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
      # Waiting for the lock is the prepare command's job (above), so the backup itself only
      # needs a short retry: the CouchDB downtime stays bounded.
      retryLock = "10m";
      backupPrepareCommand = "${prepare}";
      backupCleanupCommand = "${cleanup}";
    };
  };
}
