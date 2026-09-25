# NixVim migration — design

Date: 2026-09-23
Status: approved in brainstorming, revised after three peer reviews (NixVim API accuracy against nixvim `main` rev bcb5f577, dynamic theme, completeness). Pending user review.

## Goal

Replace the vendored LazyVim setup (`config/nvim/` + `modules/home/neovim.nix`) completely with a native NixVim configuration. The editor must follow the wallpaper-driven color scheme of the illogical-impulse desktop the same way the terminal does, live, without restart.

Success criteria:

- `nvim` on every host is the NixVim build; no lazy.nvim, no LazyVim, no Mason, no runtime plugin or tool downloads.
- All LSPs, formatters, linters and treesitter grammars for the selected languages come from Nix (except rust-analyzer, which comes from rustup, and the language toolchains: `go`, `rustup`, `jdk21`, `nodejs_22` and `texliveMedium` live in `modules/home/dev.nix`; `go` is added there in phase 2). `go` is not on the editor's PATH, but `gotools`' `goimports` wrapper references nixpkgs' `go` internally, so a copy of `go` is present in the editor's Nix closure (not its PATH) regardless.
- Changing the wallpaper recolors every running Neovim instance within about one second.
- Config changes can be tested with `nix run .#nvim` without a system rebuild.
- `nix flake check` fails if the generated config errors at startup.
- LazyVim core keymaps, options and default autocmds keep working for kept features.

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
| Theme | Runtime `dynamic` colorscheme on mini.base16: wallpaper surfaces + standard syntax hues tinted toward the wallpaper primary, live reload |
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
| Options / autocmds | user options verbatim plus LazyVim baseline options and default autocmds |
| Extras (DAP, neotest, AI, terminal) | not included |
| Old files | deleted; snippets moved |
| Delivery | two phases, each with its own implementation plan |

## Phasing

- **Phase 1 — usable editor, LazyVim removed.** Flake wiring, options, keymaps, autocmds, dynamic theme, completion and snippets, snacks, UI, editing, tools, `lang/default.nix` base, nix and lua languages, cleanup of `config/nvim/` and `neovim.nix`. After phase 1, `nvim` is the NixVim build on all hosts.
- **Phase 2 — remaining languages.** web, data, python, rust, go, java, tex, markdown, docker-shell. One commit per language.

Phase 1 removes LazyVim, so languages other than nix/lua lose LSP until phase 2 lands. Treesitter grammars for all languages are included in phase 1, so highlighting is not lost. The snippet library (including tex) works in phase 1; tex snippets that call vimtex functions evaluate lazily and only fail condition checks until vimtex arrives in phase 2 (see Snippets).

## Architecture

### Flake

