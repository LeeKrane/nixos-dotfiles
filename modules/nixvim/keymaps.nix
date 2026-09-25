# LazyVim-compatible core keymaps for the kept plugins, plus which-key groups.
let
  lua = code: { __raw = code; };
  map = mode: key: action: desc: {
    inherit mode key action;
    options = {
      inherit desc;
      silent = true;
    };
  };
  fn = body: lua "function() ${body} end";
  diag =
    count: severity:
    fn ''
      vim.diagnostic.jump({
        count = ${count},
        severity = ${severity},
        on_jump = function(_, bufnr)
          vim.diagnostic.open_float({ bufnr = bufnr, scope = "cursor", focus = false })
        end,
      })'';
  # Pass the key through raw inside floating windows (e.g. a lazygit float),
  # matching LazyVim; otherwise run the window-nav wincmd.
  termWinMap = key: dir: desc: {
    mode = "t";
    key = key;
    action = lua ''
      function()
        if vim.api.nvim_win_get_config(0).relative ~= "" then
          return "${key}"
        end
        return "<cmd>wincmd ${dir}<cr>"
      end
    '';
    options = {
      inherit desc;
      silent = true;
      expr = true;
    };
  };
in
{
  # Root for "root" pickers: git root, else cwd (replaces LazyVim.root()).
  extraConfigLuaPre = ''
    function _G.nixvim_root()
      return (Snacks and Snacks.git.get_root()) or vim.uv.cwd()
    end
  '';

  keymaps = [
    # pickers
    (map "n" "<leader><space>" (fn "Snacks.picker.files({ cwd = nixvim_root() })")
      "Find Files (Root Dir)"
    )
    (map "n" "<leader>/" (fn "Snacks.picker.grep({ cwd = nixvim_root() })") "Grep (Root Dir)")
    (map "n" "<leader>," (fn "Snacks.picker.buffers()") "Buffers")
    (map "n" "<leader>:" (fn "Snacks.picker.command_history()") "Command History")
    (map "n" "<leader>ff" (fn "Snacks.picker.files({ cwd = nixvim_root() })") "Find Files (Root Dir)")
    (map "n" "<leader>fr" (fn "Snacks.picker.recent()") "Recent")
    (map "n" "<leader>fc" (fn "Snacks.picker.files({ cwd = vim.fn.expand(vim.g.nixvim_config_dir) })")
      "Find Config File"
    )
    (map "n" "<leader>sg" (fn "Snacks.picker.grep({ cwd = nixvim_root() })") "Grep (Root Dir)")
    (map [
      "n"
      "x"
    ] "<leader>sw" (fn "Snacks.picker.grep_word({ cwd = nixvim_root() })") "Word (Root Dir)")
    (map "n" "<leader>sh" (fn "Snacks.picker.help()") "Help Pages")
    (map "n" "<leader>sk" (fn "Snacks.picker.keymaps()") "Keymaps")
    (map "n" "<leader>sd" (fn "Snacks.picker.diagnostics()") "Diagnostics")
    (map "n" "<leader>ss" (fn "Snacks.picker.lsp_symbols()") "LSP Symbols")
    (map "n" "<leader>sR" (fn "Snacks.picker.resume()") "Resume")
    (map "n" "<leader>sr" "<cmd>GrugFar<cr>" "Search and Replace")

    # explorer
    (map "n" "<leader>e" (fn "Snacks.explorer({ cwd = nixvim_root() })") "Explorer (Root Dir)")
    (map "n" "<leader>E" (fn "Snacks.explorer()") "Explorer (cwd)")
    (map "n" "-" "<cmd>Oil<cr>" "Open Parent Directory")

    # git
    (map "n" "<leader>gg" (fn "Snacks.lazygit({ cwd = nixvim_root() })") "Lazygit (Root Dir)")
    (map "n" "<leader>gb" (fn "Snacks.git.blame_line()") "Git Blame Line")
    (map "n" "<leader>gl" (fn "Snacks.lazygit.log({ cwd = nixvim_root() })") "Lazygit Log")

    # diagnostics
    (map "n" "]d" (diag "1" "nil") "Next Diagnostic")
    (map "n" "[d" (diag "-1" "nil") "Prev Diagnostic")
    (map "n" "]e" (diag "1" "vim.diagnostic.severity.ERROR") "Next Error")
    (map "n" "[e" (diag "-1" "vim.diagnostic.severity.ERROR") "Prev Error")
    (map "n" "]w" (diag "1" "vim.diagnostic.severity.WARN") "Next Warning")
    (map "n" "[w" (diag "-1" "vim.diagnostic.severity.WARN") "Prev Warning")
    (map "n" "<leader>cd" (fn "vim.diagnostic.open_float()") "Line Diagnostics")
    (map "n" "<leader>xx" "<cmd>Trouble diagnostics toggle<cr>" "Diagnostics (Trouble)")
    (map "n" "<leader>xX" "<cmd>Trouble diagnostics toggle filter.buf=0<cr>"
      "Buffer Diagnostics (Trouble)"
    )
    (map "n" "<leader>cs" "<cmd>Trouble symbols toggle<cr>" "Symbols (Trouble)")
    (map [
      "n"
      "x"
    ] "<leader>cf" (fn ''require("conform").format()'') "Format")

    # buffers
    (map "n" "<S-h>" "<cmd>BufferLineCyclePrev<cr>" "Prev Buffer")
    (map "n" "<S-l>" "<cmd>BufferLineCycleNext<cr>" "Next Buffer")
    (map "n" "[b" "<cmd>BufferLineCyclePrev<cr>" "Prev Buffer")
    (map "n" "]b" "<cmd>BufferLineCycleNext<cr>" "Next Buffer")
    (map "n" "<leader>bd" (fn "Snacks.bufdelete()") "Delete Buffer")
    (map "n" "<leader>bo" (fn "Snacks.bufdelete.other()") "Delete Other Buffers")
    (map "n" "<leader>bb" "<cmd>e #<cr>" "Switch to Other Buffer")

    # windows (normal + terminal only; insert <C-j>/<C-k>/<C-l> belong to blink)
    (map "n" "<C-h>" "<C-w>h" "Go to Left Window")
    (map "n" "<C-j>" "<C-w>j" "Go to Lower Window")
    (map "n" "<C-k>" "<C-w>k" "Go to Upper Window")
    (map "n" "<C-l>" "<C-w>l" "Go to Right Window")
    (termWinMap "<C-h>" "h" "Go to Left Window")
    (termWinMap "<C-j>" "j" "Go to Lower Window")
    (termWinMap "<C-k>" "k" "Go to Upper Window")
    (termWinMap "<C-l>" "l" "Go to Right Window")
    (map "n" "<leader>-" "<C-W>s" "Split Window Below")
    (map "n" "<leader>|" "<C-W>v" "Split Window Right")
    (map "n" "<leader>wd" "<C-W>c" "Delete Window")

    # ui toggles
    (map "n" "<leader>uf" (fn "vim.b.disable_autoformat = not vim.b.disable_autoformat")
      "Toggle Format on Save (Buffer)"
    )
    (map "n" "<leader>uF" (fn "vim.g.disable_autoformat = not vim.g.disable_autoformat")
      "Toggle Format on Save (Global)"
    )
    (map "n" "<leader>uw" (fn "vim.wo.wrap = not vim.wo.wrap") "Toggle Wrap")
    (map "n" "<leader>ul"
      (fn "vim.wo.number = not vim.wo.number; vim.wo.relativenumber = vim.wo.number")
      "Toggle Line Numbers"
    )
    (map "n" "<leader>ud" (fn "vim.diagnostic.enable(not vim.diagnostic.is_enabled())")
      "Toggle Diagnostics"
    )
    (map "n" "<leader>un" (fn "Snacks.notifier.hide()") "Dismiss Notifications")

    # sessions / quit
    (map "n" "<leader>qs" (fn ''require("persistence").load()'') "Restore Session")
    (map "n" "<leader>ql" (fn ''require("persistence").load({ last = true })'') "Restore Last Session")
    (map "n" "<leader>qd" (fn ''require("persistence").stop()'') "Don't Save Current Session")
    (map "n" "<leader>qq" "<cmd>qa<cr>" "Quit All")

    # flash
    (map [ "n" "x" "o" ] "s" (fn ''require("flash").jump()'') "Flash")
    (map [ "n" "x" "o" ] "S" (fn ''require("flash").treesitter()'') "Flash Treesitter")
    (map "o" "r" (fn ''require("flash").remote()'') "Remote Flash")
    (map [ "o" "x" ] "R" (fn ''require("flash").treesitter_search()'') "Treesitter Search")
    (map "c" "<c-s>" (fn ''require("flash").toggle()'') "Toggle Flash Search")

    # move by display line over wrapped lines (LazyVim default; user sets wrap = true)
    {
      mode = [
        "n"
        "x"
      ];
      key = "j";
      action = "v:count == 0 ? 'gj' : 'j'";
      options = {
        expr = true;
        silent = true;
        desc = "Down";
      };
    }
    {
      mode = [
        "n"
        "x"
      ];
      key = "k";
      action = "v:count == 0 ? 'gk' : 'k'";
      options = {
        expr = true;
        silent = true;
        desc = "Up";
      };
    }

    # misc
    (map [ "n" "i" "x" "s" ] "<C-s>" "<cmd>w<cr><esc>" "Save File")
    {
      mode = [
        "i"
        "n"
        "s"
      ];
      key = "<esc>";
      action = fn ''
        vim.cmd("noh")
        local ok, ls = pcall(require, "luasnip")
        if ok and ls.get_active_snip() then
          ls.unlink_current()
        end
        return "<esc>"'';
      options = {
        desc = "Escape and Clear hlsearch";
        silent = true;
        expr = true;
      };
    }
    (map "n" "<A-j>" "<cmd>m .+1<cr>==" "Move Down")
    (map "n" "<A-k>" "<cmd>m .-2<cr>==" "Move Up")
    (map "i" "<A-j>" "<esc><cmd>m .+1<cr>==gi" "Move Down")
    (map "i" "<A-k>" "<esc><cmd>m .-2<cr>==gi" "Move Up")
    (map "v" "<A-j>" ":m '>+1<cr>gv=gv" "Move Down")
    (map "v" "<A-k>" ":m '<-2<cr>gv=gv" "Move Up")
    (map "v" "<" "<gv" "Indent Left")
    (map "v" ">" ">gv" "Indent Right")
  ];

  autoGroups.nixvim_lsp_keymaps.clear = true;
  autoCmd = [
    {
      event = "LspAttach";
      group = "nixvim_lsp_keymaps";
      callback.__raw = ''
        function(event)
          local function map(mode, lhs, rhs, desc, opts)
            vim.keymap.set(mode, lhs, rhs, vim.tbl_extend("force", { buffer = event.buf, desc = desc }, opts or {}))
          end
          map("n", "gd", function() Snacks.picker.lsp_definitions() end, "Goto Definition")
          -- nowait: nvim 0.12's global grr/gra/grn/gri/grt would otherwise make
          -- plain `gr` wait on timeoutlen for a longer mapping.
          map("n", "gr", function() Snacks.picker.lsp_references() end, "References", { nowait = true })
          map("n", "gI", function() Snacks.picker.lsp_implementations() end, "Goto Implementation")
          map("n", "gy", function() Snacks.picker.lsp_type_definitions() end, "Goto Type Definition")
          map("n", "gD", vim.lsp.buf.declaration, "Goto Declaration")
          map("n", "K", function() vim.lsp.buf.hover() end, "Hover")
          map("n", "gK", function() vim.lsp.buf.signature_help() end, "Signature Help")
          map({ "n", "x" }, "<leader>ca", vim.lsp.buf.code_action, "Code Action")
          map("n", "<leader>cr", vim.lsp.buf.rename, "Rename")
        end
      '';
    }
  ];

  plugins.which-key.settings.spec = [
    {
      __unkeyed-1 = "<leader>b";
      group = "buffer";
    }
    {
      __unkeyed-1 = "<leader>c";
      group = "code";
    }
    {
      __unkeyed-1 = "<leader>f";
      group = "file/find";
    }
    {
      __unkeyed-1 = "<leader>g";
      group = "git";
    }
    {
      __unkeyed-1 = "<leader>gh";
      group = "hunks";
    }
    {
      __unkeyed-1 = "<leader>q";
      group = "quit/session";
    }
    {
      __unkeyed-1 = "<leader>s";
      group = "search";
    }
    {
      __unkeyed-1 = "<leader>u";
      group = "ui";
    }
    {
      __unkeyed-1 = "<leader>w";
      group = "windows";
    }
    {
      __unkeyed-1 = "<leader>x";
      group = "diagnostics/quickfix";
    }
  ];
}
