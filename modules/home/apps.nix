# GUI applications from the machine inventory. flameshot is absent: ii ships hyprshot instead,
# already wired into its keybinds.
# Out of scope, never add here or elsewhere in this repo: all JetBrains IDEs and
# jetbrains-toolbox, kate, android-studio, audacity, brave, thunderbird, notesnook, alpaca,
# gnome-clocks, super-productivity, Path of Building, Hytale Launcher, DaVinci Resolve, VirtualBox.
{ inputs, pkgs, ... }:
{
  home.packages =
    with pkgs;
    [
      # Browsers
      firefox
      ungoogled-chromium

      # Editors / IDEs
      vscode
      zed-editor
      code-cursor

      # File manager
      kdePackages.dolphin
      kdePackages.kio-extras # thumbnails/protocols
      kdePackages.qtsvg # icons
      # ii themes Qt only through ~/.config/kdeglobals (MaterialYouDark, Darkly, breeze-dark),
      # which only the "kde" platform theme reads. lib/mk-host.nix patches illogical-flake
      # to keep QT_QPA_PLATFORMTHEME=kde; these packages make that theme resolvable.
      kdePackages.plasma-integration # "kde" Qt platform theme: reads ii's kdeglobals
      darkly # widgetStyle=Darkly named in ii's kdeglobals
      kdePackages.breeze-icons # Icons Theme=breeze-dark named in ii's kdeglobals

      # Media
      obs-studio
      vlc
      mpv
      spotify
      gpu-screen-recorder
      losslesscut
      upscaler

      # Comms
      vesktop

      # Networking / downloads
      qbittorrent
      proton-vpn # renamed from protonvpn-gui
      rclone
      yad # rclone script's GTK dialogs (scripts/proton-drive-rclone-mount.sh)

      # System / misc utilities
      mission-center
      cartridges
      keypunch
      keymapp
      awakened-poe-trade
    ]
    ++ [
      # Third-party flake (github:0xc000022070/zen-browser-flake, input zen-browser), not
      # nixpkgs. Uses pkgs.stdenv.hostPlatform.system, not the deprecated pkgs.system.
      inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];

  # No other xdg.mimeApps config exists in this repo; VS Code was previously the
  # de facto inode/directory handler by nixpkgs/desktop-file default, not by
  # explicit config here. Likewise chromium was the de facto web handler until
  # the web types below were pinned to zen-beta, matching the hyprland `browser`
  # global set per host in hosts/*/display.nix.
  xdg.mimeApps =
    let
      zen = "zen-beta.desktop";
    in
    {
      enable = true;
      defaultApplications = {
        "inode/directory" = "org.kde.dolphin.desktop";
        "x-scheme-handler/http" = zen;
        "x-scheme-handler/https" = zen;
        "x-scheme-handler/about" = zen;
        "x-scheme-handler/unknown" = zen;
        "text/html" = zen;
        "application/xhtml+xml" = zen;
      };
    };

  # xdg-settings/xdg-open consult $BROWSER first in some tools; keep it aligned
  # with the mime defaults above.
  home.sessionVariables.BROWSER = "zen-beta";
}
