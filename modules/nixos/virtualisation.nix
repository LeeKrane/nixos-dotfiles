# Containers and VMs. VirtualBox is out of scope, libvirt/QEMU only.
{
  config,
  lib,
  ...
}:
{
  options.krane.podman.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Enable podman alongside docker. Off by default: the workflow only ever
      used docker. podman stays an opt-in escape hatch.
    '';
  };

  config = {
    virtualisation.docker = {
      enable = true;
      # Starts on demand, not at boot.
      enableOnBoot = false;
    };

    virtualisation.podman.enable = config.krane.podman.enable;

    programs.virt-manager.enable = true;
    virtualisation.libvirtd = {
      enable = true;
      # OVMF now ships with QEMU. swtpm is the only submodule still needed.
      qemu.swtpm.enable = true;
    };
    virtualisation.spiceUSBRedirection.enable = true;
  };
}
