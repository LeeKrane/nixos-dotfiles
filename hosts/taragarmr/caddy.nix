# Public ingress: Caddy terminates TLS (Let's Encrypt, HTTP challenge on port 80) for the kept
# domains. The router forwards 80/443 here. Certificates are reissued on first start, so
# /var/lib/caddy is not backed up.
{ config, ... }:
let
  lan = import ../../lib/lan.nix;
  inherit (import ../../lib/wireguard.nix) wg0;
in
{
  services.caddy = {
    enable = true;
    # TODO: Let's Encrypt expiry mails go to krane.user.gitEmail until a dedicated address exists.
    email = config.krane.user.gitEmail;
    # Clients without SNI (an IP address in the browser) get the Fritzbox listener's cert.
    globalConfig = ''
      default_sni fritz.krane.dev
    '';

    virtualHosts = {
      # Obsidian LiveSync (hosts/taragarmr/couchdb.nix).
      "couch.krane.dev".extraConfig = ''
        encode zstd gzip
        header -Server
        reverse_proxy 127.0.0.1:5984
      '';

      # gym-league on taronychus, which accepts this host's LAN address (192.168.178.23) and wg0
      # address only.
      "api-gymleague.paulbankl.dev".extraConfig = ''
        reverse_proxy ${lan.hosts.taronychus}:8080
      '';

      # Fritzbox admin UI for the LAN and wg0 (firewall below), replacing the old nginx proxy
      # with its self-signed fritz.krane.dev certificate. `tls internal` is Caddy's own CA:
      # clients get a certificate warning until its root (/var/lib/caddy/.local/share/caddy/pki/
      # authorities/local/root.crt) is trusted. Like the nginx it keeps the client's Host header
      # (Caddy's default) and sets X-Forwarded-*.
      "https://fritz.krane.dev:4242, https://${lan.hosts.taragarmr}:4242, https://${wg0.hub.ip}:4242".extraConfig =
        ''
          tls internal
          reverse_proxy http://${lan.router}
        '';
    };
  };

  networking.firewall = {
    allowedTCPPorts = [
      80
      443
    ];
    allowedUDPPorts = [ 443 ];
    # 4242 (Fritzbox proxy): the LAN only; wg0 is a trusted interface already. The firewall
    # backend is iptables (networking.nftables is off), hence extraCommands, not extraInputRules.
    extraCommands = ''
      iptables -A nixos-fw -s ${lan.network} -p tcp --dport 4242 -j nixos-fw-accept
    '';
    extraStopCommands = ''
      iptables -D nixos-fw -s ${lan.network} -p tcp --dport 4242 -j nixos-fw-accept || true
    '';
  };
}
