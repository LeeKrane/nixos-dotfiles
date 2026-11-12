# NixOS modules for role "server" (headless). Boot loader and hardware are per host: taragarmr
# uses systemd-boot (UEFI), the Pis nixos-raspberrypi. Nothing here assumes either.
{ ... }:
{
  imports = [
    ./backup.nix
    ./base.nix
    ./docker.nix
    ./networking.nix
    ./ssh.nix
    ./zram.nix
  ];
}
