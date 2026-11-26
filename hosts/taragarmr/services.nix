# The watermarks-remover plugin backend (127.0.0.1:8765), a lingering user service.
{ config, pkgs, ... }:
let
  # The plugin cache holds one directory per version; run the newest.
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
