# ani-cli with its watch history synced across devices through the `ani-cli` database on the
# Obsidian LiveSync CouchDB (couch.krane.dev, hosts/taragarmr/couchdb.nix). The wrapper
# (scripts/ani-cli-sync.sh) pulls and merges ani-hsts before every run and pushes it after.
# A separate database, not the LiveSync one: LiveSync stores files chunked and encrypted, and
# only syncs while Obsidian runs.
#
# Credentials come from the `ani-cli/curl-auth` secret (secrets/README.md). Without that
# section in secrets/<host>.yaml this installs plain ani-cli.
#
# One-time server setup, as the CouchDB admin (secret couchdb/env on taragarmr):
#   c=https://couch.krane.dev; a=admin:<admin password>
#   curl -u "$a" -X PUT "$c/ani-cli"
#   curl -u "$a" -X PUT "$c/_users/org.couchdb.user:ani-cli" -H 'Content-Type: application/json' \
#     -d '{"name":"ani-cli","password":"<password>","roles":[],"type":"user"}'
#   curl -u "$a" -X PUT "$c/ani-cli/_security" -H 'Content-Type: application/json' \
#     -d '{"admins":{"names":[],"roles":[]},"members":{"names":["ani-cli"],"roles":[]}}'
# Then on each desktop host, from the repo root:
#   sops set secrets/<host>.yaml '["ani-cli"]["curl-auth"]' '"user = \"ani-cli:<password>\""'
{
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  hasAuth = osConfig.sops.secrets ? "ani-cli/curl-auth";

  wrapper = pkgs.writeShellApplication {
    name = "ani-cli";
    runtimeInputs = with pkgs; [
      curl
      jq
      gawk
      coreutils
      diffutils
    ];
    text = ''
      ANI_CLI_REAL=${lib.getExe pkgs.ani-cli}
      ANI_SYNC_AUTH=${osConfig.sops.secrets."ani-cli/curl-auth".path}
    ''
    + builtins.readFile ../../../scripts/ani-cli-sync.sh;
  };

  # Earlier paths win in symlinkJoin: the wrapper's bin/ani-cli shadows the real one, the man
  # page and anything else come from ani-cli itself.
  synced = pkgs.symlinkJoin {
    name = "ani-cli-synced";
    paths = [
      wrapper
      pkgs.ani-cli
    ];
  };
in
{
  home.packages = [ (if hasAuth then synced else pkgs.ani-cli) ];
}
