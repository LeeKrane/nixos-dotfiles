# CouchDB for Obsidian LiveSync (couch.krane.dev, proxied by caddy.nix), the container that
# replaces obsidian-sync's Docker build: same base image (couchdb:3.5.2), the same livesync.ini
# mounted over local.d instead of baked in. The old image's curl/jq only served its healthcheck
# and init/provision.sh; provision.sh is not needed because the databases and users come with
# the restored data. No healthcheck is defined: the base image is not known to ship curl.
#
# Restore the data once, before the first start (old host: docker volume
# ck7ixy7dnv0gn2drc5qjnwkz_couchdb-data, 240 MB):
#   sudo rsync -a /var/lib/docker/volumes/ck7ixy7dnv0gn2drc5qjnwkz_couchdb-data/_data/ <this host>:/srv/couchdb/
#   sudo chown -R 5984:5984 /srv/couchdb
#
# Secret couchdb/env (secrets/taragarmr.yaml, section `couchdb`), an env file with
#   COUCHDB_USER=admin
#   COUCHDB_PASSWORD=...
#   COUCHDB_SECRET=...
# Without the section the container is not defined, so the host evaluates before step 8.
{
  config,
  lib,
  hostName,
  ...
}:
let
  hostSecrets = import ../../lib/host-secrets.nix { inherit lib hostName; };
in
{
  config = lib.mkIf (hostSecrets.hasSection "couchdb") {
    sops.secrets."couchdb/env" = {
      owner = "root";
      mode = "0400";
    };

    # 5984 is the couchdb user's uid/gid inside the image.
    systemd.tmpfiles.rules = [ "d /srv/couchdb 0750 5984 5984 -" ];

    virtualisation.oci-containers.containers.couchdb = {
      image = "couchdb:3.5.2";
      environmentFiles = [ config.sops.secrets."couchdb/env".path ];
      # Loopback only: Caddy is the way in.
      ports = [ "127.0.0.1:5984:5984" ];
      volumes = [
        "/srv/couchdb:/opt/couchdb/data"
        "${./couchdb/livesync.ini}:/opt/couchdb/etc/local.d/10-livesync.ini:ro"
      ];
    };
  };
}
