{ pkgs }:
{
  # Overrides nixpkgs' claude-code with the vendored copy, so its version
  # is set by pkgs/claude-code/manifest.zst.json rather than the nixpkgs pin.
  claude-code = pkgs.callPackage ./claude-code/package.nix { };

  plymouth-lone = pkgs.callPackage ./plymouth-lone { };
  proton-drive-mount = pkgs.callPackage ./proton-drive-mount { };
  teamclaude = pkgs.callPackage ./teamclaude/package.nix { };
}
