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
    ./teamclaude.nix
    ./zsh-fallback.nix
  ];

  home.stateVersion = "26.05";
  home.username = kraneUser.name;
  # Derived from the username option; matches NixOS's mkDefault users.users.<name>.home.
  home.homeDirectory = "/home/${config.home.username}";
}
