# teamclaude proxy as a systemd --user service, replacing `teamclaude service install`, which
# would write a unit pointing at whatever node and store path were current at install time.
# ~/.claude/settings.json sets ANTHROPIC_BASE_URL=http://localhost:3456, so Claude Code cannot
# connect until this runs. Seat tokens live in ~/.config/teamclaude.json, written by
# `teamclaude login` and refreshed by the proxy itself: live state, never declared here.
{ pkgs, ... }:
{
  systemd.user.services.teamclaude = {
    Unit = {
      Description = "TeamClaude multi-account Claude proxy";
      Documentation = [ "https://github.com/KarpelesLab/teamclaude" ];
      After = [ "network-online.target" ];
    };
    # default.target, not graphical-session.target: claude also runs from TTYs and SSH. No
    # linger, so the proxy stops with the last session, same as upstream's own unit.
    Install.WantedBy = [ "default.target" ];
    Service = {
      ExecStart = "${pkgs.teamclaude}/bin/teamclaude server --headless";
      Restart = "always";
      RestartSec = 5;
    };
  };

  home.packages = [ pkgs.teamclaude ];
}
