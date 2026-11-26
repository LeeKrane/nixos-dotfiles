# `hostName` is the mk-host.nix specialArg, not `config.networking.hostName`:
# tariognatha-vm overrides the latter but shares tariognatha's secrets file.
{
  config,
  lib,
  pkgs,
  hostName,
  ...
}:
let
  secrets = import ../../../lib/host-secrets.nix { inherit lib hostName; };
  inherit (secrets) hasSection;
  hostSecretsFile = secrets.file;
  hostSecretsExist = secrets.exists;
in
{
  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  }
  # sops-nix validates every sopsFile, so gate on the file existing.
  // lib.optionalAttrs hostSecretsExist {
    defaultSopsFile = hostSecretsFile;

    # Gated per section too: sops-nix validates every declared key at build time.
    # Owned by the login account: copied into its rclone.conf.
    secrets =
      lib.optionalAttrs (hasSection "rclone") {
        "rclone/config-seed" = {
          owner = config.krane.user.name;
          mode = "0400";
        };
      }
      // lib.optionalAttrs (hasSection "ani-cli") {
        "ani-cli/curl-auth" = {
          owner = config.krane.user.name;
          mode = "0400";
        };
      };
  };

  environment.systemPackages = [
    pkgs.sops
    pkgs.age
    pkgs.ssh-to-age
  ];
}
