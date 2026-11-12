# The login account's name and git identity, per host. Every module that names the
# account reads it from here (users.nix, desktop.nix, nix-settings.nix, sops.nix,
# lib/mk-host.nix, hosts/*/default.nix), and home-manager gets it as the `kraneUser`
# specialArg (lib/mk-host.nix). The defaults are the three original hosts' values;
# install.sh's new-host flow writes a `krane.user` block into hosts/<name>/default.nix.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.krane.user = {
    name = mkOption {
      # Same rule as install.sh's check_new_username.
      type = types.strMatching "[a-z_][a-z0-9_-]{0,31}";
      default = "krane";
      description = "Login account: users.users.<name>, home-manager.users.<name>, greetd autologin and nix trusted-users.";
    };
    gitName = mkOption {
      type = types.str;
      default = config.krane.user.name;
      defaultText = lib.literalExpression "config.krane.user.name";
      description = "git user.name for this host's account.";
    };
    gitEmail = mkOption {
      type = types.str;
      default = "chris@krane.dev";
      description = "git user.email for this host's account.";
    };
  };
}
