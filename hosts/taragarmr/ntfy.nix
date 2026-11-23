# ntfy for the automatic server upgrades (modules/nixos/server/auto-upgrade.nix): failure and
# recovery pushes to the phone and the desktops. Listens only on the WireGuard address, no
# Caddy vhost; wg0 is a trusted firewall interface (modules/nixos/server/wireguard.nix), so
# the port is reachable there and nowhere else. Everything is denied by default; two
# provisioned users each get one right on the topic, so a leaked token can do one thing:
#   upgrade-publisher  write-only  token on the servers (ntfy/publish-token)
#   krane              read-only   token on the desktops (ntfy/read-token), password on the phone
# Users, ACLs and tokens are provisioned declaratively (ntfy 2.26: NTFY_AUTH_USERS,
# NTFY_AUTH_ACCESS, NTFY_AUTH_TOKENS) from the sops secret ntfy/server-env, so no CLI step on
# the host. See secrets/README.md for how to generate the values.
{
  config,
  lib,
  hostName,
  ...
}:
let
  ntfy = import ../../lib/ntfy.nix;
  hasEnv = (import ../../lib/host-secrets.nix { inherit lib hostName; }).hasSection "ntfy";
in
{
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = ntfy.url;
      listen-http = "${ntfy.host}:${toString ntfy.port}";
      auth-default-access = "deny-all";
    };
    environmentFile = lib.mkIf hasEnv config.sops.secrets."ntfy/server-env".path;
  };

  sops.secrets = lib.mkIf hasEnv {
    "ntfy/server-env" = {
      owner = "root";
      mode = "0400";
    };
  };

  # The listen address belongs to wg0, which comes up after the network; retry until it does.
  systemd.services.ntfy-sh = {
    after = [ "wg-quick-wg0.service" ];
    wants = [ "wg-quick-wg0.service" ];
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
