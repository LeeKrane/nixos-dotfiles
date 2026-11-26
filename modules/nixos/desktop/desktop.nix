{ config, pkgs, ... }:
{
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };

  services.greetd = {
    enable = true;
    useTextGreeter = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-session --sessions /run/current-system/sw/share/wayland-sessions";
        user = "greeter";
      };

      # Autologin into plain (non-UWSM) Hyprland, which locks itself at start
      # (modules/home/desktop/lock-on-start.nix). The disk is unencrypted, so the lock screen
      # replaces the greeter's password gate. See docs/INSTALL.md.
      initial_session = {
        command = "${config.programs.hyprland.package}/bin/start-hyprland";
        user = config.krane.user.name;
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

  # hyprlock/hypridle come from the soymou module, which registers no PAM service;
  # without this every unlock fails.
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
    # kde stays registered for apps that need it by name.
    config.common.default = [
      "hyprland"
      "gtk"
    ];
  };

  services.power-profiles-daemon.enable = true;

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
