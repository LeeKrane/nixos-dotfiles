# Public ingress: Caddy terminates TLS (Let's Encrypt, HTTP challenge on port 80) for the kept
# domains. The router forwards 80/443 here. Certificates are reissued on first start, so
# /var/lib/caddy is not backed up.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  lan = import ../../lib/lan.nix;
  inherit (import ../../lib/wireguard.nix) wg0;

  # Every vhost served on 443, from the config: a site address may list several, with a scheme
  # or a port (the Fritzbox proxy on 4242 is not a 443 site, so it is skipped).
  tlsHosts = lib.unique (
    lib.filter (h: !lib.hasInfix ":" h) (
      map (lib.removePrefix "https://") (
        lib.concatMap (lib.splitString ", ") (lib.attrNames config.services.caddy.virtualHosts)
      )
    )
  );
  # Resolved to this host, so the check needs no DNS. Auth-protected vhosts answer 401/403: any
  # status below 500 means Caddy and TLS work, 000 means no answer at all. Right after a boot a
  # backend can still be starting (CouchDB's container answered 502 nine seconds in), so a bad
  # answer is retried for about two minutes before it counts.
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

  # An upgrade is healthy only if Caddy still serves every 443 vhost over TLS.
  krane.autoUpgrade.healthChecks = [ "${caddyHealth}" ];

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
