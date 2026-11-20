# Home-manager modules for role "server" (headless).
{ inputs, pkgs, ... }:
let
  unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [ ];

  # Claude Code plus the binaries its hooks call (~/.claude/settings.json runs `rtk hook claude`
  # and `codegraph prompt-hook`). ~/.claude itself is copied over by hand. Its settings.json
  # points ANTHROPIC_BASE_URL at the teamclaude proxy, which only taragarmr runs
  # (hosts/taragarmr/services.nix); other hosts need that proxy or a settings override.
  home.packages = [
    pkgs.claude-code # vendored, from pkgs/claude-code via the overlay
    pkgs.rtk
    unstable.codegraph # not in nixpkgs 26.05
  ];
}
