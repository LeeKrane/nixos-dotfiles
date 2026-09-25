# Standalone NixVim config, built as packages.x86_64-linux.nvim in flake.nix.
{
  imports = [
    ./options.nix
    ./autocmds.nix
    ./theme.nix
    ./snacks.nix
    ./ui.nix
    ./editing.nix
    ./tools.nix
    ./keymaps.nix
    ./completion.nix
    ./lang
  ];

  viAlias = true;
  vimAlias = true;

  performance.byteCompileLua = {
    enable = true;
    configs = true;
    plugins = true;
    nvimRuntime = true;
  };
}
