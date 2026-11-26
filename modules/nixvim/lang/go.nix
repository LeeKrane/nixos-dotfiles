{ pkgs, ... }:
{
  lsp.servers.gopls = {
    enable = true;
    config.settings.gopls = {
      gofumpt = true;
      usePlaceholders = true;
      staticcheck = true;
      analyses.unusedparams = true;
    };
  };

  # gopls uses the go from modules/home/desktop/dev.nix, not one bundled here.
  dependencies.go.enable = false;

  plugins.conform-nvim.settings = {
    formatters_by_ft.go = [
      "goimports"
      "gofumpt"
    ];
    formatters.goimports.command = "${pkgs.gotools}/bin/goimports";
  };
  plugins.lint.lintersByFt.go = [ "golangcilint" ];

  extraPackages = with pkgs; [
    gofumpt
    golangci-lint
  ];
}
