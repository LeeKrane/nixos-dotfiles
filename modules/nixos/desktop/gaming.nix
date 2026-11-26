{ pkgs, ... }:
{
  programs.steam = {
    enable = true;
    package = pkgs.steam.override { extraArgs = "-console"; };
    gamescopeSession.enable = true;
    protontricks.enable = true;
    extraCompatPackages = [ pkgs.proton-ge-bin ];
  };

  programs.gamemode = {
    enable = true;
    settings.general = {
      renice = 20;
      ioprio = 0;
    };
  };

  # GE-Proton uses ntsync whenever /dev/ntsync exists, which needs the module loaded.
  boot.kernelModules = [ "ntsync" ];
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
