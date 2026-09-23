# NixVim migration — design

Date: 2026-09-23
Status: approved in brainstorming, pending spec review

## Goal

Replace the vendored LazyVim setup (`config/nvim/` + `modules/home/neovim.nix`) completely with a native NixVim configuration. The editor must follow the wallpaper-driven color scheme of the illogical-impulse desktop the same way the terminal does, live, without restart.

Success criteria:

- `nvim` on every host is the NixVim build; no lazy.nvim, no LazyVim, no Mason, no runtime plugin or tool downloads.
- All LSPs, formatters, linters and treesitter grammars for the selected languages come from Nix.
- Changing the wallpaper recolors every running Neovim instance within about one second.
- Config changes can be tested with `nix run .#nvim` without a system rebuild.
- `nix flake check` fails if the generated config errors at startup.
- LazyVim core keymaps keep working, so existing muscle memory and LazyVim docs still apply for kept features.

## Current state (what is replaced)

- `modules/home/neovim.nix`: `programs.neovim` (defaultEditor, vi/vim aliases), per-file `xdg.configFile` links into `~/.config/nvim`, LSP/formatter binaries in `home.packages`.
- `config/nvim/`: LazyVim starter with language extras only (docker, java, json, markdown, python, rust, tailwind, tex, typescript, yaml), custom options, catppuccin-frappe, neo-tree showing dotfiles, Mason disabled, LuaSnip with a custom snippet library (`lua/snippets/{all,lua}.lua`, `lua/snippets/tex/*.lua`).
- Dead config: `lua/plugins/nvim-cmp.lua` and the cmp part of `luasnip.lua` do not apply, because LazyVim now uses blink.cmp. `lua/plugins/example.lua` is inert.
- Runtime plugin set (from `lazy-lock.json`): blink.cmp, bufferline, catppuccin, conform, crates, flash, friendly-snippets, fzf-lua, gitsigns, grug-far, lazydev, lualine, LuaSnip, markdown-preview, mini.ai, mini.icons, mini.pairs, neo-tree, noice, nvim-jdtls, nvim-lint, nvim-lspconfig, nvim-treesitter (+textobjects), nvim-ts-autotag, persistence, render-markdown, rustaceanvim, SchemaStore, snacks, sonokai, todo-comments, tokyonight, trouble, ts-comments, venv-selector, vimtex, which-key.

## Decisions

| Aspect | Decision |
|---|---|
| Architecture | Native NixVim, no lazy.nvim/LazyVim layer |
| Wiring | Standalone package via `nixvim.lib.evalNixvim`, installed by home-manager |
| Theme | Runtime mini.base16 palette from illogical-impulse generated colors, live reload |
| Completion | blink.cmp |
| Snippets | LuaSnip with all custom snippets, autosnippets and friendly-snippets |
| Picker | snacks.picker (replaces fzf-lua) |
| Explorer | snacks.explorer + oil.nvim (replaces neo-tree) |
| Messages UI | snacks.notifier; noice removed |
| Tabs / statusline | bufferline, lualine (kept) |
| Dashboard | snacks.dashboard (kept) |
| Editing | flash, mini.ai, mini.pairs, ts-comments, todo-comments (kept); mini.surround (new) |
| Workflow | gitsigns, snacks.lazygit, trouble, grug-far, persistence (kept) |
| which-key | kept |
| Languages | nix, lua, web (TS/JS, tailwind, html/css), data (json, yaml, toml), python, rust, go (new), java, tex, markdown, docker, shell (new) |
| rust-analyzer | from rustup, not bundled |
| Format on save | on, toggleable with `<leader>uf` |
| Keymaps | LazyVim-compatible core set, only for kept plugins |
| Options | user options verbatim plus LazyVim baseline |
| Extras (DAP, neotest, AI, terminal) | not included |
| Old files | deleted; snippets moved |

## Architecture

### Flake

