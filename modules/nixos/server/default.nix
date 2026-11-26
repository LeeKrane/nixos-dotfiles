{ ... }:
{
  imports = [
    ./auto-upgrade.nix
    ./backup.nix
    ./base.nix
    ./docker.nix
    ./networking.nix
    ./prompt.nix
    ./ssh.nix
    ./wireguard.nix
    ./zram.nix
  ];
}
