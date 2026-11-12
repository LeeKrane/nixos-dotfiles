# Pieces shared by tarkov.nix (live EFT) and spt.nix (Single Player Tarkov + Fika): the umu and
# GE-Proton environment, PRIME offload, MangoHud and the vkBasalt color LUT, the per-session
# extras (gamemode registration, performance power profile, paused replay buffer), the wait for
# the game to exit, and the mutual exclusion between the two installs. A plain function, not a
# module: each caller does `import ./tarkov-common.nix { inherit config lib pkgs; }` and
# splices the strings into its own scripts. Reads krane.tarkov.primeOffload, declared by
# tarkov.nix, so both files are imported together.
{
  config,
  lib,
  pkgs,
}:
let
  proton = pkgs.proton-ge-bin.steamcompattool;

  # Display color as set in the NVIDIA Control Panel on Windows, in the units the driver stores
  # under HKCU\Software\NVIDIA Corporation\Global\NVTweak\Devices\<id>\Color, not the slider
  # percentages: brightness and contrast 100 are neutral, gamma is the slider value times 100.
  # Sliders 50% / 62% / 2.30 store 100 / 108 / 230. Applied to the game only, through vkBasalt's
  # LUT effect, since Wayland has no per-app gamma ramp.
  color = {
    brightness = 100;
    contrast = 108;
    gamma = 230;
  };

  # The driver's ramp, as reverse-engineered from nvxdapix.dll by nvBrightness (CalculateGamma in
  # src/nvDisplay.cpp): contrast stretches around the midpoint, brightness offsets, then gamma,
  # each step clamped. The ramp is per channel; the 3D LUT applies it to R, G and B.
  colorLut = pkgs.runCommand "tarkov-color.cube" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python3 - > $out <<'EOF'
    b = (${toString color.brightness} - 100) / 100
    c = (${toString color.contrast} - 100) / 100
    g = 100 / ${toString color.gamma}
    def ramp(x):
        x = (c + 1) * (x - 0.5) if c <= 0 else (x - 0.5) / (1 - c)
        x = min(max(x + b + 0.5, 0.0), 1.0)
        return min(x**g, 1.0)
    n = 64
    print(f"LUT_3D_SIZE {n}")
    t = [ramp(i / (n - 1)) for i in range(n)]
    for bi in range(n):
        for gi in range(n):
            for ri in range(n):
                print(f"{t[ri]:.6f} {t[gi]:.6f} {t[bi]:.6f}")
    EOF
  '';

  vkbasaltConf = pkgs.writeText "tarkov-vkbasalt.conf" ''
    effects = lut
    lutFile = ${colorLut}
    toggleKey = Home
  '';
