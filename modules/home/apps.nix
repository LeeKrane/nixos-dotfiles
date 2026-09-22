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

  # illogical-flake's custom/env.lua forces QT_QPA_PLATFORMTHEME=qt6ct, but ii's matugen
  # pipeline only themes Qt through ~/.config/kdeglobals (MaterialYouDark, Darkly, breeze-dark),
  # which only the "kde" platform theme reads. Nothing writes ~/.config/qt6ct, so qt6ct falls
  # back to a light Fusion palette (white Dolphin). Restore ii upstream's value; krane.hypr.env
  # is appended after the flake's block, so this hl.env wins.
  krane.hypr.env.QT_QPA_PLATFORMTHEME = "kde";

  # No other xdg.mimeApps config exists in this repo; VS Code was previously the
  # de facto inode/directory handler by nixpkgs/desktop-file default, not by
  # explicit config here.
  xdg.mimeApps = {
    enable = true;
    defaultApplications."inode/directory" = "org.kde.dolphin.desktop";
  };
}
