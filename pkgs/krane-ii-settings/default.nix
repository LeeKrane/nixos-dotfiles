# Writer of hosts/<host>/ii-settings.json. See docs/II-INTEGRATION.md "Settings persistence".
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
  flakeIgnore = [
    "E501"
    "W503"
  ];
} source
