# Desktop-only shell bits. fish itself, its aliases and direnv are in ../common/shells.nix.
{ pkgs, ... }:
{
  # `just`/`gum` on the installed system too, since install.sh's setup UI
  # and `just check` need them without `nix develop`.
  environment.systemPackages = with pkgs; [
    just
    gum
    pv
  ];

  # Explicit false: the soymou module's starship already inits the
  # prompt. A second one here would double-init.
  programs.starship.enable = false;

  # home-manager's home.sessionVariables (modules/home/desktop/cli.nix) only reaches
  # bash/zsh via /etc/profile.d; fish is NixOS-managed, so it needs its own
  # SSH_AUTH_SOCK export to reach the gcr ssh-agent gnome-keyring runs.
  programs.fish.interactiveShellInit = ''
    set -gx SSH_AUTH_SOCK $XDG_RUNTIME_DIR/gcr/ssh
  '';
}
