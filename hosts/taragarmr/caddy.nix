# Public ingress: Caddy terminates TLS (Let's Encrypt, HTTP challenge on port 80); the router
# forwards 80/443 here.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  lan = import ../../lib/lan.nix;
  inherit (import ../../lib/wireguard.nix) wg0;

  # Vhosts served on 443; entries with a port (the Fritzbox proxy on 4242) are skipped.
  tlsHosts = lib.unique (
    lib.filter (h: !lib.hasInfix ":" h) (
      map (lib.removePrefix "https://") (
        lib.concatMap (lib.splitString ", ") (lib.attrNames config.services.caddy.virtualHosts)
      )
    )
  );
  # Resolved to this host, so no DNS is needed. Auth-protected vhosts answer 401/403: any status
  # below 500 means Caddy and TLS work. A backend may still be starting after boot, so a bad
  # answer is retried for about two minutes.
  caddyHealth = pkgs.writeShellScript "caddy-health" ''
    for host in ${lib.escapeShellArgs tlsHosts}; do
      for _ in {1..24}; do
        code=$(${lib.getExe pkgs.curl} --resolve "$host:443:127.0.0.1" -s -o /dev/null --max-time 10 \
          -w '%{http_code}' "https://$host/") || true
        [ "$code" -ge 100 ] && [ "$code" -lt 500 ] && continue 2
        ${lib.getExe' pkgs.coreutils "sleep"} 5
      done
      echo "$host answered $code" >&2
      exit 1
    done
  '';
in
{
  services.caddy = {
    enable = true;
    # TODO: dedicated address; Let's Encrypt expiry mails go to gitEmail.
    email = config.krane.user.gitEmail;
    # Clients without SNI get the Fritzbox listener's cert.
    globalConfig = ''
      default_sni fritz.krane.dev
    '';

    virtualHosts = {
      "couch.krane.dev".extraConfig = ''
        encode zstd gzip
        header -Server
        reverse_proxy 127.0.0.1:5984
      '';

      # Fritzbox admin UI for the LAN and wg0. `tls internal` is Caddy's own CA: clients warn until
      # /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt is trusted.
      "https://fritz.krane.dev:4242, https://${lan.hosts.taragarmr}:4242, https://${wg0.hub.ip}:4242".extraConfig =
        ''
          tls internal
          reverse_proxy http://${lan.router}
        '';
    };
  };

  krane.autoUpgrade.healthChecks = [ "${caddyHealth}" ];

  networking.firewall = {
    allowedTCPPorts = [
      80
      443
    ];
    allowedUDPPorts = [ 443 ];
    # 4242 (Fritzbox proxy): LAN only; wg0 is trusted already. extraCommands because the firewall
    # backend is iptables.
    extraCommands = ''
      iptables -A nixos-fw -s ${lan.network} -p tcp --dport 4242 -j nixos-fw-accept
    '';
    extraStopCommands = ''
      iptables -D nixos-fw -s ${lan.network} -p tcp --dport 4242 -j nixos-fw-accept || true
    '';
  };
}
