{ pkgs, ... }:
{
  # btop-cuda adds /run/opengl-driver/lib to the rpath so btop can dlopen libnvidia-ml.
  programs.btop.package = pkgs.btop-cuda;

  # gnome-keyring already runs the gcr ssh-agent (modules/nixos/desktop/desktop.nix). fish gets
  # SSH_AUTH_SOCK from modules/nixos/desktop/shells.nix; GUI clients get it through krane.hypr.env
  # (Hyprland starts without hm-session-vars).
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
  ];
}
