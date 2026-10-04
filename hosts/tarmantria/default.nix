{ config, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./audio.nix
    ./gpu-mux.nix
    ../../modules/nixos/gpu/nvidia-prime.nix
  ];

  system.stateVersion = "26.05";

  # zram at twice the RAM size instead of boot.nix's 1:1 default: Tarkov alone keeps ~9 GiB
  # resident plus swapped on this 16 GiB laptop, and its launcher another ~3 GiB.
  zramSwap.memoryPercent = 200;

  # nvidia-powerd: without it the RTX 4060 Laptop GPU stays at its 80 W base limit; Dynamic
  # Boost lets it borrow CPU headroom up to the 140 W nvidia-smi reports as its maximum.
  hardware.nvidia.dynamicBoost.enable = true;

  # display.nix sets krane.hypr.*, a home-manager module, imported at the user level.
  # tarkov.nix is also home-manager, here and not in modules/home/default.nix: only the hosts
  # that play it.
  home-manager.users.${config.krane.user.name} = {
    imports = [
      ./display.nix
      ../../modules/home/tarkov.nix
    ];
    krane.tarkov.primeOffload = true;
  };

  # PCI bus IDs from `lspci | grep -E 'VGA|3D'`. FILL AT INSTALL: these placeholders are
  # almost certainly wrong for the actual laptop.
  krane.prime.intelBusId = "PCI:0:2:0"; # set by install.sh
  krane.prime.nvidiaBusId = "PCI:1:0:0"; # set by install.sh
}
