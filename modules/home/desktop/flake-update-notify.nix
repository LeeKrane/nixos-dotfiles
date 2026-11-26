# Desktop notification when the weekly update workflow (.github/workflows/update.yml) has an open
# update pull request (one unit per lane: servers, desktops), once per pushed head commit. The
# repo is public, so the script needs no GitHub login.
{ lib, pkgs, ... }:
let
  repo = "LeeKrane/nixos-dotfiles";
  lanes = {
    servers = "Server update";
    desktops = "Desktop update";
  };
in
{
  systemd.user.services = lib.mapAttrs' (
    lane: label:
    lib.nameValuePair "flake-update-notify-${lane}" {
      Unit = {
        Description = "Notify about a pending ${lib.toLower label} pull request";
        # notify-send and xdg-open need the session. Requisite fails the start outside one instead
        # of pulling one up; recovery is OnActiveSec=1min after the next login or the next daily
        # trigger (no lingering). Restart does not cover this: the job fails, not the service.
        Requisite = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
        # Caps the retries below: 5 starts per 30 minutes.
        StartLimitIntervalSec = "30min";
        StartLimitBurst = 5;
      };
      Service = {
        Type = "oneshot";
        # oneshot has no start timeout and --wait has no upper bound, so a never-closed
        # notification would block the unit and swallow later triggers. State is written before
        # notifying, so a timeout kill does not repeat the notification.
        TimeoutStartSec = "12h";
        # A start soon after login can run before the network or notification daemon is up; the
        # script then exits non-zero and Restart retries. State is written only once the daemon
        # probe succeeds. A quick notify-send failure removes state and exits 1 (retried); a
        # failure after a delay keeps state and exits 0, so a popup is not shown twice.
        Restart = "on-failure";
        RestartSec = "2min";
        Environment = [
          "REPO=${repo}"
          "BRANCH=ci/flake-update-${lane}"
          "LABEL=${label}"
        ];
        ExecStart = "${pkgs.flake-update-notify}/bin/flake-update-notify";
      };
    }
  ) lanes;

  systemd.user.timers = lib.mapAttrs' (
    lane: label:
    lib.nameValuePair "flake-update-notify-${lane}" {
      Unit.Description = "Daily check for a pending ${lib.toLower label} pull request";
      # Bound to the session like the service's Requisite, not timers.target: stops at logout,
      # and OnActiveSec re-arms at the next login.
      Unit.PartOf = [ "graphical-session.target" ];
      Timer = {
        OnCalendar = "daily";
        OnActiveSec = "1min";
        Persistent = true;
      };
      # Enabled via graphical-session.target.wants/ (same as proton-drive.nix), so the timer starts
      # when the session target does (session-target.nix: hyprland-session.target BindsTo it).
      Install.WantedBy = [ "graphical-session.target" ];
    }
  ) lanes;
}
