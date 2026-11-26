# recursive keeps the directory real so users can add their own images. ii's picker reads
# $XDG_PICTURES_DIR/Wallpapers.
{
  home.file."Pictures/Wallpapers" = {
    source = ../../../assets/wallpapers;
    recursive = true;
  };
}
