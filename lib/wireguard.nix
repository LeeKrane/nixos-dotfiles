# WireGuard peer table for modules/nixos/server/wireguard.nix and the ssh host aliases in
# modules/home/common/cli.nix. Public keys only. Desktops keep their own wg0 client config
# (modules/nixos/desktop/networking.nix); this table only feeds servers.
{
  # wg0: hub-and-spoke network of all machines.
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
        publicKey = "cRsje9HjPg/GejOtG7cxpK+krqZMz/TkvpHDWR1VDxQ=";
      };
      tarritator = {
        ip = "192.168.82.3";
        publicKey = "H9Zgxh5DEKxfM/94eY3jIrfGio6rl1FzoPsXhw6MfVQ=";
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
      taryonyx = {
        ip = "192.168.82.7";
        publicKey = "K8fZU7WupZLJeXlRm9hYCysQPYc46E6My+/RUKakex0=";
      };
      taractias = {
        ip = "192.168.82.8";
        publicKey = "IScNK6RCHQHARQHG+XaZDs4aAHds5vPuEjKCFvKW5EM=";
      };
    };
    sshServers = [
      "taragarmr"
      "taronychus"
      "tarritator"
      "tarronax"
    ];
    desktopSsh = [
      "tariognatha"
      "tarmantria"
    ];
    desktopSshClients.tariognatha = [ "taryonyx" ];
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
