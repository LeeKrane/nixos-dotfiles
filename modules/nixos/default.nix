# Aggregate import for all NixOS modules. GPU modules are host-specific,
# imported separately per host.
{ ... }:
{
  imports = [
    ./nix-settings.nix
    ./hardware.nix
    ./locale.nix
    ./users.nix
    ./boot.nix
    ./networking.nix
    ./audio.nix
    ./bluetooth.nix
    ./peripherals.nix
    ./desktop.nix
    ./fonts.nix
    ./shells.nix
    ./virtualisation.nix
    ./gaming.nix
    ./flatpak.nix
    ./appimage.nix
    ./sops.nix
  ];
}
