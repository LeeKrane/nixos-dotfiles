# SSH access on servers. sshd itself (enable, keys only, no root login) comes from
# modules/nixos/common/users.nix, which exists so every host has an age-identity host key;
# servers only open port 22 and install the authorized keys.
#
# Login password: sudo needs the account's password (wheelNeedsPassword), so a server without
# one cannot be deployed to. It is the sops secret `users/krane-password-hash` (a yescrypt
# hash, `mkpasswd -m yescrypt`; section `users` in secrets/<host>.yaml), decrypted early
# (neededForUsers) with the pre-placed SSH host key. With users.mutableUsers = true (common/
# users.nix) NixOS applies hashedPasswordFile only when the user's /etc/shadow entry is
# created, i.e. on a fresh install or first boot of an image; later activations keep whatever
# `passwd` set. Rotating the hash in sops does not change an installed host. Without the
# section the account has no password and the config still evaluates.
{
  config,
  lib,
  hostName,
  ...
}:
let
  hostSecrets = import ../../../lib/host-secrets.nix { inherit lib hostName; };
  user = config.krane.user.name;
in
{
  services.openssh.openFirewall = true;
  users.users.${user} = {
    openssh.authorizedKeys.keys = builtins.attrValues (import ../../../lib/ssh-keys.nix);
  }
  // lib.optionalAttrs (hostSecrets.hasSection "users") {
    hashedPasswordFile = config.sops.secrets."users/krane-password-hash".path;
  };
  sops.secrets = lib.mkIf (hostSecrets.hasSection "users") {
    "users/krane-password-hash".neededForUsers = true;
  };
}
