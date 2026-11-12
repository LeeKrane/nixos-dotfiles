# Raspberry Pi 4: implies system aarch64-linux and role "server" (see hostMeta in flake.nix).
{
  board = "rpi4";
  # Flashable SD image: packages.image-tarronax.
  image = "sd";
}
