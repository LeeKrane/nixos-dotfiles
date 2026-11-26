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
