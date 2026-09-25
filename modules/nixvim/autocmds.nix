# LazyVim's default autocmds (lua/lazyvim/config/autocmds.lua), ported.
{ lib, ... }:
{
  autoGroups =
    lib.genAttrs
      [
        "lazyvim_checktime"
        "lazyvim_highlight_yank"
        "lazyvim_resize_splits"
        "lazyvim_last_loc"
        "lazyvim_close_with_q"
        "lazyvim_wrap_spell"
        "lazyvim_json_conceal"
        "lazyvim_auto_create_dir"
      ]
      (_: {
        clear = true;
      });

  autoCmd = [
    {
      event = [
        "FocusGained"
        "TermClose"
        "TermLeave"
      ];
      group = "lazyvim_checktime";
      callback.__raw = ''
        function()
          if vim.o.buftype ~= "nofile" then
            vim.cmd("checktime")
          end
        end
      '';
    }
    {
      event = "TextYankPost";
      group = "lazyvim_highlight_yank";
      callback.__raw = "function() (vim.hl or vim.highlight).on_yank() end";
    }
    {
      event = "VimResized";
      group = "lazyvim_resize_splits";
      callback.__raw = ''
        function()
          local current_tab = vim.fn.tabpagenr()
          vim.cmd("tabdo wincmd =")
          vim.cmd("tabnext " .. current_tab)
        end
      '';
    }
    {
      event = "BufReadPost";
      group = "lazyvim_last_loc";
      callback.__raw = ''
        function(event)
          local buf = event.buf
          if vim.bo[buf].filetype == "gitcommit" or vim.b[buf].lazyvim_last_loc then
            return
          end
          vim.b[buf].lazyvim_last_loc = true
          local mark = vim.api.nvim_buf_get_mark(buf, '"')
          local lcount = vim.api.nvim_buf_line_count(buf)
          if mark[1] > 0 and mark[1] <= lcount then
            pcall(vim.api.nvim_win_set_cursor, 0, mark)
          end
        end
      '';
    }
    {
      event = "FileType";
      group = "lazyvim_close_with_q";
      pattern = [
        "help"
        "qf"
        "man"
        "lspinfo"
        "checkhealth"
        "notify"
        "grug-far"
        "gitsigns-blame"
      ];
      callback.__raw = ''
        function(event)
          vim.bo[event.buf].buflisted = false
          vim.schedule(function()
            vim.keymap.set("n", "q", function()
              vim.cmd("close")
              pcall(vim.api.nvim_buf_delete, event.buf, { force = true })
            end, { buffer = event.buf, silent = true, desc = "Quit buffer" })
          end)
        end
      '';
    }
    {
      event = "FileType";
      group = "lazyvim_wrap_spell";
      pattern = [
        "gitcommit"
        "markdown"
        "text"
        "tex"
      ];
      callback.__raw = ''
        function()
          vim.opt_local.wrap = true
          vim.opt_local.spell = true
        end
      '';
    }
    {
      event = "FileType";
      group = "lazyvim_json_conceal";
      pattern = [
        "json"
        "jsonc"
        "json5"
      ];
      callback.__raw = "function() vim.opt_local.conceallevel = 0 end";
    }
    {
      event = "BufWritePre";
      group = "lazyvim_auto_create_dir";
      callback.__raw = ''
        function(event)
          if event.match:match("^%w%w+:[\\/][\\/]") then
            return
          end
          local file = vim.uv.fs_realpath(event.match) or event.match
          vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
        end
      '';
    }
  ];
}
