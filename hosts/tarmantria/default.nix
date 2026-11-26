{ config, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./audio.nix
    ./gpu-mux.nix
    ./ec-wake.nix
    ../../modules/nixos/gpu/nvidia-prime.nix
    ../../modules/nixos/desktop/t7-win11.nix
  ];

  system.stateVersion = "26.05";

  # For building the Raspberry Pi servers' images (aarch64 steps that cannot be cross-built).
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  zramSwap.memoryPercent = 200;
  zramSwap.algorithm = "lz4";

  hardware.nvidia.dynamicBoost.enable = true;

  # tarkov, spt, stalker-gamma and heuristiclab are imported only on the hosts that use them.
  home-manager.users.${config.krane.user.name} = {
    imports = [
      ./display.nix
      ../../modules/home/desktop/tarkov.nix
      ../../modules/home/desktop/spt.nix
      ../../modules/home/desktop/stalker-gamma.nix
      ../../modules/home/desktop/heuristiclab.nix
    ];
    krane.tarkov.primeOffload = true;
    # taragarmr's wg1 address, reached over wg0; the public port is closed.
    krane.spt.server = "https://192.168.83.1:6969";
    krane.spt.cpus = "0-11";
  };

  networking.hosts."192.168.83.1" = [ "spt-tarkov.krane.dev" ];

  # PCI bus IDs from `lspci | grep -E 'VGA|3D'`.
  krane.prime.intelBusId = "PCI:0:2:0"; # set by install.sh
  krane.prime.nvidiaBusId = "PCI:1:0:0"; # set by install.sh

  # Fika raid host port (spt.nix); home-manager cannot open ports.
  networking.firewall.allowedUDPPorts = [ 25565 ];
}
