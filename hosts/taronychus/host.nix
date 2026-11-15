# Raspberry Pi 5: implies system aarch64-linux and role "server" (see hostMeta in flake.nix).
{
  board = "rpi5";
  # Flashable image: packages.image-taronychus, written straight to the NVMe.
  image = "sd";
}
