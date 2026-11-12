# NixOS modules for role "desktop" (Hyprland, audio, gaming, ...).
{ ... }:
{
  imports = [
    ./hardware.nix
    ./boot.nix
    ./networking.nix
    ./audio.nix
    ./bluetooth.nix
    ./peripherals.nix
    ./desktop.nix
    ./fonts.nix
    ./shells.nix
    ./users.nix
    ./virtualisation.nix
    ./gaming.nix
    ./recording.nix
    ./flatpak.nix
    ./appimage.nix
  ];
}
