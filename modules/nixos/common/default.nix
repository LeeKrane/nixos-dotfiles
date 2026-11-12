# NixOS modules every host needs, desktop or server. Desktop-only modules live in ../desktop,
# selected by lib/mk-host.nix from the host's role. GPU modules are host-specific, imported
# separately per host from ../gpu.
{ ... }:
{
  imports = [
    ./nix-settings.nix
    ./locale.nix
    ./users.nix
    ./user.nix
    ./keyboard.nix
    ./sops.nix
  ];
}
