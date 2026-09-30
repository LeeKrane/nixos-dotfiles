{ pkgs }:
let
  ani-cli-launcher = pkgs.callPackage ./ani-cli-launcher/package.nix { };
in
{
  # Termux launcher entries for ani-cli (APK, unsigned) and the script that signs it, see
  # scripts/ani-cli-launcher.sh.
  inherit ani-cli-launcher;
  ani-cli-launcher-sign = ani-cli-launcher.sign;

  # Overrides nixpkgs' claude-code with the vendored copy, so its version
  # is set by pkgs/claude-code/manifest.zst.json rather than the nixpkgs pin.
  claude-code = pkgs.callPackage ./claude-code/package.nix { };
  krane-ii-settings = pkgs.callPackage ./krane-ii-settings { };

  anydoc = pkgs.callPackage ./anydoc/package.nix { };
  flake-update-notify = pkgs.callPackage ./flake-update-notify { };
  heuristiclab = pkgs.callPackage ./heuristiclab/package.nix { };
  plymouth-lone = pkgs.callPackage ./plymouth-lone { };
  proton-drive-mount = pkgs.callPackage ./proton-drive-mount { };
  server-upgrade = pkgs.callPackage ./server-upgrade { };
  skillspector = pkgs.callPackage ./skillspector/package.nix { };
  teamclaude = pkgs.callPackage ./teamclaude/package.nix { };
  voicestudio = pkgs.callPackage ./voicestudio/package.nix { };
}
