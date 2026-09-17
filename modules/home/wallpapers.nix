# Repo ships a default wallpaper; Pictures/Wallpapers stays a real directory so users can drop
# their own images in. ii's wallpaper picker reads $XDG_PICTURES_DIR/Wallpapers by default.
{
  home.file."Pictures/Wallpapers/nixos-wp.png".source = ../../assets/wallpapers/nixos-wp.png;
}
