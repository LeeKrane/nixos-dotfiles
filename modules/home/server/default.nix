# Home-manager modules for role "server" (headless).
{ inputs, pkgs, ... }:
let
  unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [ ];

  # Claude Code plus the binaries its hooks call (~/.claude/settings.json runs `rtk hook claude`
  # and `codegraph prompt-hook`; plugin hooks and the claude-mem worker/MCP server need node
  # and bun). ~/.claude itself is a clone of the claude-dotfiles repo. The NixOS
  # session variable ANTHROPIC_BASE_URL (modules/nixos/common/claude.nix) points it at the
  # teamclaude proxy, which only taragarmr runs (hosts/taragarmr/services.nix); other hosts
  # need that proxy.
  home.packages = [
    pkgs.claude-code # vendored, from pkgs/claude-code via the overlay
    pkgs.rtk
    unstable.codegraph # not in nixpkgs 26.05
    pkgs.nodejs_22 # also provides npx (skills CLI)
    pkgs.bun
  ];
}
