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
      losslesscut
      upscaler
      voicestudio # pkgs/voicestudio

      # Comms
      vesktop

      # Notes: vault syncs to the home server through the Self-hosted LiveSync plugin,
      # configured in-app (its config holds the CouchDB credentials, so it stays out of Nix).
      obsidian

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

  # Text types are mapped to Zed in neovim.nix. VS Code was previously the
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

  # Vesktop has no global shortcuts on Wayland, so forward Discord's built-in in-app toggles
  # (Ctrl+Shift+M mute, Ctrl+Shift+D deafen) to its window without focusing it.
  krane.hypr.binds = [
    {
      keys = "F6";
      action = ''hl.dsp.send_shortcut({ mods = "CTRL SHIFT", key = "M", window = "class:vesktop" })'';
      description = "Vesktop: Toggle mute";
    }
    {
      keys = "F7";
      action = ''hl.dsp.send_shortcut({ mods = "CTRL SHIFT", key = "D", window = "class:vesktop" })'';
      description = "Vesktop: Toggle deafen";
    }
  ];

  # xdg-settings/xdg-open consult $BROWSER first in some tools; keep it aligned
  # with the mime defaults above.
  home.sessionVariables.BROWSER = "zen-beta";
}
