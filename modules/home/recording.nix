# Hyprland side of GPU Screen Recorder (the NixOS side, programs.gpu-screen-recorder, lives in
# modules/nixos/recording.nix). gsr-ui's first launch starts its background daemon, which then
# listens for gsr-ui-cli commands; everything below drives that daemon through Hyprland binds
# instead of gsr-ui's own native evdev hotkeys, so upstream ii's wf-recorder binds are unbound
# to free the keys and gsr-ui's config is seeded to disable its own hotkey grabbing.
{ lib, pkgs, ... }:
let
  # Seed content for ~/.config/gpu-screen-recorder/config_ui, verified against
  # gpu-screen-recorder-ui's own Config.cpp: config_ui is a flat "key value" (single space,
  # no "=") file, one setting per line (parse_key_value, Config.cpp ~L165); keys the file
  # doesn't set just keep the app's built-in defaults on load (read_config, ~L376), so this
  # minimal two-line file loads cleanly instead of resetting anything.
  #
  # main.config_file_version's value is GSR_CONFIG_FILE_VERSION (include/Config.hpp), 2 as of
  # this gsr-ui version; save_config() always rewrites it to the app's current constant anyway,
  # so this only needs to be a value the loader accepts, not track upstream forever.
  #
  # main.hotkeys_enable_option controls gsr-ui's own native evdev hotkey grab. Its default is
  # "enable_hotkeys" (main_config.hotkeys_enable_option, include/Config.hpp), which would grab
  # gsr-ui's built-in keyboard hotkeys (Alt+Z, Alt+F9, Alt+F10, ...) directly from the input
  # device, racing the Hyprland binds below for the same keys. "disable_hotkeys" is the literal
  # id used both by that config field and by the settings-page radio button
  # (GlobalSettingsPage.cpp's create_enable_keyboard_hotkeys_button, ~L195-208), and leaves
  # Hyprland as the only thing driving gsr-ui, via gsr-ui-cli.
  gsrUiConfigSeed = pkgs.writeText "gsr-ui-config-ui-seed" ''
    main.config_file_version 2
    main.hotkeys_enable_option disable_hotkeys
  '';
in
{
  krane.hypr.execOnce = [ "gsr-ui" ];

  # Upstream ii wf-recorder binds (illogical-flake's hyprland/keybinds.lua:85-93), replaced by
  # the gsr-ui-cli binds below.
  krane.hypr.unbinds = [
    "SUPER + SHIFT + R"
    "SUPER + ALT + R"
    "CTRL + ALT + R"
    "SUPER + SHIFT + ALT + R"
  ];

  krane.hypr.binds = [
    {
      keys = "ALT + Z";
      action = ''hl.dsp.exec_cmd("gsr-ui-cli toggle-show")'';
      description = "Recording: GPU Screen Recorder overlay";
    }
    {
      keys = "ALT + F9";
      action = ''hl.dsp.exec_cmd("gsr-ui-cli toggle-record")'';
      description = "Recording: Start/stop recording";
    }
    {
      keys = "ALT + SHIFT + F10";
      action = ''hl.dsp.exec_cmd("gsr-ui-cli toggle-replay")'';
      description = "Recording: Toggle replay";
    }
    {
      keys = "ALT + F10";
      action = ''hl.dsp.exec_cmd("gsr-ui-cli replay-save")'';
      description = "Recording: Save replay";
    }
  ];

  # Seed-if-absent, not owned: gsr-ui rewrites config_ui in full whenever its settings page is
  # closed (GlobalSettingsPage::save(), called from on_navigate_away_from_page()), so treating
  # this file as declarative would fight the app on every settings change made through its UI.
  home.activation.seedGsrUiConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target="$HOME/.config/gpu-screen-recorder/config_ui"
    if [ ! -e "$target" ]; then
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$target")"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -Dm644 "${gsrUiConfigSeed}" "$target"
    fi
  '';
}
