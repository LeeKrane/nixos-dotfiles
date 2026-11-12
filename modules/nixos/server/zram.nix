# Compressed swap in RAM. Kept on servers: the Pis have little RAM and no swap partition, and
# zram costs nothing when idle. Half of RAM (the desktop uses 100% plus sysctl tuning); hosts
# override memoryPercent.
{ lib, ... }:
{
  zramSwap = {
    enable = true;
    memoryPercent = lib.mkDefault 50;
    algorithm = lib.mkDefault "zstd";
  };
}
