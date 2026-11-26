# The Pis have little RAM and no swap partition.
{ lib, ... }:
{
  zramSwap = {
    enable = true;
    memoryPercent = lib.mkDefault 50;
    algorithm = lib.mkDefault "zstd";
  };
}
