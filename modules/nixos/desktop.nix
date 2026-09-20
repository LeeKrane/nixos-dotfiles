# Hyprland session, greetd/tuigreet and portal/keyring/polkit plumbing.
# i2c/ydotool/udisks2/rtkit live in peripherals.nix/audio.nix, not here.
#
# ii (illogical-impulse) owns ~/.config/hypr entirely. Never add
# home-manager's own Hyprland module. Configure only via `programs.hyprland`.
{ config, pkgs, ... }:
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
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-session --sessions /run/current-system/sw/share/wayland-sessions";
        # Explicit: this session runs as the unprivileged greeter user, security-relevant.
        user = "greeter";
      };

      # Boot straight into krane's plain (non-UWSM) Hyprland session; the session locks
      # itself at start (modules/home/lock-on-start.nix), so the ii lock screen is the
      # first screen. tuigreet stays as default_session for logout. The disk is not
      # encrypted, so this trades the greeter's password gate for the lock screen's. See
      # docs/INSTALL.md. This is the same command tuigreet's "Hyprland" .desktop entry
      # runs, not the "Hyprland (UWSM)" one.
      initial_session = {
        command = "${config.programs.hyprland.package}/bin/start-hyprland";
        user = "krane";
      };
    };

    # The NixOS greetd module defaults `restart` to false whenever `initial_session` is
    # set, on the pre-0.9 assumption that a greetd restart re-triggers autologin. greetd
    # 0.10.3's /run/greetd.run runfile already gates autologin to once per boot, so a
    # restart is safe here and desirable: it recovers a crashed greetd back into the
    # locked session instead of stranding the machine. `systemctl restart greetd` yields
    # tuigreet, not another autologin (see docs/II-INTEGRATION.md "Rollback and escape
    # hatches").
    restart = true;
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
