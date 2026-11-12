# sops-nix wiring: decrypts per-host secrets from age keys derived from
# each host's own SSH host key. See secrets/README.md.
#
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
    # Every host decrypts with its own SSH host key, no separate age identity needed.
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  }
  # Gated on the secrets file existing: sops-nix validates every sopsFile
  # even if unused, failing `nix flake check` on a fresh checkout otherwise.
  // lib.optionalAttrs hostSecretsExist {
    defaultSopsFile = hostSecretsFile;

    # Each declaration is also gated on its own top-level section being present:
    # sops-nix validates every declared key at build time, and a section a host
    # doesn't use would otherwise fail the build.
    # Owned by the login account (krane.user.name), not root: copied verbatim into
    # that account's own rclone.conf. The wireguard secrets are declared by
    # modules/nixos/desktop/networking.nix.
    secrets = lib.optionalAttrs (hasSection "rclone") {
      "rclone/config-seed" = {
        owner = config.krane.user.name;
        mode = "0400";
      };
    };
  };

  # Also on $PATH on the installed system for scripts/bootstrap-sops.sh
  # and day-to-day `sops secrets/<host>.yaml` edits.
  environment.systemPackages = [
    pkgs.sops
    pkgs.age
    pkgs.ssh-to-age
  ];
}
