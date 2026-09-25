# Python: basedpyright for types, ruff for lint and format.
{ pkgs, ... }:
{
  lsp.servers = {
    basedpyright = {
      enable = true;
      # LazyVim's defaults: "standard" checking; ruff organizes imports.
      config.settings.basedpyright = {
        analysis.typeCheckingMode = "standard";
        disableOrganizeImports = true;
      };
    };
    ruff.enable = true;
  };

  # ruff's hover is minimal; leave hover to basedpyright (LazyVim does the same).
  autoGroups.nixvim_ruff_hover.clear = true;
  autoGroups.nixvim_python_keymaps.clear = true;
  autoCmd = [
    {
      event = "FileType";
      group = "nixvim_python_keymaps";
      pattern = "python";
      callback.__raw = ''
        function(event)
          vim.keymap.set("n", "<leader>cv", "<cmd>VenvSelect<cr>", { buffer = event.buf, silent = true, desc = "Select VirtualEnv" })
        end
      '';
    }
    {
      event = "LspAttach";
      group = "nixvim_ruff_hover";
      callback.__raw = ''
        function(event)
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client.name == "ruff" then
            client.server_capabilities.hoverProvider = false
          end
        end
      '';
    }
  ];

  # venv-selector v2 API (nixvim's own example still shows v1 keys).
  plugins.venv-selector = {
    enable = true;
    settings.options.picker = "snacks";
  };

  plugins.conform-nvim.settings.formatters_by_ft.python = [
    "ruff_organize_imports"
    "ruff_format"
  ];

  extraPackages = [ pkgs.ruff ];
}
