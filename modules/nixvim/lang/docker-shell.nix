# Dockerfiles and shell scripts. bashls runs shellcheck itself when it is on PATH.
{ pkgs, ... }:
{
  lsp.servers = {
    dockerls.enable = true;
    bashls.enable = true;
  };

  plugins.conform-nvim.settings.formatters_by_ft = {
    sh = [ "shfmt" ];
    bash = [ "shfmt" ];
  };
  plugins.lint.lintersByFt.dockerfile = [ "hadolint" ];

  extraPackages = with pkgs; [
    shfmt
    shellcheck
    hadolint
  ];
}
