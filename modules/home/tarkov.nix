# Escape from Tarkov, BSG launcher copy (direct purchase, not Steam), offline PvE only. Online
# PvP needs BattlEye's Proton runtime, which BSG has not enabled for Tarkov. Imported only by
# hosts/tarmantria/default.nix.
#
# umu-launcher runs the launcher with the Nix GE-Proton, so no Proton build is downloaded at
# runtime. The prefix is live state, never declared here: `tarkov-setup <installer.exe>` builds
# it once from the installer on the BSG account page (the download needs a login), then the
# launcher downloads the game itself. The game also needs Steam's free Proton BattlEye Runtime
# (app 1161040), installed once with `steam steam://install/1161040`.
{ pkgs, ... }:
let
  env = ''
    export WINEPREFIX="$HOME/Games/tarkov"
    export PROTONPATH="${pkgs.proton-ge-bin.steamcompattool}"
    # umu-default: GE-Proton's Tarkov protonfix is for the Steam copy and expects its layout.
    export GAMEID=umu-default
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
    # libgamemode.so in the Nix store, so gamemode never engaged and only spammed the log.
    runtimeInputs = [ pkgs.umu-launcher ];
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

      # PRIME offload: render on the NVIDIA dGPU, for GL and for DXVK's Vulkan.
      export __NV_PRIME_RENDER_OFFLOAD=1
      export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
      export __GLX_VENDOR_LIBRARY_NAME=nvidia
      export __VK_LAYER_NV_optimus=NVIDIA_only
      # The launcher is CEF-based and hangs on its software rasterizer under Proton.
      exec umu-run "$launcher" --disable-software-rasterizer "$@"
    '';
  };
in
{
  home.packages = [
    tarkovSetup
    tarkov
  ];

  xdg.desktopEntries.tarkov = {
    name = "Escape from Tarkov";
    comment = "BSG launcher through umu-launcher and GE-Proton";
    exec = "${tarkov}/bin/tarkov";
    icon = "applications-games";
    categories = [ "Game" ];
  };
}
