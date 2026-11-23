# Where the ntfy server for the automatic server upgrades listens: taragarmr's WireGuard
# address (lib/wireguard.nix), never a public address. Shared by hosts/taragarmr/ntfy.nix (the
# server), modules/nixos/server/auto-upgrade.nix (publishers) and the desktops' subscriber.
let
  hub = (import ./wireguard.nix).wg0.hub;
in
rec {
  host = hub.ip;
  port = 2586;
  topic = "server-upgrades";
  url = "http://${host}:${toString port}";
}
