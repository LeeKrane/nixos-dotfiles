# SSH between the wg0.desktopSsh desktops over wg0 only: port 22 opens on wg0 alone, and each
# authorized key carries from= with the other desktop's wg0 address, so a stolen key is useless
# elsewhere.
{
  config,
  lib,
  hostName,
  ...
}:
let
  inherit (import ../../../lib/wireguard.nix) wg0;
  sshKeys = import ../../../lib/ssh-keys.nix;
  others = lib.remove hostName wg0.desktopSsh ++ wg0.desktopSshClients.${hostName} or [ ];
in
lib.mkIf (builtins.elem hostName wg0.desktopSsh) {
  networking.firewall.interfaces.${wg0.interface}.allowedTCPPorts = [ 22 ];
  # Only the keys below: a hand-added ~/.ssh/authorized_keys entry would skip from=.
  services.openssh.authorizedKeysInHomedir = false;
  users.users.${config.krane.user.name}.openssh.authorizedKeys.keys = map (
    n: ''from="${wg0.peers.${n}.ip}" ${sshKeys.${n}}''
  ) others;
}
