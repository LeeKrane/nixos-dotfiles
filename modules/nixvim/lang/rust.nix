# Rust via rustaceanvim. rust-analyzer comes from rustup (modules/home/desktop/dev.nix), never nixpkgs:
# rustaceanvim would otherwise pull nixpkgs' rust-analyzer onto PATH.
{ pkgs, ... }:
{
  dependencies.rust-analyzer.enable = false;

  plugins.rustaceanvim = {
    enable = true;
    # rustaceanvim 9.2.2's busted suite fails under neovim 0.12.6 (lsp_spec.lua:
    # "Invalid 'buf': Expected Lua number"). Checks skip only for 9.2.2, so any
    # nixpkgs bump re-enables them. Remove this override once a newer version builds.
    package = pkgs.vimPlugins.rustaceanvim.overrideAttrs (old: {
      doCheck = builtins.head (pkgs.lib.splitString "-" old.version) != "9.2.2";
    });
    settings.server.default_settings.rust-analyzer = {
      cargo.allFeatures = true;
      check.command = "clippy";
      procMacro.enable = true;
    };
  };

  plugins.crates = {
    enable = true;
    settings = {
      # In-process LSP: completion/hover/code actions reach blink via the LSP
      # source (the nvim-cmp source is unused). completion.crates also feeds
      # the LSP completion (crates.nvim lua/crates/completion/common.lua).
      lsp = {
        enabled = true;
        actions = true;
        completion = true;
        hover = true;
      };
      completion.crates.enabled = true;
    };
    lazyLoad.settings.event = [ "BufRead Cargo.toml" ];
  };
}
