# Overrides for tariognatha-vm (flake.nix): a QEMU/UEFI llvmpipe smoke test without real NVIDIA
# hardware or disk. mkForce because the base modules set these at normal priority.
{ config, lib, ... }:
{
  services.xserver.videoDrivers = lib.mkForce [ "modesetting" ];

  # nvidia-desktop.nix enables these for real hardware; off so nothing loads the NVIDIA stack
  # against llvmpipe.
  hardware.nvidia.modesetting.enable = lib.mkForce false;
  hardware.nvidia.open = lib.mkForce false;
  boot.blacklistedKernelModules = lib.mkForce [ ];
  services.ollama.enable = lib.mkForce false;

  # disko.nix points at a real disk; emptying disko.devices drops its fileSystems, set below.
  disko.devices = lib.mkForce { };

  fileSystems = lib.mkForce {
    "/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };
    "/boot" = {
      device = "/dev/disk/by-label/ESP";
      fsType = "vfat";
    };
  };

  # Autologin and a throwaway password, for the VM variant build only.
  virtualisation.vmVariant = {
    virtualisation = {
      memorySize = 8192;
      cores = 4;
      graphics = true;
    };

    services.greetd.settings.initial_session = {
      command = "uwsm start hyprland-uwsm.desktop";
      user = config.krane.user.name;
    };

    users.users.${config.krane.user.name}.initialPassword = "krane";
  };
}
