# blink.cmp completion with LuaSnip (custom library in ./snippets + friendly-snippets).
{
  plugins.friendly-snippets.enable = true;

  plugins.luasnip = {
    enable = true;
    settings.enable_autosnippets = true;
    # plugins.friendly-snippets.enable already injects fromVscode = [{}] into
    # this module; setting it again here made lazy_load run twice and
    # doubled every friendly-snippets entry.
    fromLua = [
      {
        paths = ./snippets;
        lazyLoad = false;
      }
    ];
  };

  extraFiles."lua/snippet_util.lua".source = ./lua/snippet_util.lua;

  plugins.blink-cmp = {
    enable = true;
    settings = {
      # Upstream option, passed through nixvim's freeform settings. Default is vim.snippet.
      snippets.preset = "luasnip";
      completion = {
        list.selection = {
          preselect = false;
          auto_insert = false;
        };
        documentation.auto_show = true;
      };
      sources.default = [
        "lsp"
        "path"
        "snippets"
        "buffer"
      ];
      # Ports the intent of the old (dead) nvim-cmp.lua mappings.
      keymap = {
        preset = "none";
        # cmp.accept() (blink.cmp 1.10.2, lua/blink/cmp/init.lua) already
        # returns nil/falsy when nothing is selected: `if item == nil then
        # return end`, checked *before* scheduling the accept. No need to
        # duplicate that check with cmp.get_selected_item() here.
        "<CR>" = [
          "accept"
          "fallback"
        ];
        "<S-CR>" = [
          "select_and_accept"
          "fallback"
        ];
        "<C-j>" = [
          {
            __raw = ''
              function()
                local ls = require("luasnip")
                if ls.expand_or_jumpable() then
                  ls.expand_or_jump()
                  return true
                end
              end
            '';
          }
          "fallback"
        ];
        "<C-l>" = [
          {
            __raw = ''
              function()
                local ls = require("luasnip")
                if ls.jumpable(-1) then
                  ls.jump(-1)
                  return true
                end
              end
            '';
          }
          "fallback"
        ];
        # <C-k> is vim's built-in digraph key. Only take it over when there's
        # something to act on: accept a visible selection, or open the menu
        # after a keyword character; otherwise fall back to digraph entry
        # (e.g. right after whitespace or at the start of a line). In Select
        # mode (e.g. inside a LuaSnip placeholder, after jumping into a
        # choice/insert node), <C-k> is left alone entirely -- it must not
        # be swallowed by menu-accept/show, even if a menu happens to be
        # visible.
        "<C-k>" = [
          {
            __raw = ''
              function(cmp)
                if vim.fn.mode() == "s" then
                  return
                end
                if cmp.is_menu_visible() then
                  return cmp.select_and_accept()
                end
                local col = vim.fn.col(".") - 1
                -- \k (keyword chars, 'iskeyword') rather than Lua's %w:
                -- covers "_" and multibyte identifier characters, not just
                -- ASCII letters/digits.
                if col > 0 and vim.regex([[\k$]]):match_str(vim.fn.getline("."):sub(1, col)) then
                  return cmp.show()
                end
              end
            '';
          }
          "fallback"
        ];
        "<C-f>" = [
          {
            __raw = ''
              function()
                local ls = require("luasnip")
                if ls.choice_active() then
                  ls.change_choice(1)
                  return true
                end
              end
            '';
          }
          "fallback"
        ];
        "<C-d>" = [
          "scroll_documentation_down"
          "fallback"
        ];
        "<C-u>" = [
          "scroll_documentation_up"
          "fallback"
        ];
        "<Tab>" = [
          "select_next"
          "fallback"
        ];
        "<S-Tab>" = [
          "select_prev"
          "fallback"
        ];
        "<C-space>" = [
          "show"
          "show_documentation"
          "hide_documentation"
        ];
        "<C-e>" = [
          "hide"
          "fallback"
        ];
      };
    };
  };
}
