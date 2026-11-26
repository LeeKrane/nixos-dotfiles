{ ... }:
{
  imports = [
    ./nix-settings.nix
    ./locale.nix
    ./users.nix
    ./user.nix
    ./keyboard.nix
    ./sops.nix
    ./shells.nix
    ./claude.nix
  ];
}
