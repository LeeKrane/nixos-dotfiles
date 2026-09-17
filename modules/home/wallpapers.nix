# Every image in assets/wallpapers is linked; recursive keeps the directory real so users can
# drop their own images in. ii's wallpaper picker reads $XDG_PICTURES_DIR/Wallpapers by default.
{
  home.file."Pictures/Wallpapers" = {
    source = ../../assets/wallpapers;
    recursive = true;
  };
}
