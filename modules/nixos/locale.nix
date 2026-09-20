# Time zone, locale and keyboard layout.
{ ... }:
{
  time.timeZone = "Europe/Vienna";

  # Austrian formats, English UI strings.
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_AT.UTF-8";
    LC_IDENTIFICATION = "de_AT.UTF-8";
    LC_MEASUREMENT = "de_AT.UTF-8";
    LC_MONETARY = "de_AT.UTF-8";
    LC_NAME = "de_AT.UTF-8";
    LC_NUMERIC = "de_AT.UTF-8";
    LC_PAPER = "de_AT.UTF-8";
    LC_TELEPHONE = "de_AT.UTF-8";
    LC_TIME = "de_AT.UTF-8";
  };

  # NixOS derives the TTY keymap from the xkb settings below; kbd ships no at-* console maps.
  console.useXkbConfig = true;
  console.font = "eurlatgr";

  # Hyprland reads this even without an X server.
  services.xserver.xkb = {
    layout = "at";
    variant = "nodeadkeys";
  };
}
