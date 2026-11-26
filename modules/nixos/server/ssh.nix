# sudo needs the account's password (wheelNeedsPassword), so deploys need one. It is not in sops
# or the repo; it is typed on site at install (see each host's header). mutableUsers = true
# (common/users.nix) keeps a password set with `passwd` across rebuilds.
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
