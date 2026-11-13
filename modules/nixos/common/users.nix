# The one human user account, named by krane.user.name (modules/nixos/common/user.nix).
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
    # Base groups only; desktop groups are added in modules/nixos/desktop/users.nix.
    extraGroups = [
      "wheel"
      "video"
      "audio"
    ];
  };

  security.sudo.wheelNeedsPassword = true;

  # Enabled only so sshd-keygen creates the host's age-identity key at
  # first boot. openFirewall stays false here (mkDefault): desktops never listen for SSH; servers
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

  # No password is ever committed (no plaintext, no hash, not even in sops). Desktops: set once
  # at install with `nixos-enter -- passwd <krane.user.name>`. Servers: typed on site at
  # install (see the host headers). mutableUsers = true keeps a password set with `passwd`
  # across rebuilds.
  users.mutableUsers = true;
}