- New input `nixvim.url = "github:nix-community/nixvim"` (branch `main`, matches nixos-unstable). Do not set `inputs.nixpkgs.follows` at first, per upstream advice. If evaluation fails due to nixpkgs skew (nixvim issue #4426, open), switch to `follows = "nixpkgs"`.
- The evaluation lives in `flake.nix` `outputs` (it needs `inputs.nixvim`), merged into the existing `packages.${system}` and `checks.${system}` attrsets, which currently come from `import ./pkgs { inherit pkgs; }` and a local attrset:
  ```nix
  nvimEval = nixvim.lib.evalNixvim {
    modules = [ ./modules/nixvim { nixpkgs.pkgs = pkgs; } ];
  };
  packages.${system} = import ./pkgs { inherit pkgs; } // { nvim = nvimEval.config.build.package; };
  checks.${system} = { lua-syntax = ...; nvim = nvimEval.config.build.test; };
  ```
  `nixpkgs.pkgs = pkgs` passes the flake's own `pkgs` (with `overlays = import ./overlays` and `allowUnfree`), so the editor uses the same nixpkgs as the system and no second nixpkgs tree lands in the closure. If this triggers the skew problem, drop it and let nixvim use its pinned nixpkgs. `evalNixvim { system, modules, extraSpecialArgs }`, `config.build.package` and `config.build.test` are confirmed in nixvim `main`.
- Home-manager gets the package through the existing `extraSpecialArgs = { inherit inputs hostName; }` as `inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.nvim`. Bare `self` and `system` are not in scope there.

### Home-manager

`modules/home/neovim.nix` shrinks to:

- `home.packages = [ nvim ]` (package from above)
- `home.sessionVariables.EDITOR`/`VISUAL = "nvim"`

`vi`/`vim` aliases come from NixVim's top-level `viAlias = true; vimAlias = true;` (confirmed available standalone).

Removed: `programs.neovim`, all `xdg.configFile."nvim/*"` entries, all LSP/formatter `home.packages`. `modules/nixos/shells.nix` (`EDITOR nvim`, `nv`, `fnv`, `rfnv`) and `git.nix` (`core.editor`) stay unchanged.

### Module layout

```
modules/nixvim/
  default.nix        imports everything below; viAlias/vimAlias; performance
  options.nix        opts, globals, leaders
  autocmds.nix       LazyVim default autocmds
  keymaps.nix        core keymaps + all which-key group definitions
  theme.nix          fallback palette, extraFiles for lua/dynamic-theme.lua and colors/dynamic.lua, startup call
  lua/dynamic-theme.lua
  colors/dynamic.lua
  completion.nix     blink.cmp, LuaSnip, friendly-snippets
  snippets/          moved from config/nvim/lua/snippets/ unchanged
  snacks.nix         picker, explorer, dashboard, notifier, lazygit, bigfile, quickfile, words, indent, input
  ui.nix             bufferline, lualine, which-key plugin settings, mini.icons
  editing.nix        flash, mini.ai, mini.pairs, mini.surround, ts-comments, todo-comments, oil
  tools.nix          gitsigns, trouble, grug-far, persistence
  lang/
    default.nix      lsp base, conform-nvim, lint, treesitter + all grammars, format-on-save toggle
    nix-lua.nix                                  (phase 1)
    web.nix  data.nix  python.nix  rust.nix  go.nix
    java.nix  tex.nix  markdown.nix  docker-shell.nix   (phase 2)
```

Each file owns one concern. which-key group names are defined only in `keymaps.nix`; `ui.nix` holds only which-key plugin settings. Language files add servers, formatters, linters and language plugins to options defined in `lang/default.nix`.

## Options

User options, verbatim: `maplocalleader = ","`, `number`, `relativenumber`, `tabstop = 4`, `shiftwidth = 4`, `smartindent`, `smarttab`, `cursorline`, `expandtab = false`, `wrap = true`, `mouse = "a"`, `showmode = false`, `termguicolors = true` (forced on; truecolor detection fails under tmux/SSH/VT, and the theme sets GUI colours only).

Dropped as Neovim defaults: `encoding`, `filetype plugin indent on`.

LazyVim baseline added (the full list; nothing else from LazyVim's options.lua is carried over): `mapleader = " "`, `clipboard = "unnamedplus"` (`""` when `vim.env.SSH_TTY` is set: no system clipboard over SSH, since OSC 52 reads block), `undofile = true`, `undolevels = 10000`, `ignorecase`, `smartcase`, `scrolloff = 4`, `sidescrolloff = 8`, `signcolumn = "yes"`, `splitright`, `splitbelow`, `splitkeep = "screen"`, `confirm`, `completeopt = "menu,menuone,noselect"`, `laststatus = 3`, `updatetime = 200`, `timeoutlen = 300`, `pumheight = 10`, `list = true` (`listchars = "tab:  ,trail:·,nbsp:␣"`: tabs render blank because the user indents with tabs and snacks.indent draws guides), `virtualedit = "block"`, `wildmode = "longest:full,full"`, `sessionoptions = "buffers,curdir,tabpages,winsize,help,globals,skiprtp,folds"`, `foldlevel = 99`, `foldmethod = "expr"`, `foldexpr = "v:lua.vim.treesitter.foldexpr()"`, `foldtext = ""`.

## Autocmds

LazyVim defaults, in `autocmds.nix` using `autoGroups`/`autoCmd`:

- highlight on yank
- `checktime` on focus gained / terminal leave
- resize splits on `VimResized`
- restore last cursor position on buffer open (skip gitcommit)
- close with `q` for `help`, `qf`, `man`, `lspinfo`, `checkhealth`, `notify`, `grug-far`, `gitsigns-blame`
- wrap and spell for `gitcommit`, `markdown`, `text`, `tex`
- `conceallevel = 0` for json/jsonc/json5
- auto-create missing parent directories on write

## Dynamic theme

### Source

Single input: `~/.local/state/quickshell/user/generated/material_colors.scss` (honor `$XDG_STATE_HOME`). It contains every Material 3 role (camelCase, e.g. `$background`, `$onSurface`, `$surfaceContainer`, `$primary`, `$error`), `$term0`–`$term15` and `$darkmode: True|False;`.

`colors.json` is not used. Findings from inspecting `switchwall.sh`/`applycolor.sh`:

- matugen writes `colors.json` first; the python generator writes the scss about 330 ms later.
- The scss is written through a shell `>` redirect: truncated at open, then written in one burst at exit. It is empty while python runs and stays empty if python fails.
- Both files are rewritten in place (same inode).
- `colors.json` and the scss come from different generators and disagree (e.g. background `#141315` vs `#0F0E0F`); under `forceDarkMode` their dark/light modes can differ. The scss is the one kitty uses.

### Parse and validate

- Colors: lines matching `^%$(%w+):%s*(#%x%x%x%x%x%x);` (hex is uppercase). Mode: `^%$darkmode:%s*(%a+);`. Ignore `$transparent`.
- Valid only if `darkmode`, `background`, `onSurface`, `surfaceContainer`, `surfaceContainerHigh`, `outline`, `onSurfaceVariant`, `primary` and `term0`–`term15` are all present.

### Palette

Surfaces (`base00`–`base07`):

| slot | source |
|---|---|
| base00 | `term0` (matches kitty's background exactly, no seam) |
| base01 | `surfaceContainer` |
| base02 | `surfaceContainerHigh` (selection) |
| base03 | `outline` (comments; contrast ≥ 3.0 vs base00) |
| base04 | `onSurfaceVariant` |
| base05 | `onSurface` |
| base06 | `onSurface` lightened (dark mode) / darkened (light mode) by a fixed step |
| base07 | `onBackground` |

Accents (`base08`–`base0F`): standard base16 hues shifted toward the wallpaper primary.

- Canonical OKLCH hues: base08 red 25°, base09 orange 55°, base0A yellow 90°, base0B green 145°, base0C cyan 200°, base0D blue 250°, base0E purple 305°, base0F brown/pink 0°.
- The whole hue wheel rotates by one angle: the signed gap from the canonical hue nearest to `$primary` onto it, capped at ±15° (no rotation when `$primary` is near-grey, chroma < 0.03). A single rotation keeps accent spacing intact.
- Fixed lightness: L ≈ 0.78 in dark mode, L ≈ 0.50 in light mode. Chroma fixed at about 0.12, reduced only to stay in sRGB gamut.
- Checks after conversion to hex:
  - contrast ≥ 4.5 against base00
  - OKLab distance ≥ 0.08 from base05
  - at least 25° hue separation between accents (holds by construction because the shift is capped)
- On failure, adjust lightness in steps toward more contrast. Never substitute another role.

Terminal colors: after applying the palette, set `vim.g.terminal_color_0..15` to `$term0..15`, so `:terminal` matches kitty. Existing terminal buffers keep their old colors (Neovim reads them only at terminal creation), which is accepted.

### Colorscheme integration

- `colors/dynamic.lua` (shipped via `extraFiles`):
  1. Set `vim.o.background` from `$darkmode`, only when it changes.
  2. Call `require("mini.base16").setup({ palette = p })` (cterm colors stay off by default).
  3. Set the terminal colors.
  4. Set `vim.g.colors_name = "dynamic"`.
- Apply at startup and on reload with `vim.cmd.colorscheme("dynamic")`. Neovim then runs `hi clear` and fires `ColorScheme` with pattern `dynamic`. lualine (`auto`), bufferline, gitsigns, snacks, todo-comments, render-markdown and flash recompute on `ColorScheme`. which-key, blink, treesitter `@*` and `@lsp.*` are covered by mini.base16 integrations and links.
- The startup call must run after mini is on the runtimepath: put it in `extraConfigLuaPost` rather than relying on mini's own `extraConfigLua` priority.
- A manual `:colorscheme other` sticks. The reload handler only applies when `vim.g.colors_name` is `nil` or `"dynamic"`.

### Watching

- Skip the watcher when there is no UI: `#vim.api.nvim_list_uis() == 0` (headless, embedded, flake check).
- Watch the directory `generated/` once with `vim.uv.new_fs_event`. Filter on `filename == "material_colors.scss"`. The fs_event itself is never re-armed (files are rewritten in place), but see the recreate case below.
- If the directory does not exist (yet), poll for it every 10s instead of never watching; once it appears, arm the watcher and reload.
- The watch is lost when the fs_event callback reports an error, `vim.uv.fs_stat` on the directory comes back nil, its inode changed since the watch was armed, or the reported filename is the directory's own basename (inotify watches an inode, not a path: a directory removed and recreated at the same path needs a fresh watch). On loss, stop and close that fs_event; if the directory exists right now (recreated already), re-arm immediately and reload; otherwise fall into the poll-and-re-arm path. This is exercised headless: `theme_state_spec.lua` stubs `nvim_list_uis()` to arm a real fs_event, then covers both a plain wallpaper change and a delete-then-recreate of the directory.
- Handler flow:
  - The trailing debounce is 300 ms and resets on each event.
  - The timer callback leaves libuv's fast-event context via `vim.schedule_wrap`, because `vim.cmd`/`vim.api` raise E5560 there; `vim.uv.*` calls (including the directory-gone check above) are fast-context safe and run inline.
  - If the file is valid, recompute the palette and apply `dynamic`.
  - If it is empty or invalid, keep the current palette and retry once, 500 ms out, via a single cancellable `vim.uv` timer. A new file event (a fresh, non-retry reload) cancels any retry still pending before doing its own work and scheduling its own, so an old retry can never race state a newer event already applied.
  - If a non-empty file is still invalid after the retry, show one `vim.notify` WARN.
- Close the fs_event, its debounce timer, the retry timer and the directory-poll timer on `VimLeavePre`.

### Fallback

- At startup, with no valid file, use a fixed palette defined in `theme.nix` (catppuccin-frappe base16 values, dark).
- A missing file or directory is silent (machines without illogical-impulse, `nix run` elsewhere, the flake check).
- Invalid content warns once per failure streak: the warning latch resets on every successful read, so a later, independent bad write in the same session still gets its own warning instead of being silently swallowed by an earlier one.
- After the first valid palette, the fallback is never used again in that session. Failed reloads keep the last good palette.

No changes to illogical-impulse scripts. Each Neovim instance watches independently; cost is one inotify watch and a few milliseconds per wallpaper switch.

## Plugins

Option paths below were verified against nixvim `main`.

### Completion and snippets

- `plugins.blink-cmp.settings`:
  - sources: `lsp`, `path`, `snippets`, `buffer`, plus `lazydev` for lua only.
  - `snippets.preset = "luasnip"`: upstream blink option passed through nixvim's freeform settings. It is not a declared nixvim option, and the plugin default is native `vim.snippet`, so it must be set explicitly.
  - `completion.list.selection.preselect = false`.
  - `keymap.preset = "none"` plus explicit keys (all insert mode), porting the intent of the dead `nvim-cmp.lua`:
    - `<CR>`: `["accept" "fallback"]`. blink.cmp 1.10.2's `accept()` already returns nil/falsy when nothing is selected (checked before scheduling), so this needs no extra selection check: it accepts the selected item, else falls back to a plain newline.
    - `<S-CR>`: `["select_and_accept" "fallback"]`. Forces acceptance of the first item even with nothing explicitly selected.
    - `<C-j>`: expand snippet or jump forward.
    - `<C-l>`: snippet jump backward.
    - `<C-k>`: vim's built-in digraph key. In Select mode (`vim.fn.mode() == "s"`, e.g. inside a LuaSnip placeholder) it is left alone unconditionally. Otherwise, only taken over when there is something to act on: if the menu is visible, `select_and_accept()`; else if the cursor is preceded by a keyword character (`vim.regex([[\k$]])`, i.e. `'iskeyword'` -- covers `_` and multibyte identifier characters, not just ASCII word characters), `show()` to open the menu; otherwise falls through to `fallback` for vim's native digraph entry (e.g. right after whitespace or at the start of a line).
    - `<C-f>`: cycle LuaSnip choice node. Doc scrolling moves to `<C-d>`/`<C-u>`, active only while the doc window is visible (falls back otherwise).
    - `<Tab>`/`<S-Tab>`: next/previous item.
    - `<C-space>`: show menu. `<C-e>`: hide.
- `plugins.luasnip`:
  - `settings.enable_autosnippets = true`.
  - `fromLua = [ { paths = <store path of modules/nixvim/snippets>; } ]` with eager loading.
  - `fromVscode = [ { } ]` (lazy) for `plugins.friendly-snippets`.
- tex snippets call `vim.fn["vimtex#syntax#in_mathzone"]` and `vim.fn["vimtex#env#is_inside"]` inside condition closures. These run at expansion time in tex buffers, after vimtex loads for the filetype. Loading the snippet files does not need vimtex. Until vimtex exists (phase 2), wrap those conditions defensively: `vim.fn.exists("*vimtex#syntax#in_mathzone") == 1` guard in a small shared helper. This is the only permitted edit to the snippet files.
- `performance.combinePlugins` is not enabled. (A blink/friendly-snippets conflict under combinePlugins is reported by users but not confirmed in nixvim source; irrelevant while combinePlugins stays off.)

### snacks.nvim

`plugins.snacks.settings`:

- `picker.enabled = true`, `picker.sources.explorer.hidden = true` (dotfiles shown), `picker.sources.files.hidden = true`.
- `explorer.enabled = true`.
- `dashboard`: keys for find file, recent, grep, config, restore session, quit.
- Enabled: `notifier`, `lazygit`, `bigfile`, `quickfile`, `words`, `indent`, `input`. `scroll` disabled.
- `lazygit` binary in `extraPackages`.
- Root detection for "root" pickers uses snacks.picker's built-in cwd/root handling (`Snacks.git.get_root()` fallback to cwd). There is no port of `LazyVim.root()`.

### UI

- bufferline, under `plugins.bufferline.settings.options`:
  - `diagnostics = "nvim_lsp"`
  - `always_show_bufferline = false`
  - `offsets = [ { filetype = "snacks_layout_box"; } ]` to reserve space for snacks.explorer
- lualine, under `plugins.lualine.settings.options`:
  - `theme = "auto"`
  - `globalstatus = true`
  - LazyVim-like sections in `settings.sections` (mode, branch, diagnostics, filename, diff, location)
- which-key v3 (`plugins.which-key.settings`). Group specs come from `keymaps.nix`.
- `plugins.mini-icons.mockDevIcons = true` (standalone mini-icons plugin), or on the combined plugin `plugins.mini.mockDevIcons = true` alongside `modules.icons`.

### Editing and workflow

- flash: keys `s`, `S` (n/x/o), `r` (o), `R` (o/x), `<c-s>` (cmdline toggle).
- `mini.ai`, `mini.pairs`, `mini.surround` (`gsa`, `gsd`, `gsr`, `gsf`, `gsh`), `ts-comments`, `todo-comments`.
- oil: `-` in normal mode is set globally to `<cmd>Oil<cr>` (oil's own `-` mapping applies only inside oil buffers); dotfiles shown via `view_options.show_hidden = true`.
- gitsigns: `settings.on_attach` defines buffer-local `]h`/`[h` and `<leader>gh*`.
- trouble: `<leader>xx`, `<leader>xX`, `<leader>cs`.
- grug-far: `<leader>sr`.
- persistence: `<leader>qs`, `<leader>ql`, `<leader>qd`.

## Keymaps

LazyVim core set, limited to kept plugins. Mode is normal unless noted.

- Pickers: `<leader><space>` files (root), `<leader>/` grep, `<leader>,` buffers, `<leader>:` command history, `<leader>ff`, `<leader>fr`, `<leader>fc` (config), `<leader>sg`, `<leader>sw` (n/x), `<leader>sh`, `<leader>sk`, `<leader>sd`, `<leader>ss`, `<leader>sR` (resume).
- Explorer: `<leader>e`, `<leader>E`; oil `-`.
- Git: `<leader>gg` lazygit, `<leader>gb` blame line, `<leader>gl` log.
- LSP (buffer-local on attach): `gd`, `gr`, `gI`, `gy`, `gD`, `K`, `gK` (signature help, normal mode; insert `<C-k>` stays with blink), `<leader>ca` (n/x), `<leader>cr`, `<leader>cf` (n/x), `<leader>cd`.
- Diagnostics: `[d`/`]d`, `[e`/`]e`, `[w`/`]w`.
- Buffers: `<S-h>`/`<S-l>`, `[b`/`]b`, `<leader>bd`, `<leader>bo`, `<leader>bb`.
- Windows: `<C-h/j/k/l>` (normal and terminal only, never insert), `<leader>-`, `<leader>|`, `<leader>wd`.
- UI toggles: `<leader>uf` (format on save, buffer), `<leader>uF` (global), `<leader>uw` wrap, `<leader>ul` line numbers, `<leader>ud` diagnostics, `<leader>un` dismiss notifications.
- Misc: `<leader>qq` quit all, `<C-s>` save (n/i/x/s), `<esc>` clears search highlight (n/i), `<A-j>`/`<A-k>` move lines (n/i/v), `<`/`>` keep visual selection (v).

Deliberate non-conflicts: flash `s` vs surround `gs*` (different keys); flash `<c-s>` is cmdline mode only, save `<C-s>` is not; `-` (oil) vs `<leader>-` (split).

which-key groups: `+buffer`, `+code`, `+file/find`, `+git`, `+hunks`, `+quit/session`, `+search`, `+ui`, `+windows`, `+diagnostics/quickfix`.

## Languages

### LSP wiring

- Use the top-level `lsp` module (Neovim 0.11 `vim.lsp.config`/`vim.lsp.enable`), optionally paired with `plugins.lspconfig` for upstream server defaults. The `lsp` module does not require it, but pairing is the documented idiom.
- The per-server "quirk" infrastructure landed (nixvim PR #3783, issue #3773 closed). No servers have been migrated to it yet, so cross-server wiring like the `ts_ls` integration still lives only in legacy `plugins.lsp.servers`. Any server needing such defaults uses legacy `plugins.lsp.servers` instead. Expected: none among the selected servers, because `ts_ls` is used standalone without vue.
- Server binaries come from the `lsp` module's per-server package defaults. When overriding, use these names: `dockerls` → `pkgs.dockerfile-language-server`, `bashls` → `pkgs.bash-language-server`, `ts_ls` → `pkgs.typescript-language-server`, `yamlls` → `pkgs.yaml-language-server`, and `html`/`cssls`/`jsonls` → `pkgs.vscode-langservers-extracted`.
- Self-managed LSP clients that bypass `vim.lsp.enable`:
  - **Rust**: `plugins.rustaceanvim`.
    - Set top-level `dependencies.rust-analyzer.enable = false`, because rustaceanvim otherwise puts nixpkgs' rust-analyzer on PATH.
    - Leave `settings.server.cmd` unset so rustaceanvim finds rustup's `rust-analyzer` on PATH.
    - Configured via `plugins.rustaceanvim.settings`, which maps to `vim.g.rustaceanvim`.
  - **Java**: nvim-jdtls directly (`extraPlugins`), not nixvim's `plugins.jdtls` module (its `cmd`/`root_dir` are evaluated once at startup, not per buffer).
    - Server `pkgs.jdt-language-server` in `extraPackages`.
    - Started from an explicit `FileType java` autocmd: root from `vim.fs.root(event.buf, markers)` (else cwd), `start_or_attach(config, nil, { bufnr = event.buf })`, `capabilities` from `require("blink.cmp").get_lsp_capabilities()`.
    - Per-project workspace dir under `vim.fn.stdpath("cache") .. "/jdtls/"`, named from the full root path (`/` → `%`) so projects with the same basename don't share one.

| Language | LSP | Formatter | Linter / extra |
|---|---|---|---|
| nix | nixd | nixfmt | — |
| lua | lua_ls + lazydev | stylua | — |
| web | ts_ls, tailwindcss, html, cssls | prettierd | nvim-ts-autotag |
| data | jsonls, yamlls (SchemaStore.nvim schemas), taplo | prettierd, taplo | — |
| python | basedpyright, ruff | ruff | venv-selector |
| rust | rustaceanvim (rust-analyzer from rustup) | rustfmt via rust-analyzer | crates.nvim |
| go | gopls | gofumpt, goimports | golangci-lint |
| java | nvim-jdtls | LSP formatting (jdtls) | — |
| tex | texlab | latexindent | vimtex |
| markdown | marksman | prettierd | render-markdown, markdown-preview |
| docker / shell | dockerls, bashls | shfmt | hadolint, shellcheck |

Notes:

- `latexindent` is not a top-level nixpkgs attribute. Build `(pkgs.texliveBasic.withPackages (ps: [ ps.latexindent ]))` and point conform's `formatters.latexindent.command` at its `bin/latexindent`; the env is not in `extraPackages`, so its `pdflatex` etc. never shadow the system `texliveMedium`. `prepend_args = [ "-g" "/dev/null" ]` stops latexindent writing `indent.log` into the cwd.
- `goimports` likewise runs from `${pkgs.gotools}/bin/goimports` via conform's `formatters.goimports.command`, keeping gotools' other binaries off the editor's PATH.
- basedpyright: `settings.basedpyright = { analysis.typeCheckingMode = "standard"; disableOrganizeImports = true; }` (ruff organizes imports).
- cssls: `lint.unknownAtRules = "ignore"` for `css`, `scss` and `less`, so Tailwind at-rules don't warn.
- crates.nvim: in-process LSP (`settings.lsp = { enabled; actions; completion; hover; }`), which blink reaches through its LSP source.
- `<leader>cv` (VenvSelect) and `<leader>cp` (MarkdownPreviewToggle) are buffer-local, set from `FileType python` / `FileType markdown` autocmds.
- venv-selector: nixvim's module example and picker assertion target the old v1 API. Write the v2 nested shape directly (`settings.options.picker = "snacks"` or `"native"`), and expect the nixvim picker assertion to be unreliable for snacks. If the assertion errors, use `"native"`.
- SchemaStore: `pkgs.vimPlugins.SchemaStore-nvim` via `extraPlugins`, with schemas set explicitly in `lsp.servers.jsonls`/`yamlls` config through `__raw` (nixvim's `plugins.schemastore` wiring targets the legacy `plugins.lsp` servers).
- vimtex: `texlivePackage = null` (use the system `texliveMedium`, keep TeX out of the editor closure); treesitter highlighting disabled for `latex`, because vimtex's math-zone detection needs vimtex syntax.

### Formatting and linting

- `plugins.conform-nvim.settings`:
  - `formatters_by_ft` per the table above.
  - `format_on_save` as raw Lua, returning nil when `vim.g.disable_autoformat` or `vim.b[buf].disable_autoformat` is set, else `{ timeout_ms = 500 }`; the `lsp_format = "fallback"` fallback comes from `default_format_opts`, not from `format_on_save` itself.
  - Format on save only with config: `prettierd` (web, json/yaml, markdown) runs on save only when a prettier config is found upward from the buffer (`.prettierrc`, `.prettierrc.{json,yaml,yml,json5,js,cjs,mjs,toml}`, `prettier.config.{js,cjs,mjs}`, or a `package.json` with a `"prettier"` key); `shfmt` only when an `.editorconfig` is found upward. `format_on_save` drops an unconfigured gated formatter from the run; if none is left it returns nil (no LSP fallback on save). Manual `<leader>cf` always formats (conform `condition` is not used, since it would also block manual formatting). taplo, stylua, nixfmt, ruff, gofumpt/goimports and latexindent always run on save.
- `plugins.lint.lintersByFt` (top-level camelCase option; this module has no `settings`). Lint on `BufWritePost`/`BufReadPost`/`InsertLeave`, except `go` buffers, which lint on `BufWritePost` only (golangci-lint is slow).
- Formatter and linter binaries go in `extraPackages`.

### Treesitter

`plugins.treesitter` with the top-level `highlight.enable` and `indent.enable` (not the legacy `settings.*`), and `grammarPackages` from `config.plugins.treesitter.package.builtGrammars`:

`nix lua luadoc luap vim vimdoc query regex bash diff gitcommit git_rebase gitignore markdown markdown_inline typescript tsx javascript jsdoc html css json yaml toml python rust go gomod gosum gowork java latex bibtex dockerfile`

All grammars ship in phase 1. `plugins.treesitter-textobjects` provides function/class objects for mini.ai.

## Performance

- `performance.byteCompileLua = { enable = true; configs = true; plugins = true; nvimRuntime = true; }`.
- lz.n lazy loading (`plugins.lz-n.enable`, per-plugin `lazyLoad.settings`) only for heavy, clearly triggered plugins:
  - grug-far and trouble (cmd/keys)
  - markdown-preview (ft/cmd), crates.nvim (`BufRead Cargo.toml`)

  vimtex is not lazy-loaded (vimtex documents that it must not be). nvim-jdtls and rustaceanvim already start from filetype hooks, so lz-n adds nothing for them.

  nixvim marks `lazyLoad` experimental (API may change). If a plugin misbehaves under it, drop lazy loading for that plugin rather than work around it.
- `combinePlugins` not enabled.

## Cleanup (phase 1)

- Move `config/nvim/lua/snippets/` to `modules/nixvim/snippets/` (`git mv`). The only edit is the vimtex guard described in Snippets.
- Delete the rest of `config/nvim/`.
- Rewrite `modules/home/neovim.nix` as described.
- Update `docs/MIGRATION-NOTES.md`:
  - Remove the `lazyvim.json` and Mason notes.
  - Keep the rust-analyzer/rustup note.
  - Add NixVim notes (`nix run .#nvim`, theme source file).
- Update the `README.md` layout table.
- Add `just nvim *ARGS` recipe: `nix run .#nvim -- {{ARGS}}`.
- User runs manually after switching (outside the repo, not automated): `rm -rf ~/.config/nvim ~/.local/share/nvim/lazy ~/.local/state/nvim/lazy`.

## Verification

Phase 1:

1. `nix flake check` passes, including `checks.x86_64-linux.nvim` (headless startup with no generated color files present; no warnings from the theme module).
2. The closure has no lazy.nvim, LazyVim or Mason: `nix path-info -r .#nvim | grep -Ei 'lazy-nvim|lazyvim|mason'` returns nothing.
3. `nix run .#nvim`:
   - `:checkhealth vim.lsp` shows nixd and lua_ls attached on a `.nix` and a `.lua` file.
   - Format on save works; `<leader>uf` disables it.
4. Snippets expand: a friendly-snippet, a lua snippet and a non-math tex snippet. `<C-j>`/`<C-l>` jump.
5. Theme:
   - Switching the wallpaper recolors running instances within about one second.
   - Switching light/dark flips `background`; all accents stay ≥ 4.5 contrast against base00 in both modes.
   - `:terminal` colors match kitty.
   - `:colorscheme habamax` survives a wallpaper switch.
6. LazyVim autocmds work: yank highlight, cursor restore, `q` closes help.
7. `nix build .#nixosConfigurations.<host>.config.system.build.toplevel --dry-run` for tariognatha, tarmantria, taractias.

Phase 2, per language: open a sample file and confirm each of the following:

- the LSP is attached
- the formatter runs on save
- the linter reports
- the language plugin works (vimtex compile, rustaceanvim with rustup's rust-analyzer, jdtls workspace creation, crates.nvim in `Cargo.toml`)
- tex math-mode autosnippets fire

## Workflow

- Implement in a git worktree.
- Phase 1 commits: flake wiring, options/autocmds/keymaps, theme, completion/snippets, snacks/UI, editing/tools, lang base + nix/lua, cleanup.
- Phase 2: one commit per language.
- Subject-only commit messages. No push, no PR.

## Out of scope

DAP, neotest, AI completion, terminal toggle, Mason, LazyVim extras UI, `LazyVim.root()` port, sharing the config with non-NixOS machines.
