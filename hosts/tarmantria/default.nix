{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/nixos/gpu/nvidia-prime.nix
  ];

  system.stateVersion = "26.05";

  # display.nix sets krane.hypr.*, a home-manager module, imported at the user level.
  home-manager.users.krane.imports = [ ./display.nix ];

  # PCI bus IDs from `lspci | grep -E 'VGA|3D'`. FILL AT INSTALL: these placeholders are
  # almost certainly wrong for the actual laptop.
  krane.prime.intelBusId = "PCI:0:2:0"; # FILL AT INSTALL
  krane.prime.nvidiaBusId = "PCI:1:0:0"; # FILL AT INSTALL
}
