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
    # Absolute path, not extraPackages: gotools ships many other binaries
    # (stringer, gonew, ...) that would land on the editor's PATH. Its
    # goimports wrapper references nixpkgs' go internally, so go is in the
    # editor's closure (not its PATH) regardless.
    formatters.goimports.command = "${pkgs.gotools}/bin/goimports";
  };
  plugins.lint.lintersByFt.go = [ "golangcilint" ];

  extraPackages = with pkgs; [
    gofumpt
    golangci-lint
  ];
}
