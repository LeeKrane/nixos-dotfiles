# Raspberry Pi 5: implies system aarch64-linux and role "server" (see hostMeta in flake.nix).
{
  board = "rpi5";
  # Flashable SD image: packages.image-tarritator.
  image = "sd";
}
