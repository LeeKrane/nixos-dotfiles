# SSH between the desktops listed in wg0.desktopSsh (lib/wireguard.nix), over wg0 only.
# sshd already runs on every host (modules/nixos/common/users.nix) with port 22 closed. Here
# port 22 opens on the wg0 interface alone, and each authorized key carries a from= option
# with the other desktop's wg0 address, so a stolen key is useless from anywhere else.
{
  config,
  lib,
  hostName,
  ...
}:
let
  inherit (import ../../../lib/wireguard.nix) wg0;
  sshKeys = import ../../../lib/ssh-keys.nix;
  others = lib.remove hostName wg0.desktopSsh;
in
lib.mkIf (builtins.elem hostName wg0.desktopSsh) {
  networking.firewall.interfaces.${wg0.interface}.allowedTCPPorts = [ 22 ];
  # Only the keys below: a hand-added ~/.ssh/authorized_keys entry would skip from=.
  services.openssh.authorizedKeysInHomedir = false;
  users.users.${config.krane.user.name}.openssh.authorizedKeys.keys = map (
    n: ''from="${wg0.peers.${n}.ip}" ${sshKeys.${n}}''
  ) others;
}
