{
  config,
  lib,
  pkgs,
  ...
}:
{
  users.users.${config.krane.user.name} = {
    isNormalUser = true;
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "video"
      "audio"
    ];
  };

  security.sudo.wheelNeedsPassword = true;

  # Enabled only so sshd-keygen creates the host's age-identity key at first boot. Servers
  # open port 22 in modules/nixos/server/ssh.nix.
  services.openssh = {
    enable = true;
    openFirewall = lib.mkDefault false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # No password is committed. Desktops: `nixos-enter -- passwd <user>` at install. Servers:
  # typed on site. mutableUsers keeps a password set with `passwd` across rebuilds.
  users.mutableUsers = true;
}
