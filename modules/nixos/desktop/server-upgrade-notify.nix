# Declared only when the host's secrets file has the `ntfy` section: sops-nix validates every
# declared key at build time.
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
