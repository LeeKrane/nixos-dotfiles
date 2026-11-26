# ntfy for the automatic server upgrades (modules/nixos/server/auto-upgrade.nix): failure and
# recovery pushes. Listens only on the WireGuard address (wg0 is a trusted interface), no Caddy
# vhost. Deny by default; two users each get one right on the topic:
#   upgrade-publisher  write-only  token on the servers (ntfy/publish-token)
#   krane              read-only   token on the desktops (ntfy/read-token), password on the phone
# Users, ACLs and tokens come from the sops secret ntfy/server-env (NTFY_AUTH_USERS,
# NTFY_AUTH_ACCESS, NTFY_AUTH_TOKENS); see secrets/README.md.
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
