# Language plumbing shared by lang/*.nix: LSP, formatting, linting, treesitter.
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
    ./tex.nix
    ./markdown.nix
    ./docker-shell.nix
  ];

  # Upstream server defaults for the top-level `lsp` module (vim.lsp.config/enable).
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
      # prettierd and shfmt run on save only when the project has their config
      # (found upward from the buffer); manual <leader>cf always formats. Gating
      # here rather than with conform `condition`, which would also block
      # manual formatting. A buffer whose formatters are all gated off is not
      # formatted on save at all (no LSP fallback either).
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

          return function(bufnr)
            if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
              return
            end
            local listed = require("conform").formatters_by_ft[vim.bo[bufnr].filetype]
            if type(listed) ~= "table" then
              return { timeout_ms = 500 }
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
              return { timeout_ms = 500 }
            end
            if #kept == 0 then
              return
            end
            return { timeout_ms = 500, formatters = kept }
          end
        end)()
      '';
    };
  };

  # This module has no `settings`; linters go in lintersByFt (phase 2).
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
    # Top-level options drive the main branch's FileType autocmd (settings.* is the legacy API).
    highlight.enable = true;
    indent.enable = true;
    # All phase 1 and phase 2 grammars, so highlighting never regresses.
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
      latex
      bibtex
      dockerfile
    ];
  };
  plugins.treesitter-textobjects.enable = true;
}
