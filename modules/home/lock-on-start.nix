# Autologin (modules/nixos/desktop.nix initial_session) gives no password to PAM, so the
# session must lock itself before anything is visible. pidof only proves the qs process
# exists; ii's Lock panel sits behind a LazyLoader gated on Config.ready, so its IpcHandler
# appears seconds later. Wait for the handler, call it directly (no hypridle / global-shortcut
# hop, which drops silently when the target is not registered), and fail closed to hyprlock.
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
