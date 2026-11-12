# Fixture host for checks.server-eval in flake.nix: the least hardware a role = "server"
# config needs to evaluate. Not under hosts/, so it is no nixosConfiguration.
{ ... }:
{
  system.stateVersion = "26.05";
  boot.loader.grub.enable = false;
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
}
