# Escape from Tarkov, BSG launcher copy (direct purchase, not Steam), offline PvE only. Online
# PvP needs BattlEye's Proton runtime, which BSG has not enabled for Tarkov. Imported by
# hosts/tarmantria/default.nix and hosts/tariognatha/default.nix.
#
# umu-launcher runs the launcher with the Nix GE-Proton, so no Proton build is downloaded at
# runtime. The prefix is live state, never declared here: `tarkov-setup <installer.exe>` builds
# it once from the installer on the BSG account page (the download needs a login), then the
# launcher downloads the game itself. The game also needs Steam's free Proton BattlEye Runtime
# (app 1161040), installed once with `steam steam://install/1161040`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  env = ''
    export WINEPREFIX="$HOME/Games/tarkov"
    export PROTONPATH="${pkgs.proton-ge-bin.steamcompattool}"
    # umu-default: GE-Proton's Tarkov protonfix is for the Steam copy and expects its layout.
    export GAMEID=umu-default
  '';

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

  # The launcher refuses to start the game unless the BattlEye service is registered.
  # Registering it does not make BattlEye work and does not enable online play.
  beService = "HKLM\\System\\CurrentControlSet\\Services\\BEService";
  beServiceImage = "C:\\Program Files (x86)\\Common Files\\BattlEye\\BEService_x64.exe";

  tarkovSetup = pkgs.writeShellApplication {
    name = "tarkov-setup";
    runtimeInputs = [ pkgs.umu-launcher ];
    text = ''
      ${env}
      if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
        echo "usage: tarkov-setup <path to the BsgLauncher installer .exe>" >&2
        exit 1
      fi
      mkdir -p "$WINEPREFIX"
      umu-run winetricks dotnet48 vcrun2022
      reg() { umu-run reg add '${beService}' /v "$1" /t "$2" /d "$3" /f; }
      reg DisplayName REG_SZ 'BattlEye Service'
      reg ErrorControl REG_DWORD 1
      reg ObjectName REG_SZ LocalSystem
      reg ImagePath REG_SZ '${beServiceImage}'
      reg Start REG_DWORD 2
      reg Type REG_DWORD 16
      reg WOW64 REG_DWORD 1
      umu-run "$1"
      echo "Done. Start the launcher with: tarkov"
    '';
  };

  tarkov = pkgs.writeShellApplication {
    name = "tarkov";
    # No gamemoderun: its preload runs inside umu's Steam Runtime container, which cannot see
    # libgamemode.so in the Nix store, so gamemode never engaged and only spammed the log. The
    # game is registered from outside the container by PID instead, below.
    runtimeInputs = [
      pkgs.umu-launcher
      pkgs.procps
      pkgs.gamemode
      pkgs.power-profiles-daemon
    ];
    text = ''
      ${env}
      # Proton swaps the Windows BEClient for this runtime's Linux one. Without it the game
      # loads the Windows client, which needs the BEService kernel service Wine cannot run, and
      # quits with BATTLEYE_ServiceNotRunningProperly. Steam only installs it for Steam games.
      export PROTON_BATTLEYE_RUNTIME="''${PROTON_BATTLEYE_RUNTIME:-$HOME/.local/share/Steam/steamapps/common/Proton BattlEye Runtime}"
      if [ ! -d "$PROTON_BATTLEYE_RUNTIME" ]; then
        echo "No BattlEye runtime in $PROTON_BATTLEYE_RUNTIME. Install it: steam steam://install/1161040" >&2
        exit 1
      fi
      drive_c="$WINEPREFIX/drive_c"
      launcher=$(find "$drive_c" -name BsgLauncher.exe -print -quit 2>/dev/null || true)
      if [ -z "$launcher" ]; then
        echo "No BsgLauncher.exe in $WINEPREFIX. Run tarkov-setup first." >&2
        exit 1
      fi

      # The game ships its BattlEye files; put them where the registered service points.
      common="$drive_c/Program Files (x86)/Common Files/BattlEye"
      if [ ! -e "$common/BEService_x64.exe" ]; then
        service=$(find "$drive_c/Battlestate Games" -name BEService_x64.exe -print -quit 2>/dev/null || true)
        if [ -n "$service" ]; then
          mkdir -p "$common"
          cp -r "$(dirname "$service")"/. "$common"/
        fi
      fi

      ${lib.optionalString config.krane.tarkov.primeOffload ''
        # PRIME offload: render on the NVIDIA dGPU, for GL and for DXVK's Vulkan.
        export __NV_PRIME_RENDER_OFFLOAD=1
        export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
        export __GLX_VENDOR_LIBRARY_NAME=nvidia
        export __VK_LAYER_NV_optimus=NVIDIA_only
      ''}

      # FPS counter, top right like Steam's. pressure-vessel imports the host's MangoHud Vulkan
      # layer (gaming.nix) into umu's container, so the variable alone enables it for DXVK. The
      # blacklist keeps it off the launcher, which DXVK also renders.
      export MANGOHUD=1
      export MANGOHUD_CONFIG="''${MANGOHUD_CONFIG:-fps_only,position=top-right,blacklist=BsgLauncher.exe}"
      # Color correction (colorLut above). Like MangoHud, the host's vkBasalt layer (gaming.nix)
      # reaches DXVK in umu's container; it also tints the launcher. Home toggles it in game.
      export ENABLE_VKBASALT=1
      # GE-Proton bundles its own vkBasalt layer under another name and enables it on the same
      # variable, which applied the LUT twice. Keep only the host layer.
      export VK_LOADER_LAYERS_DISABLE=VK_LAYER_VKBASALT_post_processing
      export VKBASALT_CONFIG_FILE="''${VKBASALT_CONFIG_FILE:-${vkbasaltConf}}"
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

      trap 'kill "$gamemode_watch" 2>/dev/null; [ "$paused_replay" = 0 ] || gsr-ui-cli toggle-replay' EXIT

      # The launcher is CEF-based and hangs on its software rasterizer under Proton. umu-run
      # returns once the launcher exits, not the game.
      # The performance power profile is held for the session and released when the launcher
      # exits, back to whatever profile was set before.
      powerprofilesctl launch --profile performance --reason "Escape from Tarkov" -- \
        umu-run "$launcher" --disable-software-rasterizer "$@"
    '';
  };
in
{
  options.krane.tarkov.primeOffload = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Export the PRIME render offload variables so the game renders on the NVIDIA dGPU. Only
      for hybrid-graphics laptops: a single-GPU host has no NVIDIA-G0 provider to offload to.
    '';
  };

  config.home.packages = [
    tarkovSetup
    tarkov
  ];

  config.xdg.desktopEntries.tarkov = {
    name = "Escape from Tarkov";
    comment = "BSG launcher through umu-launcher and GE-Proton";
    exec = "${tarkov}/bin/tarkov";
    icon = "applications-games";
    categories = [ "Game" ];
  };
}
