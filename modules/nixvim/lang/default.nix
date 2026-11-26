{ config, ... }:
{
  imports = [
    ./nix-lua.nix
    ./data.nix
    ./web.nix
    ./python.nix
    ./go.nix
    ./rust.nix
    ./java.nix
    ./scala.nix
    ./tex.nix
    ./markdown.nix
    ./docker-shell.nix
  ];

  plugins.lspconfig.enable = true;

  diagnostic.settings = {
    virtual_text = true;
    severity_sort = true;
    float.border = "rounded";
  };

  plugins.conform-nvim = {
    enable = true;
    settings = {
      default_format_opts.lsp_format = "fallback";
      # Toggled by <leader>uf / <leader>uF (keymaps.nix).
      format_on_save.__raw = ''
        (function()
          local prettier_files = {
            [".prettierrc"] = true,
            [".prettierrc.json"] = true,
            [".prettierrc.yaml"] = true,
            [".prettierrc.yml"] = true,
            [".prettierrc.json5"] = true,
            [".prettierrc.js"] = true,
            [".prettierrc.cjs"] = true,
            [".prettierrc.mjs"] = true,
            [".prettierrc.toml"] = true,
            ["prettier.config.js"] = true,
            ["prettier.config.cjs"] = true,
            ["prettier.config.mjs"] = true,
          }
          local function has_prettier_key(path)
            local ok, pkg = pcall(function()
              return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
            end)
            return ok and type(pkg) == "table" and pkg.prettier ~= nil
          end
          local gates = {
            prettierd = function(name, path)
              return prettier_files[name] or (name == "package.json" and has_prettier_key(path .. "/" .. name))
            end,
            shfmt = function(name)
              return name == ".editorconfig"
            end,
          }
          local function configured(formatter, bufnr)
            local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
            return vim.fs.find(gates[formatter], { upward = true, path = dir })[1] ~= nil
          end
          local function timeout_ms()
            return vim.g.format_on_save_timeout_ms or 500
          end

          return function(bufnr)
            if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
              return
            end
            local listed = require("conform").formatters_by_ft[vim.bo[bufnr].filetype]
            if type(listed) ~= "table" then
              return { timeout_ms = timeout_ms() }
            end
            local kept, gated = {}, false
            for _, name in ipairs(listed) do
              if gates[name] and not configured(name, bufnr) then
                gated = true
              else
                table.insert(kept, name)
              end
            end
            if not gated then
              return { timeout_ms = timeout_ms() }
            end
            if #kept == 0 then
              return
            end
            return { timeout_ms = timeout_ms(), formatters = kept }
          end
        end)()
      '';
    };
  };

  plugins.lint.enable = true;
  autoGroups.nixvim_lint.clear = true;
  autoCmd = [
    {
      event = [
        "BufWritePost"
        "BufReadPost"
        "InsertLeave"
      ];
      group = "nixvim_lint";
      # golangci-lint type-checks the whole package: run it on save only.
      callback.__raw = ''
        function(ev)
          if vim.bo[ev.buf].filetype == "go" and ev.event ~= "BufWritePost" then
            return
          end
          require("lint").try_lint()
        end
      '';
    }
  ];

  plugins.treesitter = {
    enable = true;
    # Top-level options drive the main branch's FileType autocmd; settings.* is legacy.
    highlight.enable = true;
    indent.enable = true;
    grammarPackages = with config.plugins.treesitter.package.builtGrammars; [
      nix
      lua
      luadoc
      luap
      vim
      vimdoc
      query
      regex
      bash
      diff
      gitcommit
      git_rebase
      gitignore
      markdown
      markdown_inline
      typescript
      tsx
      javascript
      jsdoc
      html
      css
      json
      yaml
      toml
      python
      rust
      go
      gomod
      gosum
      gowork
      java
      scala
      latex
      bibtex
      dockerfile
    ];
  };
  plugins.treesitter-textobjects.enable = true;
}
