# JSON, YAML and TOML.
{ pkgs, ... }:
{
  # Schemas set explicitly: nixvim's plugins.schemastore wires only legacy plugins.lsp servers.
  extraPlugins = [ pkgs.vimPlugins.SchemaStore-nvim ];

  # nixpkgs has no jsonc treesitter grammar; use the json parser for jsonc buffers.
  extraConfigLua = ''
    vim.treesitter.language.register("json", "jsonc")
  '';

  lsp.servers = {
    jsonls = {
      enable = true;
      config.settings.json = {
        schemas.__raw = ''require("schemastore").json.schemas()'';
        validate.enable = true;
      };
    };
    yamlls = {
      enable = true;
      config.settings.yaml = {
        schemaStore = {
          enable = false;
          url = "";
        };
        schemas.__raw = ''require("schemastore").yaml.schemas()'';
        keyOrdering = false;
      };
    };
    taplo.enable = true;
  };

  plugins.conform-nvim.settings.formatters_by_ft = {
    json = [ "prettierd" ];
    jsonc = [ "prettierd" ];
    yaml = [ "prettierd" ];
    toml = [ "taplo" ];
  };

  extraPackages = with pkgs; [
    prettierd
    taplo
  ];
}
