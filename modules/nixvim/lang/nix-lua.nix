# nix and lua: this repo's own languages.
{ pkgs, ... }:
{
  lsp.servers = {
    nixd.enable = true;
    lua_ls = {
      enable = true;
      config.settings.Lua = {
        workspace.checkThirdParty = false;
        completion.callSnippet = "Replace";
      };
    };
  };

  plugins.lazydev.enable = true;
  plugins.blink-cmp.settings.sources = {
    per_filetype.lua.__raw = ''
      { "lazydev", inherit_defaults = true }
    '';
    providers.lazydev = {
      name = "LazyDev";
      module = "lazydev.integrations.blink";
      score_offset = 100;
    };
  };

  plugins.conform-nvim.settings.formatters_by_ft = {
    nix = [ "nixfmt" ];
    lua = [ "stylua" ];
  };

  extraPackages = with pkgs; [
    nixfmt
    stylua
  ];
}
