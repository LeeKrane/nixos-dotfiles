{ pkgs }:
{
  # Overrides nixpkgs' claude-code with the vendored copy, so its version
  # is set by pkgs/claude-code/manifest.zst.json rather than the nixpkgs pin.
  claude-code = pkgs.callPackage ./claude-code/package.nix { };

  anydoc = pkgs.callPackage ./anydoc/package.nix { };
  flake-update-notify = pkgs.callPackage ./flake-update-notify { };
  heuristiclab = pkgs.callPackage ./heuristiclab/package.nix { };
  plymouth-lone = pkgs.callPackage ./plymouth-lone { };
  proton-drive-mount = pkgs.callPackage ./proton-drive-mount { };
  skillspector = pkgs.callPackage ./skillspector/package.nix { };
  teamclaude = pkgs.callPackage ./teamclaude/package.nix { };
  voicestudio = pkgs.callPackage ./voicestudio/package.nix { };
}
