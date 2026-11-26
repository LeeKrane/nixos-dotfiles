# wayscriber draws on wlr-layer-shell surfaces, not a window, so SUPER+drag cannot move it and
# nothing stays on screen when toggled off. The daemon starts hidden at login; SUPER+Y toggles
# the overlay, starting the daemon first if it is not running.
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
