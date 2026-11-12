# Desktop-only CLI extras. The shared CLI basics (bat, eza, fzf, ripgrep, ...) are in
# ../common/cli.nix.
{ pkgs, ... }:
{
  # btop-cuda adds /run/opengl-driver/lib to the rpath so btop can dlopen libnvidia-ml for the GPU box.
  # Plain definition beats common/cli.nix's mkDefault pkgs.btop.
  programs.btop.package = pkgs.btop-cuda;

  # Point ssh at the gcr ssh-agent component gnome-keyring already runs
  # (services.gnome.gnome-keyring.enable in modules/nixos/desktop/desktop.nix). ssh's
  # AddKeysToAgent is set in common/cli.nix. home.sessionVariables only reaches bash/zsh via
  # /etc/profile.d, so fish also gets SSH_AUTH_SOCK from
  # modules/nixos/desktop/shells.nix, and GUI-launched clients get it from
  # krane.hypr.env below (Hyprland is started by greetd without
  # hm-session-vars, same reasoning as modules/home/desktop/cursor.nix).
  home.sessionVariables.SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/gcr/ssh";
  krane.hypr.env.SSH_AUTH_SOCK = "/run/user/1000/gcr/ssh"; # hl.env is a literal string, no $VAR expansion

  home.packages = with pkgs; [
    imagemagick
    jpegoptim
    optipng
    toipe
    trivy
    scrcpy
    android-tools
    libnotify
    ani-cli
  ];
}
