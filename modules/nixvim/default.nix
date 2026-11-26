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

  # No plugin here uses Ruby.
  withRuby = false;

  performance.byteCompileLua = {
    enable = true;
    configs = true;
    plugins = true;
    nvimRuntime = true;
  };
}
