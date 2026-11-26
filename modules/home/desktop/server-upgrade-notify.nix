# Desktop notification for every message on the server upgrade ntfy topic: `ntfy subscribe` over
# the WireGuard tunnel, one notify-send per message. Inactive until the host's secrets have
# ntfy/read-token (modules/nixos/desktop/server-upgrade-notify.nix). Messages sent while the
# desktop is off or the tunnel is down are not replayed.
{
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  ntfy = import ../../../lib/ntfy.nix;
  tokenSecret = "ntfy/read-token";

  subscribe = pkgs.writeShellScript "server-upgrade-subscribe" ''
    NTFY_TOKEN="$(< ${osConfig.sops.secrets.${tokenSecret}.path})"
    if [ -z "$NTFY_TOKEN" ]; then
      echo "server-upgrade-notify: ${tokenSecret} is empty or unreadable" >&2
      exit 1
    fi
    export NTFY_TOKEN
    # ntfy runs the command through sh with the message in NTFY_* variables; priority 4+ (high,
    # urgent) is a failure.
    exec ${lib.getExe pkgs.ntfy-sh} subscribe ${ntfy.url}/${ntfy.topic} \
      '[ "$NTFY_PRIORITY" -ge 4 ] && urgency=critical || urgency=normal
       ${lib.getExe' pkgs.coreutils "env"} -u NTFY_TOKEN ${lib.getExe pkgs.libnotify} -a Servers -u "$urgency" -- "''${NTFY_TITLE:-Server upgrade}" "$NTFY_MESSAGE"'
  '';
in
{
  config = lib.mkIf (osConfig.sops.secrets ? ${tokenSecret}) {
    systemd.user.services.server-upgrade-notify = {
      Unit = {
        Description = "Desktop notifications for server upgrade failures";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
        StartLimitIntervalSec = 0;
      };
      Service = {
        ExecStart = "${subscribe}";
        # Reconnect with a growing delay (30s up to 10min); reconnecting replays nothing.
        Restart = "always";
        RestartSec = "30s";
        RestartSteps = 5;
        RestartMaxDelaySec = "10min";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
