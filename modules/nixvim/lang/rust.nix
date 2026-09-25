# Rust via rustaceanvim. rust-analyzer comes from rustup (modules/home/dev.nix), never nixpkgs:
# rustaceanvim would otherwise pull nixpkgs' rust-analyzer onto PATH.
{
  dependencies.rust-analyzer.enable = false;

  plugins.rustaceanvim = {
    enable = true;
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
