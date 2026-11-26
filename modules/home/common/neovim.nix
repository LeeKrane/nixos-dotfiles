# Standalone NixVim build (modules/nixvim); nvim-stable for role = "server". Nothing is linked
# into ~/.config/nvim.
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
