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
}
