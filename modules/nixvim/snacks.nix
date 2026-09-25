# snacks.nvim: picker, explorer, dashboard, notifier, lazygit and small helpers.
{ pkgs, ... }:
{
  plugins.snacks = {
    enable = true;
    settings = {
      bigfile.enabled = true;
      quickfile.enabled = true;
      notifier.enabled = true;
      words.enabled = true;
      indent.enabled = true;
      input.enabled = true;
      scroll.enabled = false;
      lazygit.enabled = true;
      explorer = {
        enabled = true;
        # oil owns directory buffers (`-` opens Oil); snacks explorer stays
        # the <leader>e sidebar only, so the two don't race for netrw.
        replace_netrw = false;
      };
      picker = {
        enabled = true;
        sources = {
          explorer.hidden = true;
          files.hidden = true;
        };
      };
      dashboard = {
        enabled = true;
        preset.keys = [
          {
            key = "f";
            desc = "Find File";
            action = ":lua Snacks.dashboard.pick('files')";
          }
          {
            key = "r";
            desc = "Recent Files";
            action = ":lua Snacks.dashboard.pick('oldfiles')";
          }
          {
            key = "g";
            desc = "Find Text";
            action = ":lua Snacks.dashboard.pick('live_grep')";
          }
          {
            key = "c";
            desc = "Config";
            action = ":lua Snacks.picker.files({ cwd = vim.fn.expand(vim.g.nixvim_config_dir) })";
          }
          {
            key = "s";
            desc = "Restore Session";
            action = ":lua require('persistence').load()";
          }
          {
            key = "q";
            desc = "Quit";
            action = ":qa";
          }
        ];
      };
    };
  };

  extraPackages = with pkgs; [
    lazygit
    ripgrep
    fd
  ];
}
