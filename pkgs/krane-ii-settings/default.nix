# krane-ii-settings: the only writer of hosts/<host>/ii-settings.json, used by the ii settings
# GUI's persistent controls and by modules/home/ii-settings.nix to render krane_gui.lua at
# build time. Standard library only; tool paths are baked in here.
# See docs/II-INTEGRATION.md "Settings persistence".
{
  lib,
  writers,
  hyprland,
  hypridle,
  systemd,
  procps,
  util-linux,
}:
let
  source =
    builtins.replaceStrings
      [
        "@hyprctl@"
        "@systemdRun@"
        "@systemctl@"
        "@pkill@"
        "@pidof@"
        "@setsid@"
        "@hypridle@"
        "@schema@"
      ]
      [
        (lib.getExe' hyprland "hyprctl")
        (lib.getExe' systemd "systemd-run")
        (lib.getExe' systemd "systemctl")
        (lib.getExe' procps "pkill")
        (lib.getExe' procps "pidof")
        (lib.getExe' util-linux "setsid")
        (lib.getExe' hypridle "hypridle")
        "${./schema.json}"
      ]
      (builtins.readFile ./krane_ii_settings.py);
in
writers.writePython3Bin "krane-ii-settings" {
  # Long lines are tables and messages; W503 conflicts with the house style.
  flakeIgnore = [
    "E501"
    "W503"
  ];
} source
