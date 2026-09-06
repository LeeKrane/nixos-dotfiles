# Steam and Proton stack. openrgb lives in peripherals.nix, not here.
{ pkgs, ... }:
{
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
    protontricks.enable = true;
    # proton-ge-bin: Glorious Eggroll's Proton build, added as a compat tool.
    extraCompatPackages = [ pkgs.proton-ge-bin ];
  };

  programs.gamemode.enable = true;
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
