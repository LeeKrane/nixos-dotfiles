# The read-only ntfy token that modules/home/desktop/server-upgrade-notify.nix subscribes with,
# owned by the login account. Declared only when the host's secrets file has the `ntfy`
# section, like every sops declaration here: sops-nix validates each declared key at build time.
{
  config,
  lib,
  hostName,
  ...
}:
let
  hasNtfy = (import ../../../lib/host-secrets.nix { inherit lib hostName; }).hasSection "ntfy";
in
{
  sops.secrets = lib.mkIf hasNtfy {
    "ntfy/read-token" = {
      owner = config.krane.user.name;
      mode = "0400";
    };
  };
}
