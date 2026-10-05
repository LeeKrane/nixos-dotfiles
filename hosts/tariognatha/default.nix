{ config, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./storage.nix
    ../../modules/nixos/gpu/nvidia-desktop.nix
  ];

  system.stateVersion = "26.05";

  # display.nix sets krane.hypr.*, a home-manager module, imported at the user level.
  # tarkov.nix and stalker-gamma.nix are also home-manager, here and not in
  # modules/home/default.nix: only the hosts that play them.
  home-manager.users.${config.krane.user.name}.imports = [
    ./display.nix
    ../../modules/home/tarkov.nix
    ../../modules/home/stalker-gamma.nix
  ];

  # Desktop only: peripherals.nix defaults this false via mkDefault, so plain `true` wins.
  services.hardware.openrgb.enable = true;
}
