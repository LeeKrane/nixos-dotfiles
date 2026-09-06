# Hyprland session, greetd/tuigreet and portal/keyring/polkit plumbing.
# i2c/ydotool/udisks2/rtkit live in peripherals.nix/audio.nix, not here.
#
# ii (illogical-impulse) owns ~/.config/hypr entirely. Never add
# home-manager's own Hyprland module. Configure only via `programs.hyprland`.
{ pkgs, ... }:
{
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };

  services.greetd = {
    enable = true;
    # tuigreet: text-based greeter, adjusted so boot messages don't interrupt it.
    useTextGreeter = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-session --sessions /run/current-system/sw/share/wayland-sessions";
      # Explicit: this session runs as the unprivileged greeter user, security-relevant.
      user = "greeter";
    };
  };

  security.pam.services.greetd.enableGnomeKeyring = true;
  services.gnome.gnome-keyring.enable = true;

  # hyprlock/hypridle come from the soymou module, not `programs.hyprlock`,
  # which registers no PAM service. Without this, every unlock fails.
  security.pam.services.hyprlock = { };

  programs.dconf.enable = true;
  services.upower.enable = true;
  services.geoclue2.enable = true;

  security.polkit.enable = true;

  services.gvfs.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.kdePackages.xdg-desktop-portal-kde
    ];
    # Pins the default portal to hyprland, falling back to gtk. kde stays
    # registered for apps that need it by name.
    config.common.default = [
      "hyprland"
      "gtk"
    ];
  };

  # Common to every host, not per GPU module: the ii power widget needs it everywhere.
  services.power-profiles-daemon.enable = true;

  # Set once here, not duplicated per GPU module.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
