# The other two user services of the old host: the teamclaude proxy (127.0.0.1:3456), the
# desktops' module imported on its own (it has no desktop dependency; the rest of
# modules/home/desktop stays out of a server), and the watermarks-remover plugin backend (127.0.0.1:8765).
# Both run lingering, like the SPT units (spt.nix).
{ config, pkgs, ... }:
{
  home-manager.users.${config.krane.user.name} = {
    imports = [ ../../modules/home/desktop/teamclaude.nix ];

    # Runs the python service out of the Claude Code plugin cache (restored with ~/.claude);
    # it does not start until that path exists.
    systemd.user.services.watermarks-remover = {
      Unit = {
        Description = "watermarks-remover HTTP service (Claude Code plugin backend)";
        After = [ "network.target" ];
        ConditionPathExists = "%h/.claude/plugins/cache/watermarks-remover/watermarks-remover/0.5.0/service/scripts/server.py";
      };
      Service = {
        ExecStart = "${pkgs.python3}/bin/python3 %h/.claude/plugins/cache/watermarks-remover/watermarks-remover/0.5.0/service/scripts/server.py --host 127.0.0.1 --port 8765";
        Restart = "on-failure";
        RestartSec = 3;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
