{ inputs, pkgs, ... }:
let
  unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [ ];

  # Claude Code plus what its hooks call (`rtk hook claude`, `codegraph prompt-hook`; node and bun
  # for plugin hooks and the claude-mem worker/MCP server).
  home.packages = [
    pkgs.claude-code
    pkgs.rtk
    unstable.codegraph # not in nixpkgs 26.05
    pkgs.nodejs_22 # also provides npx (skills CLI)
    pkgs.bun
  ];
}
