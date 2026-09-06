# LazyVim config (config/nvim) wired up declaratively via per-file xdg.configFile symlinks, not
# the whole directory, so lazy-lock.json stays mutable for `:Lazy` to write. Also installs the
# LSP servers and formatters lua/plugins/*.lua and lazyvim.json "extras" expect on $PATH. Mason
# is disabled in nix.lua so these packages, not Mason's downloads, are what lspconfig finds.
{
  pkgs,
  ...
}:
{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  # Per-file symlinks, not a whole-directory source, so lazy-lock.json (which LazyVim rewrites
  # on every plugin update) stays a normal mutable file instead of a read-only store symlink.
  xdg.configFile = {
    "nvim/init.lua".source = ../../config/nvim/init.lua;
    "nvim/lua".source = ../../config/nvim/lua;
    "nvim/lazyvim.json".source = ../../config/nvim/lazyvim.json;
    "nvim/stylua.toml".source = ../../config/nvim/stylua.toml;
    "nvim/.neoconf.json".source = ../../config/nvim/.neoconf.json;
  };

  home.packages = with pkgs; [
    tree-sitter

    # lua
    lua-language-server
    stylua

    # nix
    nixd
    nixfmt-rfc-style # same derivation as pkgs.nixfmt under nixpkgs' new name, kept for readability at the call site

    # web / json / yaml / tailwind
    vscode-langservers-extracted
    tailwindcss-language-server
    yaml-language-server

    # typescript
    typescript-language-server

    # python
    pyright
    ruff

    # No standalone `rust-analyzer`: it collides with rustup's bundled proxy in buildEnv, so
    # rustup wins (parity with the existing setup). Run `rustup component add rust-analyzer`
    # after install.
    taplo

    # markdown / docker / java / tex
    marksman
    dockerfile-language-server # renamed from dockerfile-language-server-nodejs in nixpkgs
    jdt-language-server
    texlab
  ];
}
