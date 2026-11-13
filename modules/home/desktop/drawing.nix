# Live screen annotation with wayscriber. It draws on wlr-layer-shell surfaces rather than a
# window, so Hyprland's SUPER+drag cannot move it and nothing is left on screen when it is
# toggled off. (gromit-mpx was tried first: under XWayland it is a regular floating window
# that SUPER+drag moves, and its strokes stay visible after toggling off.)
#
# The daemon starts hidden at login. SUPER+Y toggles the overlay, and starts the daemon first
# if it is not running (first use after a rebuild without a re-login, or after a crash).
# Undo, clear and tool keys are wayscriber's own, shown in its in-overlay help.
{ pkgs, ... }:
let
  wayscriber = "${pkgs.wayscriber}/bin/wayscriber";
  daemon = "${wayscriber} --daemon --no-resume-session --no-tray";
  toggle = pkgs.writeShellScript "wayscriber-toggle" ''
    if ! ${pkgs.procps}/bin/pgrep -x wayscriber >/dev/null; then
      ${pkgs.util-linux}/bin/setsid -f ${daemon} >/dev/null 2>&1
      for _ in $(seq 20); do
        ${pkgs.procps}/bin/pgrep -x wayscriber >/dev/null && break
        sleep 0.1
      done
      sleep 0.5
    fi
    exec ${wayscriber} --daemon-toggle
  '';
in
{
  home.packages = [ pkgs.wayscriber ];

  krane.hypr.execOnce = [ daemon ];

  krane.hypr.binds = [
    {
      keys = "SUPER + Y";
      action = ''hl.dsp.exec_cmd("${toggle}")'';
      description = "Drawing: Toggle draw on screen";
    }
  ];
}
