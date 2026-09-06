# Installs appimage-run and registers the binfmt handler for one-off
# AppImages this repo does not package.
{ ... }:
{
  programs.appimage = {
    enable = true;
    # binfmt lets an AppImage run directly, not just via appimage-run.
    binfmt = true;
  };
}
