# The one human user account.
{ pkgs, ... }:
{
  # `i2c` group already exists via hardware.i2c.enable. `plugdev` is
  # declared here since it's just a side effect of zsa.enable elsewhere.
  users.groups.plugdev = { };

  users.users.krane = {
    isNormalUser = true;
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "input"
      "i2c"
      "docker"
      "libvirtd"
      "audio"
      "plugdev"
      # Required by peripherals.nix's programs.ydotool.enable, for uinput access.
      "ydotool"
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

  # No password hash is ever committed. krane's login password is set
  # once at install with `nixos-enter -- passwd krane`.
  users.mutableUsers = true;
}