in
{
  inherit proton;

  # The tools the shared shell snippets below call, for a script's runtimeInputs.
  runtimeInputs = [
    pkgs.umu-launcher
    pkgs.procps
    pkgs.gamemode
    pkgs.power-profiles-daemon
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.zenity
  ];

  # prefix is a shell expression, e.g. "$HOME/Games/tarkov".
  umuEnv = prefix: ''
    export WINEPREFIX="${prefix}"
    export PROTONPATH="${proton}"
    # umu-default: GE-Proton's Tarkov protonfix is for the Steam copy and expects its layout.
    export GAMEID=umu-default
  '';

  primeEnv = lib.optionalString config.krane.tarkov.primeOffload ''
    # PRIME offload: render on the NVIDIA dGPU, for GL and for DXVK's Vulkan.
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __VK_LAYER_NV_optimus=NVIDIA_only
  '';

  # launcherExe is the launcher's file name, kept out of MangoHud.
  renderEnv = launcherExe: ''
    # FPS counter, top right like Steam's. pressure-vessel imports the host's MangoHud Vulkan
    # layer (gaming.nix) into umu's container, so the variable alone enables it for DXVK. The
    # blacklist keeps it off the launcher, which DXVK also renders.
    export MANGOHUD=1
    export MANGOHUD_CONFIG="''${MANGOHUD_CONFIG:-fps_only,position=top-right,blacklist=${launcherExe}}"
    # Color correction (colorLut above). Like MangoHud, the host's vkBasalt layer (gaming.nix)
    # reaches DXVK in umu's container; it also tints the launcher. Home toggles it in game.
    export ENABLE_VKBASALT=1
    # GE-Proton bundles its own vkBasalt layer under another name and enables it on the same
    # variable, which applied the LUT twice. Keep only the host layer.
    export VK_LOADER_LAYERS_DISABLE=VK_LAYER_VKBASALT_post_processing
    export VKBASALT_CONFIG_FILE="''${VKBASALT_CONFIG_FILE:-${vkbasaltConf}}"
  '';

  # Starts the per-session extras and defines session_end to undo them; the EXIT trap it sets
  # runs session_end, a caller needing more cleanup replaces the trap and calls session_end too.
  # The game process is EscapeFromTarkov.exe in both installs.
  session = reason: ''
    # gsr-ui's replay buffer (recording.nix) holds ~220 MiB of VRAM and keeps NVENC busy, and
    # Tarkov fills tarmantria's 8 GiB of VRAM on its own. Pause it for the session, and resume it only
    # if it was on. The replay recorder is the gpu-screen-recorder process run with -r.
    replay_on() {
      local pid
      for pid in $(pgrep -x gpu-screen-reco || true); do
        tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -q -- ' -r ' && return 0
      done
      return 1
    }
    paused_replay=0
    if command -v gsr-ui-cli >/dev/null && replay_on; then
      gsr-ui-cli toggle-replay
      paused_replay=1
    fi

    # Register each game process with gamemoded as the launcher starts it; gamemoded drops it
    # again when it exits. The match skips EscapeFromTarkov_BE.exe, BattlEye's stub. -r
    # toggles, so each PID is requested once.
    (
      registered=" "
      while :; do
        for pid in $(pgrep -x EscapeFromTarko || true); do
          case "$registered" in *" $pid "*) continue ;; esac
          tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -q 'EscapeFromTarkov\.exe' || continue
          gamemoded -r"$pid" >/dev/null && registered="$registered$pid "
        done
        sleep 5
      done
    ) &
    gamemode_watch=$!

    session_end() {
      kill "$gamemode_watch" 2>/dev/null
      [ "$paused_replay" = 0 ] || gsr-ui-cli toggle-replay
    }
    trap session_end EXIT

    # Hold the performance power profile until this script exits. The hold ends with the
    # holder process, and tail exits once this shell does.
    powerprofilesctl launch --profile performance --reason "${reason}" -- \
      tail --pid=$$ -f /dev/null &
  '';

  # Run after the launcher returns: it exits once the game starts, so keep the session (power
  # profile, gamemode registration, paused replay) until the game exits too.
  waitForGameExit = ''
    sleep 5
    while pgrep -x EscapeFromTarko >/dev/null; do
      sleep 5
    done
  '';

  # Live EFT and SPT never run together: they would share the GPU, the replay buffer and, for
  # Fika, the same ports and window focus, and a game from one prefix confuses the other's
  # wait-for-exit loop, which matches on the process name both installs share. Both have
  # EscapeFromTarkov.exe, so an install is told apart by the WINEPREFIX in each process's
  # environment, which umu and Wine pass on to every child; the SPT server, a native process,
  # is started with the SPT prefix in its environment for this. STEAM_COMPAT_DATA_PATH is the
  # same path and also matches. When the user says yes to closing the other install, all of it
  # is killed without a graceful close: nothing of the other install is worth keeping then.
  exclusion = ''
    # prefix_pids <prefix>: PIDs whose environment names the prefix, by the path as given and
    # as resolved, since ~/Games may be a symlink. One grep over all of /proc, not one per
    # process. /proc/PID/environ is the environment a process started with, so this script,
    # which exports the prefix only after it started, and its subshells do not match; the
    # grep runs without the variables so it never matches itself either.
    prefix_pids() {
      local args=() p f pid out
      for p in "$1" "$(realpath -m "$1")"; do
        args+=(-e "WINEPREFIX=$p" -e "STEAM_COMPAT_DATA_PATH=$p")
      done
      # -z: environ is NUL-separated; -l: only the matching files' names.
      out=$(env -u WINEPREFIX -u STEAM_COMPAT_DATA_PATH \
        grep -lazxF "''${args[@]}" /proc/[0-9]*/environ 2>/dev/null || true)
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        pid=''${f#/proc/}
        pid=''${pid%/environ}
        [ "$pid" = "$$" ] || echo "$pid"
      done <<<"$out"
    }

    # stop_prefix <prefix>: KILL every process of the prefix and wait until none is left. No
    # wineserver -k or TERM first, as there is nothing to save. A killed process can leave
    # children behind, so the kill repeats on whatever the next look finds.
    stop_prefix() {
      local pids _
      for _ in $(seq 40); do
        pids=$(prefix_pids "$1")
        [ -n "$pids" ] || return 0
        # shellcheck disable=SC2086
        kill -KILL $pids 2>/dev/null || true
        sleep 0.25
      done
      [ -z "$(prefix_pids "$1")" ]
    }

    # ensure_exclusive <this> <other> <other prefix>: if the other install runs, ask to close
    # it; no, or a closed dialog, leaves without starting.
    ensure_exclusive() {
      [ -n "$(prefix_pids "$3")" ] || return 0
      zenity --question --no-wrap --title="$1" \
        --text="$2 is running. Close it and start $1?" || exit 0
      if ! stop_prefix "$3"; then
        zenity --error --no-wrap --title="$1" --text="Could not close $2." || true
        exit 1
      fi
    }
  '';

  # game_pids <prefix>: the EscapeFromTarkov.exe processes of that prefix, by name and prefix
  # both, since the other install's game has the same name. Needs exclusion.
  gamePids = ''
    game_pids() {
      local pids pid
      pids=" $(prefix_pids "$1" | tr '\n' ' ')"
      for pid in $(pgrep -x EscapeFromTarko || true); do
        case "$pids" in *" $pid "*) echo "$pid" ;; esac
      done
    }
  '';
}
