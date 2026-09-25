# Tabline, statusline, key hints and icons.
{
  plugins.mini = {
    enable = true;
    mockDevIcons = true;
    modules.icons = { };
  };

  plugins.bufferline = {
    enable = true;
    settings.options = {
      diagnostics = "nvim_lsp";
      always_show_bufferline = false;
      close_command.__raw = "function(n) Snacks.bufdelete(n) end";
      right_mouse_command.__raw = "function(n) Snacks.bufdelete(n) end";
      offsets = [ { filetype = "snacks_layout_box"; } ];
    };
  };

  plugins.lualine = {
    enable = true;
    settings = {
      options = {
        theme = "auto";
        globalstatus = true;
      };
      sections = {
        lualine_a = [ "mode" ];
        lualine_b = [ "branch" ];
        lualine_c = [
          "diagnostics"
          "filename"
        ];
        lualine_x = [
          "diff"
          "filetype"
        ];
        lualine_y = [ "progress" ];
        lualine_z = [ "location" ];
      };
    };
  };

  # Group names live in keymaps.nix.
  plugins.which-key.enable = true;
}
