# Hyprland side of GPU Screen Recorder (the NixOS side, programs.gpu-screen-recorder, lives in
# modules/nixos/recording.nix). gsr-ui's first launch starts its background daemon, which then
# listens for gsr-ui-cli commands; everything below drives that daemon through Hyprland binds
# instead of gsr-ui's own native evdev hotkeys, so upstream ii's wf-recorder binds are unbound
# to free the keys and gsr-ui's config is seeded to disable its own hotkey grabbing.
{
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  # PRIME offload hosts (tarmantria) switch the recorder between GPUs; this comes from the host
  # config rather than sysfs, so an NVIDIA desktop with an enabled iGPU is not taken for one.
  primeOffload = osConfig.hardware.nvidia.prime.offload.enable or false;
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

  # Runs gsr-ui's recorder on the GPU that suits the power state, and restarts gsr-ui when
  # that changes. gsr only lists monitors of the GPU it runs on, and on a hybrid laptop that is
  # the iGPU Hyprland renders on, so the dGPU's HDMI port could not be picked and replay
  # captured and encoded the internal panel on the iGPU, costing about 20% game FPS. On mains
  # power, with an NVIDIA card next to another GPU, only the gpu-screen-recorder processes run
  # under PRIME offload, through a PATH wrapper (gsr-ui appends its own copy to the end of
  # PATH, so an earlier entry wins): they capture the NVIDIA-attached monitors and encode on
  # NVIDIA. gsr-ui itself stays on the iGPU: its overlay is an XWayland window, and running it
  # under offload froze the overlay on stopping replay, holding every input. On battery nothing
  # is offloaded, so the dGPU can sleep. A host whose only GPU is NVIDIA (tariognatha) is
  # NVIDIA mode always, without the wrapper.
  #
  # Encoding uses NVENC through gsr's normal codec choice. The NVIDIA hosts run
  # nvidiaPackages.latest because the stable 595 driver only offers NVENC API 13.0 and gsr's
  # FFmpeg needs 13.1; without it gsr-ui fell back to CPU encoding, and the Vulkan encode
  # workaround hung on stop and sat idle mid-replay.
  #
  # Offload for the recorder only. Execs the system copy by absolute path, so it cannot find
  # itself again through PATH.
  gsrOffload = pkgs.writeShellScriptBin "gpu-screen-recorder" ''
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __VK_LAYER_NV_optimus=NVIDIA_only
    export __EGL_VENDOR_LIBRARY_FILENAMES=/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json
    exec /run/current-system/sw/bin/gpu-screen-recorder "$@"
  '';

  gsrUiPower = pkgs.writeShellApplication {
    name = "gsr-ui-power";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.procps
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      prime_offload=${if primeOffload then "1" else "0"}

      on_mains() {
        local ps type have_battery=0
        for ps in /sys/class/power_supply/*; do
          [ -r "$ps/type" ] || continue
          type=$(<"$ps/type")
          if [ "$type" = Battery ]; then
            # Peripheral batteries (mice, headsets) report scope Device; only system ones count.
            [ "$(cat "$ps/scope" 2>/dev/null || true)" = Device ] || have_battery=1
          elif [ "$(cat "$ps/online" 2>/dev/null || true)" = 1 ]; then
            return 0
          fi
        done
        [ "$have_battery" = 0 ]
      }

      # Prints nvidia-offload, nvidia or default.
      pick_mode() {
        local card nvidia=0
        for card in /sys/class/drm/card[0-9]*; do
          # Skip connectors (card1-eDP-1) and non-PCI framebuffers (simpledrm has no vendor).
          [[ $(basename "$card") == *-* ]] && continue
          [ -r "$card/device/vendor" ] || continue
          [ "$(<"$card/device/vendor")" = 0x10de ] && nvidia=1
        done
        if [ "$nvidia" = 0 ]; then
          echo default
        elif [ "$prime_offload" = 0 ]; then
          echo nvidia
        elif on_mains; then
          echo nvidia-offload
        else
          echo default
        fi
      }

      log() { logger -t gsr-ui-power "$*" || true; }

      # Hyprland's exec_cmd detaches this script and logind keeps leftover processes, so a
      # logout or compositor restart does not stop it. Leave once the compositor is gone.
      session_alive() {
        [ -d "$XDG_RUNTIME_DIR/hypr/''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] &&
          [ -S "$XDG_RUNTIME_DIR/''${WAYLAND_DISPLAY:-}" ]
      }

      # gsr-ui runs in its own session (setsid), so its pid is also its process group id. It
      # ignores SIGTERM, and a force-killed gsr-ui leaves its replay recorder running with its
      # RAM buffer, so the whole group is stopped: TERM first, KILL whatever is left after 5s.
      gsr_pid=""
      stop_gsr() {
        [ -n "$gsr_pid" ] || return 0
        kill -TERM -- "-$gsr_pid" 2>/dev/null || true
        for _ in 1 2 3 4 5; do
          pgrep -g "$gsr_pid" >/dev/null || break
          sleep 1
        done
        kill -KILL -- "-$gsr_pid" 2>/dev/null || true
        gsr_pid=""
      }

      # A regular recording (a recorder without -r, which replay uses) holds unsaved work, so a
      # mode switch waits for it to end. Replay restarts with gsr-ui, so it does not block.
      recording_active() {
        local pid
        for pid in $(pgrep -g "$gsr_pid" -x gpu-screen-reco || true); do
          tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -q -- ' -r ' || return 0
        done
        return 1
      }

      start_gsr() {
        local mode=$1
        if [ "$mode" = nvidia-offload ]; then
          PATH="${gsrOffload}/bin:$PATH" setsid gsr-ui &
        else
          setsid gsr-ui &
        fi
        gsr_pid=$!
        log "started gsr-ui in $mode mode"
      }

      udev_pid=""
      cleanup() {
        stop_gsr
        [ -z "$udev_pid" ] || kill "$udev_pid" 2>/dev/null || true
      }
      trap 'exit 0' TERM INT
      trap cleanup EXIT

      mode=$(pick_mode)
      start_gsr "$mode"

      # Power plug events arrive as power_supply change uevents; the 30 s read timeout also
      # wakes the loop without them (a desktop has none), so a crashed gsr-ui comes back and a
      # dead compositor is noticed. gsr-ui restarts only when it died or the mode differs.
      exec 3< <(udevadm monitor --udev --subsystem-match=power_supply)
      udev_pid=$!
      while :; do
        if read -r -t 30 _ <&3; then
          sleep 2
        elif [ $? -le 128 ]; then
          log "udevadm monitor ended, stopping"
          exit 1
        fi
        session_alive || { log "compositor gone, stopping"; exit 0; }
        new=$(pick_mode)
        if ! kill -0 "$gsr_pid" 2>/dev/null; then
          stop_gsr
          mode=$new
          start_gsr "$mode"
        elif [ "$new" != "$mode" ] && ! recording_active; then
          stop_gsr
          mode=$new
          start_gsr "$mode"
        fi
      done
    '';
  };
in
{
  krane.hypr.execOnce = [ "${gsrUiPower}/bin/gsr-ui-power" ];

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
