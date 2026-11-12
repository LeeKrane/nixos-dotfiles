# WireGuard peer table for modules/nixos/server/wireguard.nix and the ssh host aliases in
# modules/home/common/cli.nix. Public keys only, and no peer's public endpoint IP. The
# private keys live in secrets/<host>.yaml (wireguard/wg0-private-key, wireguard/wg1-private-key).
#
# Not under hosts/: every directory there is a host. Desktops keep their own wg0 client
# config from secrets (modules/nixos/desktop/networking.nix), this table only feeds servers.
{
  # wg0: the hub-and-spoke network of all machines. Every peer reaches every other one
  # through the hub, which forwards between them.
  wg0 = {
    network = "192.168.82.0/24";
    prefixLength = 24;
    interface = "wg0";
    endpoint = "wg.krane.dev:13231";
    hub = {
      name = "taragarmr";
      ip = "192.168.82.1";
      listenPort = 13231;
      publicKey = "+OYINXtWTR6kIPSeCpWQUQKmVqkuJAQzNfGr0a3E3yc=";
    };
    peers = {
      taronychus = {
        ip = "192.168.82.2";
        publicKey = "ZofEjXMSywPlOFByfa4XOa7StMVxsvotY+K2CxkTDRA=";
      };
      tarritator = {
        ip = "192.168.82.3";
        publicKey = "A0IBd3i6msVUI0J58jQ6FhqeFpBr9jsrVOr5emfhrUw=";
      };
      tarronax = {
        ip = "192.168.82.4";
        publicKey = "ipzkgDDEwlzek50bneRP8dNv1iPUHy/9XIVRDG8JxjE=";
      };
      tariognatha = {
        ip = "192.168.82.5";
        publicKey = "OOptZa5DitDzRtMR6vQAeGcy8MMX8N0NXrkaarcQwVI=";
      };
      tarmantria = {
        ip = "192.168.82.6";
        publicKey = "CteLK18EBm4MBlzBhCBAjhGGjSqEmClTDbjJoSXa0XU=";
      };
      # Android phone, not a NixOS host.
      taryonyx = {
        ip = "192.168.82.7";
        publicKey = "K8fZU7WupZLJeXlRm9hYCysQPYc46E6My+/RUKakex0=";
      };
      taractias = {
        ip = "192.168.82.8";
        publicKey = "IScNK6RCHQHARQHG+XaZDs4aAHds5vPuEjKCFvKW5EM=";
      };
    };
    # Machines that run sshd for the login account; home-manager adds a `Host` alias for
    # each so desktops reach them over wg0.
    sshServers = [
      "taragarmr"
      "taronychus"
      "tarritator"
      "tarronax"
    ];
  };

  # wg1: hub-only network for the Fika/SPT players. Brought up by hand on the hub.
  wg1 = {
    network = "192.168.83.0/24";
    prefixLength = 24;
    interface = "wg1";
    hub = {
      name = "taragarmr";
      ip = "192.168.83.1";
      listenPort = 51821;
      publicKey = "0UgcSv10EJYyRQq+hIZNjhW40CukVZ01QQD0cF+kgxA=";
    };
    peers = {
      peer1 = {
        ip = "192.168.83.2";
        publicKey = "NXtYQkGSsJbqJY6wT1zdGGzUiREf23yuQoxrZB7dbzQ=";
      };
      peer2 = {
        ip = "192.168.83.3";
        publicKey = "FyhIxRSx8mGsseGHP1hmiIl/G5E1Ep08mZxGwLILXH8=";
      };
      peer3 = {
        ip = "192.168.83.4";
        publicKey = "DQqTrUWnJ1gz4kqkeDwbk4EtWmya++8e6MH5I2TpmlQ=";
      };
      peer4 = {
        ip = "192.168.83.5";
        publicKey = "lQHnOedJio/kSNG/lmgamUZtKYy74e9dHlCIT0PceVI=";
      };
    };
  };
}
