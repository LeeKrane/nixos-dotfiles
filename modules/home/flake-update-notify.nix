# Desktop notification when the weekly update workflow (.github/workflows/update.yml) has an
# update pull request open, once per pushed head commit. The repo is public, so the script
# needs no GitHub login. See docs/superpowers/specs/2026-10-06-flake-update-notify-design.md.
{ pkgs, ... }:
let
  repo = "LeeKrane/nixos-dotfiles";
in
{
  systemd.user.services.flake-update-notify = {
    Unit = {
      Description = "Notify about a pending flake update pull request";
      # notify-send and xdg-open need the session. Requisite fails the start outside one,
      # instead of pulling a session up; recovery is OnStartupSec=5min after the next
      # login, or the next daily trigger (no lingering, so there's no catch-up before
      # then).
      Requisite = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      # oneshot has no start timeout by default, and --wait has no upper bound, so a
      # never-closed notification would otherwise block this unit (and swallow later
      # timer triggers) indefinitely. State is already written before notifying, so a
      # timeout kill here does not cause a repeat notification.
      TimeoutStartSec = "12h";
      Environment = [
        "REPO=${repo}"
        "BRANCH=ci/flake-update"
      ];
      ExecStart = "${pkgs.flake-update-notify}/bin/flake-update-notify";
    };
  };

  systemd.user.timers.flake-update-notify = {
    Unit.Description = "Daily check for a pending flake update pull request";
    Timer = {
      OnCalendar = "daily";
      OnStartupSec = "5min";
      Persistent = true;
      RandomizedDelaySec = "15min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
