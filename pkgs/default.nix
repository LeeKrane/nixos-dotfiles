{ pkgs }:
{
  plymouth-lone = pkgs.callPackage ./plymouth-lone { };
  proton-drive-mount = pkgs.callPackage ./proton-drive-mount { };
}
