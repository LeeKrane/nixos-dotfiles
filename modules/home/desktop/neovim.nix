{ lib, ... }:
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
  # The package's nvim.desktop has Terminal=true, leaving the terminal to each launcher (Dolphin
  # would pick konsole); this entry pins kitty.
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

  xdg.mimeApps.defaultApplications = lib.genAttrs textTypes (_: "dev.zed.Zed.desktop");
}
