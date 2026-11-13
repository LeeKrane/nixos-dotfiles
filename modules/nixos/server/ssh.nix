# SSH access on servers. sshd itself (enable, keys only, no root login) comes from
# modules/nixos/common/users.nix, which exists so every host has an age-identity host key;
# servers only open port 22 and install the authorized keys.
#
# Login password: sudo needs the account's password (wheelNeedsPassword), so a server without
# one cannot be deployed to. The password is deliberately NOT in sops or the repo, not even as
# a hash: it is typed on site at install time (see each host's header). Because
# users.mutableUsers = true (common/users.nix), NixOS never overwrites an existing /etc/shadow
# entry on activation, so a password set with `passwd` persists across rebuilds.
{
  config,
  ...
}:
let
  user = config.krane.user.name;
in
{
  services.openssh.openFirewall = true;
  users.users.${user}.openssh.authorizedKeys.keys = builtins.attrValues (
    import ../../../lib/ssh-keys.nix
  );
}
