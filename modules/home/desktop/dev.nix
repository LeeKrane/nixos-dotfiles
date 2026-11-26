# direnv is NixOS-level (modules/nixos/common/shells.nix), so it hooks /etc/fish, which ii never wipes.
{ pkgs, ... }:
{
  programs.java = {
    enable = true;
    package = pkgs.jdk21;
  };

  home.packages = with pkgs; [
    # No standalone corepack: nodejs_22 bundles it and a second copy collides in buildEnv.
    nodejs_22
    bun
    pnpm
    yarn

    # No standalone python3: illogical-flake's python3.withPackages env owns bin/python3 and collides in buildEnv.
    uv
    pipx
    virtualenv

    rustup
    go
    jdk21

    # metals is for Zed's Scala extension; nixvim bundles its own (lang/scala.nix).
    sbt
    scala-cli
    metals
    scalafmt

    # No clang: collides with gcc on bin/cc and bin/c++ in buildEnv.
    gcc
    cmake
    gnumake

    docker-compose
    supabase-cli
    claude-code
    rtk # Claude Code hooks
    codegraph # Claude Code hooks
    anydoc # converts office docs and PDFs to Markdown for Claude Code
    skillspector # scans Claude Code skills for security issues before install

    # scheme-medium (~1-2 GB) instead of scheme-full (~5 GB).
    texliveMedium
  ];
}
