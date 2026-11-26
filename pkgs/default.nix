{ pkgs }:
let
  ani-cli-launcher = pkgs.callPackage ./ani-cli-launcher/package.nix { };
in
{
  inherit ani-cli-launcher;
  ani-cli-launcher-sign = ani-cli-launcher.sign;

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
