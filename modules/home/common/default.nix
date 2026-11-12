# Home-manager modules every host needs, desktop or server. Desktop-only modules live in
# ../desktop, selected by lib/mk-host.nix from the host's role.
{
  config,
  kraneUser,
  ...
}:
{
  imports = [
    ./cli.nix
    ./git.nix
    ./neovim.nix
    ./zsh-fallback.nix
  ];

  home.stateVersion = "26.05";
  # krane.user.name from the NixOS side (modules/nixos/common/user.nix), handed in by
  # lib/mk-host.nix as the kraneUser specialArg.
  home.username = kraneUser.name;
  # The one absolute /home path this repo constructs, derived from the username option, not
  # hardcoded. No mkForce/mkDefault needed: NixOS already sets users.users.<name>.home =
  # mkDefault "/home/<name>" for users.nix's normal user, which HM copies into this option,
  # the same value, so they agree.
  home.homeDirectory = "/home/${config.home.username}";
}
