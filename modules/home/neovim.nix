# Installs the standalone NixVim build (modules/nixvim, flake output
# packages.<system>.nvim). Plugins, LSP servers and formatters live inside
# that package; nothing is linked into ~/.config/nvim.
{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  textTypes = [
    "text/plain"
    "text/markdown"
    "text/x-csrc"
    "text/x-chdr"
    "text/x-c++src"
    "text/x-python"
    "text/x-java"
    "text/x-go"
    "text/rust"
    "text/x-tex"
    "text/x-nix"
    "text/x-lua"
    "text/css"
    "text/csv"
    "text/javascript"
    "application/json"
    "application/toml"
    "application/x-yaml"
    "application/xml"
    "application/x-shellscript"
  ];
in
{
  home.packages = [ inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.nvim ];

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  # nvim.desktop from the package sets Terminal=true, which leaves the choice of
  # terminal to each launcher (Dolphin would pick konsole). This entry pins kitty.
  xdg.desktopEntries.nvim-kitty = {
    name = "Neovim";
    genericName = "Text Editor";
    exec = "kitty -1 nvim %F";
    icon = "nvim";
    terminal = false;
    categories = [
      "Utility"
      "TextEditor"
    ];
    mimeType = textTypes;
  };

  xdg.mimeApps.defaultApplications = lib.genAttrs textTypes (_: "nvim-kitty.desktop");
}
