# Where the ntfy server for the automatic server upgrades listens: taragarmr's WireGuard address
# (lib/wireguard.nix).
let
  hub = (import ./wireguard.nix).wg0.hub;
in
rec {
  host = hub.ip;
  port = 2586;
  topic = "server-upgrades";
  url = "http://${host}:${toString port}";
}
