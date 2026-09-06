# Language toolchains and dev CLIs. direnv is a NixOS-level `programs.direnv` module instead
# (modules/nixos/shells.nix), so it hooks fish's real init at /etc/fish, never wiped by ii.
{ pkgs, ... }:
{
  # jdk21 is also packaged below for Mason-free lspconfig/jdtls use. programs.java sets
  # JAVA_HOME too.
  programs.java = {
    enable = true;
    package = pkgs.jdk21;
  };

  home.packages = with pkgs; [
    # No standalone `corepack`: nodejs_22 already bundles bin/corepack (Node 16.9+), and adding
    # it separately collides in home-manager's buildEnv (found by the container build).
    nodejs_22
    bun
    pnpm
    yarn

    # No standalone `python3`: illogical-flake's own python3.withPackages env already owns
    # bin/python3 and collides in buildEnv (found by the container build). Use `uv` per-project.
    uv
    pipx
    virtualenv

    rustup
    jdk21

    # No `clang` alongside `gcc`: both ship bin/c++/bin/cc and collide in buildEnv the same way.
    # For clang-specific work use `nix shell nixpkgs#clang` or a devShell instead.
    gcc
    cmake
    gnumake

    docker-compose
    supabase-cli
    claude-code

    # scheme-medium (~1-2 GB) instead of scheme-full (~5 GB). Switch if a package is missing.
    # texlive.combined.* is deprecated for Nixpkgs 27.05. See docs/MIGRATION-NOTES.md.
    texlive.combined.scheme-medium
  ];
}
