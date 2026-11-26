# Hyprland side of GPU Screen Recorder (NixOS side: modules/nixos/desktop/recording.nix).
# Hyprland binds drive gsr-ui's background daemon through gsr-ui-cli instead of its native evdev
# hotkeys: upstream ii's wf-recorder binds are unbound to free the keys, and gsr-ui's config is
# seeded to disable its own hotkey grabbing.
{
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  # PRIME offload hosts (tarmantria) switch the recorder between GPUs; taken from host config, not
  # sysfs, so an NVIDIA desktop with an enabled iGPU is not mistaken for one.
  primeOffload = osConfig.hardware.nvidia.prime.offload.enable or false;
  gsrUiConfigSeed = pkgs.writeText "gsr-ui-config-ui-seed" ''
    main.config_file_version 2
    main.hotkeys_enable_option disable_hotkeys
  '';

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
            [ "$(cat "$ps/scope" 2>/dev/null || true)" = Device ] || have_battery=1
          elif [ "$(cat "$ps/online" 2>/dev/null || true)" = 1 ]; then
            return 0
          fi
        done
        [ "$have_battery" = 0 ]
      }

      pick_mode() {
        local card nvidia=0
        for card in /sys/class/drm/card[0-9]*; do
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

      session_alive() {
        [ -d "$XDG_RUNTIME_DIR/hypr/''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] &&
          [ -S "$XDG_RUNTIME_DIR/''${WAYLAND_DISPLAY:-}" ]
      }

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

  # Upstream ii's wf-recorder binds, replaced by the gsr-ui-cli binds below.
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

  home.activation.seedGsrUiConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target="$HOME/.config/gpu-screen-recorder/config_ui"
    if [ ! -e "$target" ]; then
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$target")"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -Dm644 "${gsrUiConfigSeed}" "$target"
    fi
  '';
}
