# sops-nix wiring: decrypts per-host secrets from age keys derived from
# each host's own SSH host key. See secrets/README.md.
#
# `hostName` is the mk-host.nix specialArg, not `config.networking.hostName`:
# tariognatha-vm overrides the latter but shares tariognatha's secrets file.
{
  lib,
  pkgs,
  hostName,
  ...
}:
let
  # A Nix path, not a string, so `builtins.pathExists`/`sopsFile` get the
  # real store path.
  hostSecretsFile = ../../secrets/${hostName}.yaml;
  hostSecretsExist = builtins.pathExists hostSecretsFile;
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

    secrets = {
      # Consumed by modules/nixos/networking.nix's wg0 template.
      "wireguard/wg0-private-key" = {
        owner = "root";
        mode = "0400";
      };

      # Owned by krane, not root: copied verbatim into krane's own rclone.conf.
      "rclone/config-seed" = {
        owner = "krane";
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
