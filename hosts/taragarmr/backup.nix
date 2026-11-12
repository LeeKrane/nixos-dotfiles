# restic backup to taronychus' append-only REST server over wg0 (modules/nixos/server/backup.nix).
# The server prunes itself, so the client sends no forget/prune (pruneOpts = [ ]).
#
# What goes in:
#   /srv/couchdb               Obsidian LiveSync data. A running CouchDB writes its append-only
#                              files continuously, so the job stops the container for the run
#                              and starts it again afterwards (also after a failed backup, as
#                              cleanup is ExecStopPost). Downtime: the length of the run, a
#                              minute or so after the first one; sync clients retry.
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
      backupPrepareCommand = "${prepare}";
      backupCleanupCommand = "${cleanup}";
    };
  };
}
