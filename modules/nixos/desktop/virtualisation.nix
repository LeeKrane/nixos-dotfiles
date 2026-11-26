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
      enableOnBoot = false;
    };

    virtualisation.podman.enable = config.krane.podman.enable;

    programs.virt-manager.enable = true;
    virtualisation.libvirtd = {
      enable = true;
      qemu.swtpm.enable = true;
    };
    virtualisation.spiceUSBRedirection.enable = true;
  };
}
