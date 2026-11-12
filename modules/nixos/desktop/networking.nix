# Network stack: NetworkManager, firewall, mDNS, KDE Connect, wg0 template.
{
  config,
  lib,
  hostName,
  ...
}:
let
  hostSecrets = import ../../../lib/host-secrets.nix { inherit lib hostName; };
  hasWireguard = hostSecrets.exists && hostSecrets.hasSection "wireguard";
in
{
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  # Opens its own firewall range. No manual firewall rules needed.
  programs.kdeconnect.enable = true;

  # Tunnel values (address, peer identity, endpoint, keys) live encrypted in
  # secrets/<host>.yaml's wireguard section, never in this file. They are declared
  # here (desktops are wg0 clients of taragarmr; servers get none of this) and
  # rendered into a wg0.conf template consumed below as configFile, so nothing but the
  # fixed keepalive is cleartext. Like all sops declarations, gated on the file and
  # section existing: sops-nix validates every declared key at build time.
  sops.secrets = lib.mkIf hasWireguard (
    lib.genAttrs
      (map (k: "wireguard/${k}") [
        "wg0-private-key"
        "address"
        "listen-port"
        "peer-public-key"
        "peer-endpoint"
        "peer-allowed-ips"
      ])
      (_: {
        owner = "root";
        mode = "0400";
      })
  );

  sops.templates."wg0.conf" = lib.mkIf hasWireguard {
    owner = "root";
    mode = "0400";
    content = ''
      [Interface]
      Address = ${config.sops.placeholder."wireguard/address"}
      ListenPort = ${config.sops.placeholder."wireguard/listen-port"}
      PrivateKey = ${config.sops.placeholder."wireguard/wg0-private-key"}

      [Peer]
      # taragarmr
      PublicKey = ${config.sops.placeholder."wireguard/peer-public-key"}
      Endpoint = ${config.sops.placeholder."wireguard/peer-endpoint"}
      AllowedIPs = ${config.sops.placeholder."wireguard/peer-allowed-ips"}
      PersistentKeepalive = 25
    '';
  };

  # Gated on the template existing: hosts with no `wireguard:` section in
  # secrets/<host>.yaml get no template and no wg0 interface.
  # Reads config.sops.templates: keep sops.secrets/templates gated on file
  # contents only (hasWireguard), never on config.networking.*, or this recurses.
  networking.wg-quick.interfaces.wg0 = lib.mkIf (config.sops.templates ? "wg0.conf") {
    configFile = config.sops.templates."wg0.conf".path;
    autostart = true;
  };

  # The peer endpoint is a hostname: at boot wg-quick can run before Wi-Fi/DNS
  # is up and fail with "Name or service not known". Keep retrying instead.
  systemd.services.wg-quick-wg0 = lib.mkIf (config.sops.templates ? "wg0.conf") {
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # WireGuard peer name for the tunnel server; only meaningful when wg0 is up.
  networking.hosts = lib.mkIf (config.sops.templates ? "wg0.conf") {
    "192.168.82.1" = [ "taragarmr" ];
  };
}
