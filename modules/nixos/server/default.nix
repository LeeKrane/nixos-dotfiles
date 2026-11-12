# NixOS modules for role "server" (headless). Boot loader and hardware are per host: taragarmr
# uses systemd-boot (UEFI), the Pis nixos-raspberrypi. Nothing here assumes either.
{ ... }:
{
  imports = [
    ./networking.nix
    ./zram.nix
  ];
}
