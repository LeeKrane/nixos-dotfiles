# Autologin gives PAM no password, so the session must lock itself. pidof only proves the qs
# process exists; ii's Lock IpcHandler appears seconds later (LazyLoader gated on Config.ready).
# Wait for it, call it directly (a hypridle/global-shortcut hop drops silently when the target is
# not registered), and fail closed to hyprlock.
{ config, pkgs, ... }:
let
  lockOnStart = pkgs.writeShellScript "krane-lock-on-start" ''
    qs=${config.home.profileDirectory}/bin/qs
    ready() { "$qs" -c ii ipc show 2>/dev/null | ${pkgs.gnugrep}/bin/grep -qx 'target lock'; }
    for _ in $(${pkgs.coreutils}/bin/seq 1 300); do
      ready && break
      ${pkgs.coreutils}/bin/sleep 0.2
    done
    if ready; then
      ${pkgs.systemd}/bin/loginctl lock-session
      "$qs" -c ii ipc call lock activate
    else
      echo "krane-lock-on-start: ii lock IPC never appeared, falling back to hyprlock" >&2
      ${pkgs.procps}/bin/pidof hyprlock >/dev/null 2>&1 || ${config.home.profileDirectory}/bin/hyprlock
    fi
  '';
in
{
  krane.hypr.execOnce = [ "${lockOnStart}" ];
}