- New input `nixvim.url = "github:nix-community/nixvim"` (branch `main`, matches nixos-unstable). Do not set `inputs.nixpkgs.follows` at first, per upstream advice. If evaluation fails due to nixpkgs skew (see nixvim issue #4426), switch to `follows = "nixpkgs"`.
- `packages.x86_64-linux.nvim`: `(nixvim.lib.evalNixvim { system = "x86_64-linux"; modules = [ ./modules/nixvim ]; }).config.build.package`. If the evaluated `lib.evalNixvim` signature differs in the pinned revision, adapt to the current documented form; the legacy `makeNixvimWithModule` is the fallback.
- `checks.x86_64-linux.nvim`: `config.build.test` of the same evaluation.
- The package reaches home-manager through the existing `inputs`/specialArgs path (`self.packages.${system}.nvim`), so all three hosts get the same build.

### Home-manager

`modules/home/neovim.nix` shrinks to:

- `home.packages = [ nvim ]`
- `home.sessionVariables.EDITOR`/`VISUAL = "nvim"`
- `vi` and `vim` aliases (NixVim `viAlias`/`vimAlias` if the standalone wrapper supports them, otherwise shell aliases)

Removed: `programs.neovim`, all `xdg.configFile."nvim/*"` entries, all LSP/formatter `home.packages`. `modules/nixos/shells.nix` (`EDITOR nvim`, `nv`, `fnv`, `rfnv`) and `git.nix` (`core.editor`) stay unchanged.

### Module layout

```
modules/nixvim/
  default.nix        imports everything below
  options.nix        opts, globals, leaders
  keymaps.nix        LazyVim-compatible core keymaps, which-key groups
  theme.nix          mini.base16 + fallback palette, loads lua/dynamic-theme.lua
  lua/dynamic-theme.lua
  completion.nix     blink.cmp, LuaSnip, friendly-snippets
  snippets/          moved from config/nvim/lua/snippets/ unchanged
  snacks.nix         picker, explorer, dashboard, notifier, lazygit, bigfile, quickfile, words, indent, input
  ui.nix             bufferline, lualine, which-key, mini.icons
  editing.nix        flash, mini.ai, mini.pairs, mini.surround, ts-comments, todo-comments, oil
  tools.nix          gitsigns, trouble, grug-far, persistence
  lang/
    default.nix      lsp + lspconfig base, conform, nvim-lint, treesitter base, format-on-save toggle
    nix-lua.nix  web.nix  data.nix  python.nix  rust.nix  go.nix
    java.nix  tex.nix  markdown.nix  docker-shell.nix
```

Each file owns one concern and can be read without the others. Language files only add servers, formatters, linters, grammars and language plugins to options defined in `lang/default.nix`.

## Options

User options, verbatim: `maplocalleader = ","`, `number`, `relativenumber`, `tabstop = 4`, `shiftwidth = 4`, `smartindent`, `smarttab`, `cursorline`, `expandtab = false`, `wrap = true`, `mouse = "a"`, `showmode = false`.

Dropped as Neovim defaults: `encoding`, `termguicolors`, `filetype plugin indent on`.

Added LazyVim baseline: `mapleader = " "`, `clipboard = "unnamedplus"`, `undofile`, `ignorecase`, `smartcase`, `scrolloff = 4`, `signcolumn = "yes"`, `splitright`, `splitbelow`, `confirm`, `completeopt = "menu,menuone,noselect"`, `laststatus = 3`.

## Dynamic theme

Inputs, both in `~/.local/state/quickshell/user/generated/` (`$XDG_STATE_HOME` respected):

- `colors.json`: flat Material 3 roles, snake_case keys, `#rrggbb` values. Written by matugen on every wallpaper or mode switch.
- `material_colors.scss`: `$term0`–`$term15` (the wallpaper-harmonized terminal palette also sent to kitty) and `$darkmode: True|False;`.

`lua/dynamic-theme.lua` (bundled via `extraFiles` or `extraConfigLua`):

1. Read and parse both files (`vim.json.decode`; simple line pattern for `$name: #hex;`).
2. Build a base16 palette:
   - `base00` background, `base01` surface_container, `base02` surface_container_high, `base03` outline, `base04` on_surface_variant, `base05` on_surface, `base06` inverse_surface, `base07` on_background.
   - `base08`–`base0F` from `term1`–`term6`, `primary`, `tertiary`.
   - Contrast guard: any accent whose contrast ratio against `base00` is below a threshold (start at 3.0), or which is near-white/near-black, is replaced by the closest M3 role (`primary`, `secondary`, `tertiary`, `error`). Bright terminal colors (`term9`–`term15`) are not used directly; in the current palette several are near white.
3. Set `vim.o.background` from `$darkmode` (fallback: lightness of `background`).
4. Call `require("mini.base16").setup({ palette = p, use_cterm = false })`, then fire `User DynamicThemeChanged` and `ColorScheme` so lualine (`theme = "auto"`), bufferline and snacks recompute highlights.
5. Watch `colors.json` with `vim.uv.new_fs_event`; debounce 200 ms; re-run steps 1–4. Re-arm the watcher after each event, because matugen may replace the file (new inode). Also watch the parent directory if the file does not exist yet at startup.

Fallback: if a file is missing or fails to parse, use a fixed palette defined in `theme.nix` (catppuccin-frappe base16 values) and emit a single `vim.notify` warning, not one per event.

No changes to illogical-impulse scripts. Each Neovim instance watches independently.

## Plugins

### Completion and snippets

- blink.cmp sources: lsp, path, snippets (`preset = "luasnip"`), buffer, lazydev (lua only).
- Keymap (`preset = "none"` plus explicit keys), porting the intent of the dead `nvim-cmp.lua`:
  - `<CR>`: accept only if an item is explicitly selected (no preselect), else newline.
  - `<C-j>`: expand snippet or jump forward.
  - `<C-l>`: jump backward.
  - `<C-k>`: accept selected or first item; show menu if hidden.
  - `<C-f>`: cycle LuaSnip choice node.
  - `<Tab>`/`<S-Tab>`: select next/previous item.
  - `<C-space>`: show menu, `<C-e>`: hide.
- LuaSnip: `enable_autosnippets = true`; `from_lua` loader with `paths` pointing at the store copy of `modules/nixvim/snippets/`; `from_vscode` lazy loader for friendly-snippets.
- If `performance.combinePlugins` is ever enabled, `friendly-snippets` must be in `standalonePlugins` (known blink conflict). Not enabled in this design.

### snacks.nvim

Enabled: picker, explorer (`hidden = true` so dotfiles show), dashboard (keys for find file, recent, grep, config, restore session, quit), notifier, lazygit, bigfile, quickfile, words, indent, input. Disabled: scroll, statuscolumn animations. lazygit binary in `extraPackages`.

### UI

- bufferline: `diagnostics = "nvim_lsp"`, `always_show_bufferline = false`, offset for snacks explorer.
- lualine: `theme = "auto"`, `globalstatus = true`, LazyVim-like sections (mode, branch, diagnostics, filename, diff, location).
- which-key v3 (`settings.spec`) with groups: `+buffer`, `+code`, `+file/find`, `+git`, `+git hunks`, `+quit/session`, `+search`, `+ui`, `+diagnostics/quickfix`.
- mini.icons with `mock_nvim_web_devicons`.

### Editing and workflow

flash (`s`, `S`, `r`, `R`, `<c-s>` in cmdline), mini.ai, mini.pairs, mini.surround (`gsa`, `gsd`, `gsr`, `gsf`, `gsh`), ts-comments, todo-comments, oil (`-` opens parent directory, dotfiles shown), gitsigns (`]h`/`[h`, `<leader>gh*`), trouble (`<leader>xx`, `<leader>xX`, `<leader>cs`), grug-far (`<leader>sr`), persistence (`<leader>qs`, `<leader>ql`, `<leader>qd`).

## Keymaps

LazyVim core set, limited to kept plugins:

- Pickers: `<leader><space>` files (root), `<leader>/` grep, `<leader>,` buffers, `<leader>:` command history, `<leader>ff`, `<leader>fr`, `<leader>fc` (config), `<leader>sg`, `<leader>sw`, `<leader>sh`, `<leader>sk`, `<leader>sd`, `<leader>ss`, `<leader>sR` (resume).
- Explorer: `<leader>e`, `<leader>E`; oil `-`.
- Git: `<leader>gg` lazygit, `<leader>gb` blame line, `<leader>gl` log.
- LSP: `gd`, `gr`, `gI`, `gy`, `gD`, `K`, `gK`, `<leader>ca`, `<leader>cr`, `<leader>cf`, `<leader>cd`.
- Diagnostics: `[d`/`]d`, `[e`/`]e`, `[w`/`]w`.
- Buffers: `<S-h>`/`<S-l>`, `[b`/`]b`, `<leader>bd`, `<leader>bo`, `<leader>bb`.
- Windows: `<C-h/j/k/l>`, `<leader>-`, `<leader>|`, `<leader>wd`.
- UI toggles: `<leader>uf` (format on save, buffer), `<leader>uF` (global), `<leader>uw` wrap, `<leader>ul` line numbers, `<leader>ud` diagnostics, `<leader>un` dismiss notifications.
- Misc: `<leader>qq` quit all, `<C-s>` save, `<esc>` clears search highlight, `<A-j>`/`<A-k>` move lines, `<`/`>` keep visual selection.

## Languages

LSP via the new top-level `lsp` module (Neovim 0.11 `vim.lsp.config`/`vim.lsp.enable`) with `plugins.lspconfig` supplying server defaults. If a server needs defaults the new module lacks (nixvim issue #3773), that server uses legacy `plugins.lsp.servers` instead. Server binaries come through the modules' package options or `extraPackages`.

| Language | LSP | Formatter | Linter / extra |
|---|---|---|---|
| nix | nixd | nixfmt | — |
| lua | lua_ls + lazydev | stylua | — |
| web | ts_ls, tailwindcss, html, cssls | prettierd | nvim-ts-autotag |
| data | jsonls, yamlls (SchemaStore), taplo | prettierd, taplo | — |
| python | basedpyright, ruff | ruff | venv-selector |
| rust | rustaceanvim (rust-analyzer from rustup, not bundled) | rustfmt via rust-analyzer | crates.nvim |
| go | gopls | gofumpt, goimports | golangci-lint |
| java | nvim-jdtls | jdtls | — |
| tex | texlab | latexindent | vimtex |
| markdown | marksman | prettierd | render-markdown, markdown-preview |
| docker / shell | dockerls, bashls | shfmt | hadolint, shellcheck |

Go and Rust toolchains (compiler, cargo, go) are not bundled; projects supply them.

Treesitter: `plugins.treesitter` with `grammarPackages` from `config.plugins.treesitter.package.builtGrammars` for all languages above plus `bash`, `diff`, `regex`, `vim`, `vimdoc`, `query`, `markdown_inline`, `luadoc`, `gitcommit`, `latex`. Highlight and indent enabled. nvim-treesitter-textobjects for mini.ai function/class objects.

Formatting: conform `format_on_save` guarded by `vim.g.disable_autoformat` / `vim.b.disable_autoformat`, `lsp_format = "fallback"`, 500 ms timeout.

## Performance

- `performance.byteCompileLua.enable = true` (configs, plugins, nvimRuntime).
- lz.n lazy loading only for heavy, clearly triggered plugins: grug-far, trouble, vimtex (ft), nvim-jdtls (ft), markdown-preview (ft/cmd). Skip lazy loading wherever it complicates setup.
- `combinePlugins` not enabled.

## Cleanup

- Move `config/nvim/lua/snippets/` to `modules/nixvim/snippets/` unchanged (`git mv`).
- Delete the rest of `config/nvim/`.
- Rewrite `modules/home/neovim.nix` as described.
- Update `docs/MIGRATION-NOTES.md` (remove lazyvim.json and Mason notes, keep rust-analyzer/rustup note, add NixVim notes) and `README.md` layout table.
- Add `just nvim *ARGS` recipe: `nix run .#nvim -- {{ARGS}}`.
- User runs manually after switching (outside the repo, not automated): `rm -rf ~/.config/nvim ~/.local/share/nvim/lazy ~/.local/state/nvim/lazy`.

## Verification

1. `nix flake check` passes, including `checks.x86_64-linux.nvim` (startup without errors, with no generated color files present).
2. `nix run .#nvim` on sample files per language: `:checkhealth vim.lsp` shows the server attached; format-on-save changes the file as expected.
3. LaTeX autosnippet and a friendly-snippet expand; `<C-j>`/`<C-l>` jump.
4. Wallpaper switch recolors running instances within about one second; light/dark switch flips `background`.
5. `nix build .#nixosConfigurations.<host>.config.system.build.toplevel --dry-run` for tariognatha, tarmantria, taractias.

## Workflow

Implement in a git worktree. One commit per section (flake wiring, options/keymaps, theme, completion/snippets, snacks/UI, editing/tools, languages, cleanup). Subject-only commit messages. No push, no PR.

## Out of scope

DAP, neotest, AI completion, terminal toggle, Mason, LazyVim extras UI, sharing the config with non-NixOS machines.
