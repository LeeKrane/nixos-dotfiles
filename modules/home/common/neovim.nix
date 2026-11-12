# Installs the standalone NixVim build (modules/nixvim, flake output packages.<system>.nvim,
# or nvim-stable for role = "server", built with the stable nixvim and nixpkgs). Plugins, LSP
# servers and formatters live inside that package; nothing is linked into ~/.config/nvim.
# Desktop-only launcher and MIME entries: ../desktop/neovim.nix.
{
  inputs,
  pkgs,
  role,
  ...
}:
{
  home.packages = [
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.${
      if role == "server" then "nvim-stable" else "nvim"
    }
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
