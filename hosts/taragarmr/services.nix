# The watermarks-remover plugin backend (127.0.0.1:8765), another user service of the old host.
# It runs lingering, like the SPT units (spt.nix), and so does the teamclaude proxy every host
# gets from modules/home/common/teamclaude.nix.
{ config, pkgs, ... }:
let
  # The plugin cache holds one directory per installed version; run the newest, so a plugin
  # update (which adds a version directory) needs no change here.
  watermarksRemover = pkgs.writeShellScript "watermarks-remover" ''
    set -u
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.coreutils
        pkgs.findutils
      ]
    }
    base="$HOME/.claude/plugins/cache/watermarks-remover/watermarks-remover"
    version=$(find "$base" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V | tail -n 1)
    if [ -z "$version" ]; then
      echo "watermarks-remover: no installed plugin version under $base" >&2
      exit 1
    fi
    server="$base/$version/service/scripts/server.py"
    if [ ! -f "$server" ]; then
      echo "watermarks-remover: $server not found (newest version dir: $version)" >&2
      exit 1
    fi
    echo "watermarks-remover: starting $version"
    exec ${pkgs.python3}/bin/python3 "$server" --host 127.0.0.1 --port 8765
  '';
in
{
  home-manager.users.${config.krane.user.name} = {
    # Runs the python service out of the Claude Code plugin cache (restored with ~/.claude),
    # newest installed version; it does not start until the plugin directory exists.
    systemd.user.services.watermarks-remover = {
      Unit = {
        Description = "watermarks-remover HTTP service (Claude Code plugin backend)";
        After = [ "network.target" ];
        ConditionPathExists = "%h/.claude/plugins/cache/watermarks-remover/watermarks-remover";
      };
      Service = {
        ExecStart = "${watermarksRemover}";
        Restart = "on-failure";
        RestartSec = 3;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
