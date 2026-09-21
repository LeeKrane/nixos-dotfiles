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
  # A Nix path, not a string, so `builtins.pathExists`/`sopsFile` get the
  # real store path.
  hostSecretsFile = ../../secrets/${hostName}.yaml;
  hostSecretsExist = builtins.pathExists hostSecretsFile;

  # sops encrypts values, not key names, so the top-level sections are readable at eval time.
  # A section absent from the file means that feature is off on this host; an empty value
  # cannot be detected (it is encrypted like any other).
  secretFileLines = lib.optionals hostSecretsExist (
    lib.splitString "\n" (builtins.readFile hostSecretsFile)
  );
  hasSection =
    name:
    lib.any (p: lib.any (lib.hasPrefix p) secretFileLines) [
      "${name}:"
      "\"${name}\":"
      "'${name}':"
    ];
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
    secrets =
      # Consumed by modules/nixos/networking.nix's wg0 template.
      lib.optionalAttrs (hasSection "wireguard") {
        "wireguard/wg0-private-key" = {
          owner = "root";
          mode = "0400";
        };
        "wireguard/address" = {
          owner = "root";
          mode = "0400";
        };
        "wireguard/listen-port" = {
          owner = "root";
          mode = "0400";
        };
        "wireguard/peer-public-key" = {
          owner = "root";
          mode = "0400";
        };
        "wireguard/peer-endpoint" = {
          owner = "root";
          mode = "0400";
        };
        "wireguard/peer-allowed-ips" = {
          owner = "root";
          mode = "0400";
        };
      }
      # Owned by krane, not root: copied verbatim into krane's own rclone.conf.
      // lib.optionalAttrs (hasSection "rclone") {
        "rclone/config-seed" = {
          owner = "krane";
          mode = "0400";
        };
      };

    # Renders wg0.conf from the six wireguard/* secrets above so no cleartext
    # tunnel value (address, peer identity, endpoint) lands in the repo.
    # Consumed by modules/nixos/networking.nix's networking.wg-quick.interfaces.wg0.
    templates = lib.optionalAttrs (hasSection "wireguard") {
      "wg0.conf" = {
        owner = "root";
        mode = "0400";
        content = ''
          [Interface]
          Address = ${config.sops.placeholder."wireguard/address"}
          ListenPort = ${config.sops.placeholder."wireguard/listen-port"}
          PrivateKey = ${config.sops.placeholder."wireguard/wg0-private-key"}

          [Peer]
          # taragarmr
          PublicKey = ${config.sops.placeholder."wireguard/peer-public-key"}
          Endpoint = ${config.sops.placeholder."wireguard/peer-endpoint"}
          AllowedIPs = ${config.sops.placeholder."wireguard/peer-allowed-ips"}
          PersistentKeepalive = 25
        '';
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
