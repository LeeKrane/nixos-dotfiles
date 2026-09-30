{
  config,
  kraneUser,
  ...
}:
{
  imports = [
    ./hypr-config.nix
    ./illogical-impulse.nix
    ./git.nix
    ./cli.nix
    ./neovim.nix
    ./dev.nix
    ./apps.nix
    ./zsh-fallback.nix
    ./proton-drive.nix
    ./fallback-vendoring.nix
    ./wallpapers.nix
    ./lock-on-start.nix
    ./cursor.nix
    ./session-target.nix
    ./qwertz-binds.nix
    ./recording.nix
    ./teamclaude.nix
    ./steam.nix
  ];

  home.stateVersion = "26.05";
  # krane.user.name from the NixOS side (modules/nixos/user.nix), handed in by
  # lib/mk-host.nix as the kraneUser specialArg.
  home.username = kraneUser.name;
  # The one absolute /home path this repo constructs, derived from the username option, not
  # hardcoded. No mkForce/mkDefault needed: NixOS already sets users.users.<name>.home =
  # mkDefault "/home/<name>" for users.nix's normal user, which HM copies into this option,
  # the same value, so they agree.
  home.homeDirectory = "/home/${config.home.username}";
}
