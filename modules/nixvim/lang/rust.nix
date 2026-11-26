# rust-analyzer comes from rustup (modules/home/desktop/dev.nix);
# rustaceanvim would otherwise pull nixpkgs' rust-analyzer onto PATH.
{ pkgs, ... }:
{
  dependencies.rust-analyzer.enable = false;

  plugins.rustaceanvim = {
    enable = true;
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
