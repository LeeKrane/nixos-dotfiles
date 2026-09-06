{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/nixos/gpu/nvidia-desktop.nix
  ];

  system.stateVersion = "26.05";

  # display.nix sets krane.hypr.*, a home-manager module, imported at the user level.
  home-manager.users.krane.imports = [ ./display.nix ];

  # Desktop only: peripherals.nix defaults this false via mkDefault, so plain `true` wins.
  services.hardware.openrgb.enable = true;
}
