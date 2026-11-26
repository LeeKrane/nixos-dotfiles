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

  programs.kdeconnect.enable = true;

  # Tunnel values live in secrets/<host>.yaml's wireguard section and render into a wg0.conf
  # template (configFile below). Gated on file and section existing: sops-nix validates every
  # declared key at build time.
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
      PublicKey = ${config.sops.placeholder."wireguard/peer-public-key"}
      Endpoint = ${config.sops.placeholder."wireguard/peer-endpoint"}
      AllowedIPs = ${config.sops.placeholder."wireguard/peer-allowed-ips"}
      PersistentKeepalive = 25
    '';
  };

  # Reads config.sops.templates, so the sops declarations gate on file contents only:
  # gating on config.networking.* would recurse.
  networking.wg-quick.interfaces.wg0 = lib.mkIf (config.sops.templates ? "wg0.conf") {
    configFile = config.sops.templates."wg0.conf".path;
    autostart = true;
  };

  # The peer endpoint is a hostname: at boot wg-quick can run before Wi-Fi/DNS is up and fail
  # with "Name or service not known".
  systemd.services.wg-quick-wg0 = lib.mkIf (config.sops.templates ? "wg0.conf") {
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  networking.hosts = lib.mkIf (config.sops.templates ? "wg0.conf") {
    "192.168.82.1" = [ "taragarmr" ];
  };
}
