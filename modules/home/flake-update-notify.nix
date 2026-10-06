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
      # instead of pulling a session up; recovery is OnActiveSec=1min after the next
      # login, or the next daily trigger (no lingering, so there's no catch-up before
      # then). Restart does not cover this case: the job fails, not the service.
      Requisite = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
      # Caps the retries below: 5 starts per 30 minutes, then the unit waits for the next
      # timer trigger.
      StartLimitIntervalSec = "30min";
      StartLimitBurst = 5;
    };
    Service = {
      Type = "oneshot";
      # oneshot has no start timeout by default, and --wait has no upper bound, so a
      # never-closed notification would otherwise block this unit (and swallow later
      # timer triggers) indefinitely. State is already written before notifying, so a
      # timeout kill here does not cause a repeat notification.
      TimeoutStartSec = "12h";
      # A start soon after login can run before the network or the notification daemon
      # is up: curl, or the script's own notification-daemon probe, then fails and
      # exits non-zero, retried here instead of waiting for the next daily trigger.
      # State is written only once that probe succeeds, so a retry never re-shows an
      # already-displayed popup. Past that point, the script times notify-send itself:
      # a quick failure (no popup ever rendered) removes state and exits 1, so this
      # still retries it; a failure after a delay (a popup was likely shown) keeps
      # state and exits 0 instead, so a retry can't show that popup twice.
      Restart = "on-failure";
      RestartSec = "2min";
      Environment = [
        "REPO=${repo}"
        "BRANCH=ci/flake-update"
      ];
      ExecStart = "${pkgs.flake-update-notify}/bin/flake-update-notify";
    };
  };

  systemd.user.timers.flake-update-notify = {
    Unit.Description = "Daily check for a pending flake update pull request";
    # Bound to the session like the service's Requisite above, not timers.target: stops
    # at logout instead of lingering, and OnActiveSec below re-arms fresh at the next
    # login instead of counting from whatever instant systemd --user itself started.
    Unit.PartOf = [ "graphical-session.target" ];
    Timer = {
      OnCalendar = "daily";
      OnActiveSec = "1min";
      Persistent = true;
    };
    # Enables by symlinking into graphical-session.target.wants/ (same pattern as
    # proton-drive.nix's service), so the timer starts -- and OnActiveSec begins
    # counting -- when the session's graphical-session.target does
    # (modules/home/session-target.nix: hyprland-session.target BindsTo it).
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
