# Steam and Proton stack. openrgb lives in peripherals.nix, not here.
{ pkgs, ... }:
{
  programs.steam = {
    enable = true;
    # -console adds the Console tab to the client on every start.
    package = pkgs.steam.override { extraArgs = "-console"; };
    gamescopeSession.enable = true;
    protontricks.enable = true;
    # proton-ge-bin: Glorious Eggroll's Proton build, added as a compat tool.
    extraCompatPackages = [ pkgs.proton-ge-bin ];
  };

  programs.gamemode = {
    enable = true;
    settings.general = {
      # Registered games get the highest CPU priority (nice -20) and best-effort I/O priority 0.
      # PipeWire runs real-time through rtkit, so audio keeps up regardless.
      renice = 20;
      ioprio = 0;
    };
  };

  # ntsync: Wine's sync primitives in the kernel instead of wineserver round trips. GE-Proton
  # uses it on its own whenever /dev/ntsync exists, which needs the module loaded.
  boot.kernelModules = [ "ntsync" ];
  # The kernel deliberately slows down split-lock instructions, which some Windows games issue
  # constantly. Valve's Steam Deck kernel disables the slowdown for the same reason.
  boot.kernel.sysctl."kernel.split_lock_mitigate" = 0;
  programs.gamescope.enable = true;

  hardware.steam-hardware.enable = true;

  environment.systemPackages = with pkgs; [
    mangohud
    goverlay
    lutris
    heroic
    bottles
    umu-launcher
    protonplus
    r2modman
    vkbasalt
  ];
}
