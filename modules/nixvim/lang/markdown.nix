# Markdown: marksman, prettierd, in-buffer rendering and browser preview.
{ pkgs, ... }:
{
  lsp.servers.marksman.enable = true;

  plugins.render-markdown.enable = true;

  plugins.markdown-preview = {
    enable = true;
    lazyLoad.settings = {
      ft = "markdown";
      cmd = [
        "MarkdownPreview"
        "MarkdownPreviewToggle"
      ];
    };
  };

  autoGroups.nixvim_markdown_keymaps.clear = true;
  autoCmd = [
    {
      event = "FileType";
      group = "nixvim_markdown_keymaps";
      pattern = "markdown";
      callback.__raw = ''
        function(event)
          vim.keymap.set("n", "<leader>cp", "<cmd>MarkdownPreviewToggle<cr>", { buffer = event.buf, silent = true, desc = "Markdown Preview" })
        end
      '';
    }
  ];

  plugins.conform-nvim.settings.formatters_by_ft.markdown = [ "prettierd" ];
  extraPackages = [ pkgs.prettierd ];
}
