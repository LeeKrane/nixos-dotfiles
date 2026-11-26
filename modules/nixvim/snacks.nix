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
        # oil owns directory buffers, so snacks explorer leaves netrw alone.
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
        # The default "startup" section needs lazy.nvim's stats.
        sections = [
          { section = "header"; }
          {
            section = "keys";
            gap = 1;
            padding = 1;
          }
        ];
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
