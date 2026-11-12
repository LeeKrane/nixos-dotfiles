# The one human user account, named by krane.user.name (modules/nixos/common/user.nix).
{ config, pkgs, ... }:
{
  users.users.${config.krane.user.name} = {
    isNormalUser = true;
    shell = pkgs.fish;
    # Base groups only; desktop groups are added in modules/nixos/desktop/users.nix.
    extraGroups = [
      "wheel"
      "video"
      "audio"
    ];
  };

  security.sudo.wheelNeedsPassword = true;

  # Enabled only so sshd-keygen creates the host's age-identity key at
  # first boot. openFirewall stays false: this never listens for SSH.
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # No password hash is ever committed. The account's login password is set
  # once at install with `nixos-enter -- passwd <krane.user.name>`.
  users.mutableUsers = true;
}
