{ config, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./audio.nix
    ./gpu-mux.nix
    ../../modules/nixos/gpu/nvidia-prime.nix
    ../../modules/nixos/t7-win11.nix
  ];

  system.stateVersion = "26.05";

  # zram at twice the RAM size instead of boot.nix's 1:1 default: Tarkov alone keeps ~9 GiB
  # resident plus swapped on this 16 GiB laptop, and its launcher another ~3 GiB.
  zramSwap.memoryPercent = 200;
  # lz4 instead of boot.nix's zstd: SPT keeps over 10 GiB swapped mid-raid, and zstd's slower
  # decompression shows up as stutter whenever the game touches it. lz4 compresses less, so the
  # same swapped data takes more RAM.
  zramSwap.algorithm = "lz4";

  # nvidia-powerd: without it the RTX 4060 Laptop GPU stays at its 80 W base limit; Dynamic
  # Boost lets it borrow CPU headroom up to the 140 W nvidia-smi reports as its maximum.
  hardware.nvidia.dynamicBoost.enable = true;

  # Suspend the way Nobara and CachyOS do, where it resumed fine on this laptop: VRAM saved
  # to a file by the nvidia-suspend/resume systemd services. The kernel-notifier default for
  # open modules >= 595, with no TemporaryFilePath, left both s2idle and S3 stuck at
  # "PM: suspend entry" (keyboard light blinking, not even the power button woke it).
  hardware.nvidia.powerManagement.kernelSuspendNotifier = false;
  boot.extraModprobeConfig = "options nvidia NVreg_TemporaryFilePath=/var/tmp";

  # display.nix sets krane.hypr.*, a home-manager module, imported at the user level.
  # tarkov.nix, spt.nix, stalker-gamma.nix and heuristiclab.nix are also home-manager,
  # here and not in modules/home/default.nix: only the hosts that use them.
  home-manager.users.${config.krane.user.name} = {
    imports = [
      ./display.nix
      ../../modules/home/tarkov.nix
      ../../modules/home/spt.nix
      ../../modules/home/stalker-gamma.nix
      ../../modules/home/heuristiclab.nix
    ];
    krane.tarkov.primeOffload = true;
    # taragarmr's wg1 address, reached over wg0; the public port is closed.
    krane.spt.server = "https://192.168.83.1:6969";
    # The i7-13700H's P-cores (/sys/devices/cpu_core/cpus); 12-19 are its E-cores.
    krane.spt.cpus = "0-11";
  };

  # The SPT server hands out spt-tarkov.krane.dev as its backend address, so it has to
  # resolve to the WireGuard side too.
  networking.hosts."192.168.83.1" = [ "spt-tarkov.krane.dev" ];

  # PCI bus IDs from `lspci | grep -E 'VGA|3D'`. FILL AT INSTALL: these placeholders are
  # almost certainly wrong for the actual laptop.
  krane.prime.intelBusId = "PCI:0:2:0"; # set by install.sh
  krane.prime.nvidiaBusId = "PCI:1:0:0"; # set by install.sh

  # Fika (SPT co-op, spt.nix): the SPT server runs on the home server, so only the raid host's
  # UDP 25565 is opened, for when this machine hosts a raid. home-manager cannot open ports.
  networking.firewall.allowedUDPPorts = [ 25565 ];
}
