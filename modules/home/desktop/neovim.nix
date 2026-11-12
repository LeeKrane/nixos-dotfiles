# Desktop-only parts of the editor setup: the kitty launcher entry and the MIME defaults.
# The nvim package itself is installed for every role by ../common/neovim.nix.
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

  # GUI default for text files is Zed (dev.zed.Zed.desktop, from apps.nix); nvim
  # stays $EDITOR for terminal tools such as git.
  xdg.mimeApps.defaultApplications = lib.genAttrs textTypes (_: "dev.zed.Zed.desktop");
}
