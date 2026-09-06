{
  config,
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
  ];

  home.stateVersion = "26.05";
  home.username = "krane";
  # The one absolute /home path this repo constructs, derived from the username option, not
  # hardcoded. No mkForce/mkDefault needed: NixOS already sets users.users.krane.home =
  # mkDefault "/home/krane" (users.nix), which HM copies into this option, the same value, so
  # they agree.
  home.homeDirectory = "/home/${config.home.username}";
}
