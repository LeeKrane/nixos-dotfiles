# teamclaude proxy as a systemd --user service, replacing `teamclaude service install`, whose unit
# would pin the node and store path current at install time. Claude Code reaches it through the
# fish `claude` function or ANTHROPIC_BASE_URL (modules/nixos/common/claude.nix).
# Seat tokens live in ~/.config/teamclaude.json (live state, written by `teamclaude login`).
{ pkgs, ... }:
{
  systemd.user.services.teamclaude = {
    Unit = {
      Description = "TeamClaude multi-account Claude proxy";
      Documentation = [ "https://github.com/KarpelesLab/teamclaude" ];
    };
    # No network ordering: network-online.target does not exist in the user manager.
    # Restart=always covers a failed start.
    # default.target, not graphical-session.target: claude also runs from TTYs and SSH.
    Install.WantedBy = [ "default.target" ];
    Service = {
      ExecStart = "${pkgs.teamclaude}/bin/teamclaude server --headless";
      Restart = "always";
      RestartSec = 5;
    };
  };

  home.packages = [ pkgs.teamclaude ];
}
