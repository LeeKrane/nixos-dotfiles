{ pkgs, ... }:
{
  # install.sh's setup UI and `just check` need these without `nix develop`.
  environment.systemPackages = with pkgs; [
    just
    gum
    pv
  ];

  # The soymou module already inits starship.
  programs.starship.enable = false;

  # HM home.sessionVariables only reaches bash/zsh; fish is NixOS-managed, so it exports
  # SSH_AUTH_SOCK itself for the gcr ssh-agent.
  programs.fish.interactiveShellInit = ''
    set -gx SSH_AUTH_SOCK $XDG_RUNTIME_DIR/gcr/ssh
  '';
}
