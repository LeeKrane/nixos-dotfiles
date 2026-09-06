# QEMU/UEFI check target overrides for tariognatha (flake.nix's tariognatha-vm), neutralising
# everything that assumes real NVIDIA hardware or a real disk so this builds as a plain llvmpipe
# smoke test. All overrides use mkForce: the base host modules set these at normal priority, so a
# plain definition here would conflict instead of overriding.
{ lib, ... }:
{
  # No GPU passthrough here: force generic `modesetting` instead of nvidia-desktop.nix's "nvidia".
  services.xserver.videoDrivers = lib.mkForce [ "modesetting" ];

  # gpu/nvidia-desktop.nix turns these on for real hardware. Force them off so nothing loads the
  # proprietary NVIDIA stack against a llvmpipe/virtio GPU.
  hardware.nvidia.modesetting.enable = lib.mkForce false;
  hardware.nvidia.open = lib.mkForce false;
  boot.blacklistedKernelModules = lib.mkForce [ ];
  services.ollama.enable = lib.mkForce false;

  # disko.nix points at a real disk and generates fileSystems from it, meaningless for this VM.
  # Forcing disko.devices empty drops that, so fileSystems below is set directly instead.
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

  # Convenience overrides (autologin, no real password), applied only for the VM variant build,
  # never the plain toplevel used for the UEFI eval/build check. Touches no real host or secret.
  virtualisation.vmVariant = {
    virtualisation = {
      memorySize = 8192;
      cores = 4;
      graphics = true;
    };

    services.greetd.settings.initial_session = {
      command = "uwsm start hyprland-uwsm.desktop";
      user = "krane";
    };

    # Throwaway login for the interactive smoke test only. Never used on real hardware.
    users.users.krane.initialPassword = "krane";
  };
}
