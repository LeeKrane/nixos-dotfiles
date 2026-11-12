# Per-host keyboard layout/variant. Read by locale.nix (xkb, and via
# console.useXkbConfig the TTY/tuigreet keymap) and by display.nix
# (home-manager, via osConfig) for Hyprland's kb_layout/kb_variant. Defaults
# match the three original hosts' literal display.nix values. install.sh's
# new-host flow writes a `krane.keyboard` block into hosts/<name>/default.nix.
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.krane.keyboard = {
    layout = mkOption {
      type = types.str;
      default = "at";
      description = "xkb keyboard layout: services.xserver.xkb.layout, the TTY keymap and Hyprland's kb_layout.";
    };
    variant = mkOption {
      type = types.str;
      default = "nodeadkeys";
      description = "xkb keyboard variant: services.xserver.xkb.variant and Hyprland's kb_variant. May be empty.";
    };
  };
}
