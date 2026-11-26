{
  config,
  lib,
  pkgs,
  ...
}:
let
  wol = (import ../../lib/lan.nix).wol.tariognatha;
in
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./storage.nix
    ../../modules/nixos/gpu/nvidia-desktop.nix
    ../../modules/nixos/desktop/t7-win11.nix
  ];

  system.stateVersion = "26.05";

  # For building the Raspberry Pi servers' images (aarch64 steps that cannot be cross-built).
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # tarkov, spt, stalker-gamma and heuristiclab are imported only on the hosts that use them.
  home-manager.users.${config.krane.user.name} = {
    imports = [
      ./display.nix
      ./easyeffects.nix
      ../../modules/home/desktop/tarkov.nix
      ../../modules/home/desktop/spt.nix
      ../../modules/home/desktop/stalker-gamma.nix
      ../../modules/home/desktop/heuristiclab.nix
    ];
    # taragarmr's wg1 address, reached over wg0; the public port is closed.
    krane.spt.server = "https://192.168.83.1:6969";
  };

  networking.hosts."192.168.83.1" = [ "spt-tarkov.krane.dev" ];

  boot.kernelParams = [ "mitigations=off" ];

  # Allows nice -11, the PipeWire level, for EasyEffects (easyeffects.nix); applies from the next login.
  security.pam.loginLimits = [
    {
      domain = config.krane.user.name;
      type = "-";
      item = "nice";
      value = "-11";
    }
  ];

  # Desktop only: peripherals.nix defaults this false via mkDefault, so plain `true` wins.
  services.hardware.openrgb.enable = true;

  # Fika raid host port (spt.nix); home-manager cannot open ports.
  networking.firewall.allowedUDPPorts = [ 25565 ];

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", ATTR{address}=="${wol.mac}", RUN+="${pkgs.ethtool}/bin/ethtool -s $name wol g"
  '';
  environment.systemPackages = [
    (lib.hiPrio (pkgs.writeShellScriptBin "poweroff" "exec systemctl suspend"))
  ];
}
