# Installs the standalone NixVim build (modules/nixvim, flake output
# packages.<system>.nvim). Plugins, LSP servers and formatters live inside
# that package; nothing is linked into ~/.config/nvim.
{
  inputs,
  pkgs,
  ...
}:
{
  home.packages = [ inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.nvim ];

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
