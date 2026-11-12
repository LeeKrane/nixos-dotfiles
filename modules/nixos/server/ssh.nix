# SSH access on servers. sshd itself (enable, keys only, no root login) comes from
# modules/nixos/common/users.nix, which exists so every host has an age-identity host key;
# servers only open port 22 and install the authorized keys.
{ config, ... }:
{
  services.openssh.openFirewall = true;

  users.users.${config.krane.user.name}.openssh.authorizedKeys.keys = builtins.attrValues (
    import ../../../lib/ssh-keys.nix
  );
}
