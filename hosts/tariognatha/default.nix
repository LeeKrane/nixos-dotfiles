{ config, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./storage.nix
    ../../modules/nixos/gpu/nvidia-desktop.nix
    ../../modules/nixos/t7-win11.nix
  ];

  system.stateVersion = "26.05";

  # display.nix sets krane.hypr.*, a home-manager module, imported at the user level.
  # tarkov.nix, spt.nix and stalker-gamma.nix are also home-manager, here and not in
  # modules/home/default.nix: only the hosts that play them.
  home-manager.users.${config.krane.user.name} = {
    imports = [
      ./display.nix
      ../../modules/home/tarkov.nix
      ../../modules/home/spt.nix
      ../../modules/home/stalker-gamma.nix
    ];
    krane.spt.server = "https://spt-tarkov.krane.dev:6969";
  };

  # No CPU vulnerability mitigations: the i9-9900KS pays heavily for its Spectre and MDS ones
  # (IBRS, buffer clears on every kernel exit), and Wine games make syscalls and context switches
  # constantly. A single-user gaming desktop; the cost is protection from local code, such as
  # browser JavaScript, reading other processes' memory through speculative execution.
  boot.kernelParams = [ "mitigations=off" ];

  # Desktop only: peripherals.nix defaults this false via mkDefault, so plain `true` wins.
  services.hardware.openrgb.enable = true;

  # Fika (SPT co-op, spt.nix): the SPT server runs on the home server, so only the raid host's
  # UDP 25565 is opened, for when this machine hosts a raid. home-manager cannot open ports.
  networking.firewall.allowedUDPPorts = [ 25565 ];
}
