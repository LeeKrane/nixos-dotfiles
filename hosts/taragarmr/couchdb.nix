# CouchDB for Obsidian LiveSync (couch.krane.dev, proxied by caddy.nix).
# Secret couchdb/env: an env file with COUCHDB_USER, COUCHDB_PASSWORD and COUCHDB_SECRET. Without
# the `couchdb` section the container is not defined.
{
  config,
  lib,
  pkgs,
  hostName,
  ...
}:
let
  hostSecrets = import ../../lib/host-secrets.nix { inherit lib hostName; };
  etcDir = "/var/lib/couchdb-etc";
  ini = "${etcDir}/10-livesync.ini";
in
{
  config = lib.mkIf (hostSecrets.hasSection "couchdb") {
    sops.secrets."couchdb/env" = {
      owner = "root";
      mode = "0400";
    };

    systemd.tmpfiles.rules = [ "d /srv/couchdb 0750 5984 5984 -" ];

    virtualisation.oci-containers.containers.couchdb = {
      image = "couchdb:3.5.2";
      environmentFiles = [ config.sops.secrets."couchdb/env".path ];
      ports = [ "127.0.0.1:5984:5984" ];
      volumes = [
        "/srv/couchdb:/opt/couchdb/data"
        "${ini}:/opt/couchdb/etc/local.d/10-livesync.ini"
      ];
    };

    systemd.services.docker-couchdb.preStart = ''
      ${pkgs.coreutils}/bin/install -d -m 0755 ${etcDir}
      ${pkgs.coreutils}/bin/install -m 0644 -o 5984 -g 5984 ${./couchdb/livesync.ini} ${ini}
    '';
  };
}
