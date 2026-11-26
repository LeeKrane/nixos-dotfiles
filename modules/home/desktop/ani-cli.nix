# ani-cli with watch history synced through the `ani-cli` CouchDB database
# (hosts/taragarmr/couchdb.nix). Separate from the LiveSync database, which stores files
# chunked and encrypted and only syncs while Obsidian runs.
# Without the `ani-cli/curl-auth` secret (secrets/README.md) this installs plain ani-cli.
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

  # Earlier paths win: the wrapper's bin/ani-cli shadows the real one.
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
