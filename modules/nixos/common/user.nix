{ config, lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.krane.user = {
    name = mkOption {
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
