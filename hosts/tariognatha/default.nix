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

  # The SPT server hands out spt-tarkov.krane.dev as its backend address, so it has to
  # resolve to the WireGuard side too.
  networking.hosts."192.168.83.1" = [ "spt-tarkov.krane.dev" ];

  # No CPU vulnerability mitigations: the i9-9900KS pays heavily for its Spectre and MDS ones
  # (IBRS, buffer clears on every kernel exit), and Wine games make syscalls and context switches
  # constantly. A single-user gaming desktop; the cost is protection from local code, such as
  # browser JavaScript, reading other processes' memory through speculative execution.
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

  # Wake-on-LAN: tarronax runs `wake-tariognatha`. Only from suspend: the onboard I219-V is
  # dead (its PHY never answers) and the board cuts USB power when fully off, so the USB
  # adapter is matched by MAC (any port) and `poweroff` suspends instead. A program, not an
  # alias, so ii's search (`bash -c`) and sudo get it too. `systemctl poweroff` still shuts down.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", ATTR{address}=="${wol.mac}", RUN+="${pkgs.ethtool}/bin/ethtool -s $name wol g"
  '';
  environment.systemPackages = [
    (lib.hiPrio (pkgs.writeShellScriptBin "poweroff" "exec systemctl suspend"))
  ];
}
