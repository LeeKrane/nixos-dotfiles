# GUI applications. flameshot is absent: ii ships hyprshot, already wired into its keybinds.
{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  awakened-poe-trade = pkgs.awakened-poe-trade.override {
    # Upstream bundles Electron 40. From Electron 44 on, clipboard.readText()/writeText()
    # return Promises; APT's clipboard poller then throws inside a timer and price checks
    # silently never open. 43 is the newest nixpkgs Electron that keeps them synchronous
    # and is not EOL. Revisit when APT supports the async clipboard or 43 goes EOL.
    electron = pkgs.electron_43-bin;
    # APT's overlay backend (electron-overlay-window, uiohook) is X11-only. NIXOS_OZONE_WL=1
    # makes Electron run native Wayland, where the overlay cannot track or cover the game
    # (PoE runs under Proton in XWayland). Force XWayland. The overlay window is
    # override-redirect, so Hyprland window rules do not apply to it. It cannot take focus
    # from the game either, so in PoE use Windowed Fullscreen and turn off "Confine Mouse to
    # Window": exclusive fullscreen and confinement make Wine grab the pointer, which leaves
    # the price-check panel unclickable and drops the first copy keypress.
    commandLineArgs = [ "--ozone-platform=x11" ];
  };
in
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
      pycharm
      jetbrains.idea # Scala plugin from its Marketplace; sbt/JDK from dev.nix

      # File manager
      kdePackages.dolphin
      kdePackages.kio-extras
      kdePackages.qtsvg
      kdePackages.ark
      # ii themes Qt through ~/.config/kdeglobals, which only the "kde" platform theme reads.
      # lib/mk-host.nix patches illogical-flake to keep QT_QPA_PLATFORMTHEME=kde.
      kdePackages.plasma-integration
      darkly
      kdePackages.breeze-icons

      # Media
      qview
      obs-studio
      vlc
      mpv
      spotify
      losslesscut
      upscaler
      voicestudio

      # Comms
      vesktop

      # Vault syncs through the Self-hosted LiveSync plugin, configured in-app (its config holds
      # the CouchDB credentials).
      obsidian

      # Networking / downloads
      qbittorrent
      proton-vpn
      rclone
      yad # used by scripts/proton-drive-rclone-mount.sh

      # System / misc utilities
      mission-center
      cartridges
      keypunch
      keymapp

      # Path of Exile
      awakened-poe-trade
      # Runtime for Path of Building Community; fetches PoB's Lua sources itself on first start.
      path-of-building
    ]
    ++ [
      # Third-party flake (input zen-browser), not nixpkgs.
      inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];

  xdg.mimeApps =
    let
      zen = "zen-beta.desktop";
      imageTypes = [
        "image/png"
        "image/jpeg"
        "image/gif"
        "image/webp"
        "image/bmp"
        "image/tiff"
        "image/avif"
        "image/heic"
        "image/jxl"
        "image/svg+xml"
        "image/x-icon"
      ];
    in
    {
      enable = true;
      defaultApplications = lib.genAttrs imageTypes (_: "com.interversehq.qView.desktop") // {
        "inode/directory" = "org.kde.dolphin.desktop";
        "x-scheme-handler/http" = zen;
        "x-scheme-handler/https" = zen;
        "x-scheme-handler/about" = zen;
        "x-scheme-handler/unknown" = zen;
        "text/html" = zen;
        "application/xhtml+xml" = zen;
      };
    };

  # Vesktop has no global shortcuts on Wayland: forward Discord's in-app toggles
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

  home.sessionVariables.BROWSER = "zen-beta";
}
