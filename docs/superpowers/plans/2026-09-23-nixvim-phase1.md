# NixVim Migration Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace LazyVim with a native, standalone NixVim build (`packages.x86_64-linux.nvim`) that follows the illogical-impulse wallpaper colors live, with nix + lua language support; other languages follow in phase 2.

**Architecture:** `modules/nixvim/` is a NixVim module tree evaluated in `flake.nix` via `nixvim.lib.evalNixvim` with the flake's own `pkgs`. The result is exposed as `packages.x86_64-linux.nvim`, tested by `checks.x86_64-linux.nvim` (NixVim's startup test) and `checks.x86_64-linux.nvim-specs` (headless Lua specs in `modules/nixvim/tests/`), and installed by `modules/home/neovim.nix`. A runtime Lua module (`dynamic-theme.lua`) turns `material_colors.scss` into a mini.base16 palette exposed as colorscheme `dynamic` and reloads it on file change.

**Tech Stack:** Nix flakes, NixVim (`github:nix-community/nixvim`, branch `main`), Neovim 0.12, Lua (LuaJIT), mini.nvim, snacks.nvim, blink.cmp, LuaSnip.

**Spec:** `docs/superpowers/specs/2026-09-23-nixvim-migration-design.md` (read it first; this plan implements its Phase 1).

## Global Constraints

- nixpkgs channel: `nixos-unstable`; nixvim input on branch `main`, **no** `inputs.nixpkgs.follows` unless evaluation fails with nixvim issue #4426 (`lib.systems.elaborate: linux-kernel has been removed`).
- The editor build uses the flake's own `pkgs` (`overlays = import ./overlays`, `config.allowUnfree = true`) via `{ nixpkgs.pkgs = pkgs; }`.
- No lazy.nvim, LazyVim or Mason anywhere in the closure. No runtime downloads.
- rust-analyzer is never bundled (phase 2 concern; do not add it).
- Theme source is only `$XDG_STATE_HOME/quickshell/user/generated/material_colors.scss` (default `~/.local/state/...`). Never read `colors.json`. Never modify illogical-impulse scripts.
- Commit messages: subject line only, no body, no `Co-Authored-By` or any Claude/Anthropic attribution (user's global rule overrides harness attribution). Never push. Never open a PR.
- Flakes only see git-tracked files: `git add` every new file before any `nix build`/`nix eval`.
- Work in a git worktree on a feature branch (create via superpowers:using-git-worktrees before Task 1).
- Nix formatting: run `nix fmt` (nixfmt) on changed `.nix` files before each commit.
- `cat` may be aliased to `bat`; in shell steps use `command cat`.

## Test commands (used by every task)

- Specs: `nix build .#checks.x86_64-linux.nvim-specs -L` — runs each `modules/nixvim/tests/*_spec.lua` in a fresh headless `nvim` with empty `$HOME`/`$XDG_STATE_HOME`; any Lua error fails the build and prints the assertion message.
- NixVim startup test: `nix build .#checks.x86_64-linux.nvim -L` — fails on startup errors or warnings.
- Package: `nix build .#nvim` then `./result/bin/nvim` for manual poking.

## Review Focus

1. **Theme file mid-write (empty or truncated scss) during a wallpaper switch** — expect the previous palette to stay, no flash to the fallback, no notification. Pinned by `theme_state_spec.lua` (Task 3).
2. **Machine or check sandbox without illogical-impulse (no `generated/` dir)** — expect silent fallback palette, no warning, no watcher, clean startup test. Pinned by `theme_state_spec.lua` step 1 and `checks.nvim` (Task 3).
3. **Low-chroma wallpaper (grey primary) and light mode** — expect readable accents (≥ 4.5 contrast vs background), distinct hues, `background=light`. Pinned by `theme_spec.lua` dark/light/vivid fixtures (Task 3).
4. **User runs `:colorscheme habamax` then the wallpaper changes** — expect habamax to stay. Pinned by `theme_state_spec.lua` step 6 (Task 3).
5. **Format-on-save toggle and tex snippets without vimtex (phase 1)** — expect `<leader>uF` to stop formatting on write; math-mode snippet conditions return false instead of erroring. Pinned by `lsp_spec.lua` (Task 8) and `completion_spec.lua` (Task 7).

---

## File Structure

```
flake.nix                                   + nixvim input, nvimEval, packages.nvim, checks.nvim, checks.nvim-specs
modules/nixvim/default.nix                  imports; viAlias/vimAlias; performance; lz-n
modules/nixvim/options.nix                  opts, globals (leaders)
modules/nixvim/autocmds.nix                 LazyVim default autocmds
modules/nixvim/keymaps.nix                  global keymaps, LspAttach buffer maps, which-key groups, nixvim_root helper
modules/nixvim/theme.nix                    fallback palette, extraFiles, startup call
modules/nixvim/lua/dynamic-theme.lua        parse, palette math, apply, reload, watch
modules/nixvim/colors/dynamic.lua           `:colorscheme dynamic` entry point
modules/nixvim/lua/snippet_util.lua         vimtex-safe snippet conditions
modules/nixvim/completion.nix               blink.cmp, LuaSnip, friendly-snippets
modules/nixvim/snippets/                    moved from config/nvim/lua/snippets/
modules/nixvim/snacks.nix                   snacks.nvim
modules/nixvim/ui.nix                       mini.icons, bufferline, lualine, which-key plugin
modules/nixvim/editing.nix                  flash, mini.ai/pairs/surround, ts-comments, todo-comments, oil
modules/nixvim/tools.nix                    gitsigns, trouble, grug-far, persistence
modules/nixvim/lang/default.nix             lspconfig, diagnostics, conform, lint, treesitter + grammars
modules/nixvim/lang/nix-lua.nix             nixd, lua_ls, lazydev, nixfmt, stylua
modules/nixvim/stylua.toml                  moved from config/nvim/stylua.toml
modules/nixvim/tests/*_spec.lua             headless specs
modules/nixvim/tests/fixtures/*.scss        theme fixtures
modules/home/neovim.nix                     rewritten: install nvim, EDITOR/VISUAL
config/nvim/                                deleted
justfile, README.md, docs/MIGRATION-NOTES.md updated
```

---

### Task 1: Flake wiring, options, spec runner

**Files:**
- Modify: `flake.nix`
- Create: `modules/nixvim/default.nix`, `modules/nixvim/options.nix`, `modules/nixvim/tests/options_spec.lua`

**Interfaces:**
- Produces: flake outputs `packages.x86_64-linux.nvim`, `checks.x86_64-linux.nvim`, `checks.x86_64-linux.nvim-specs`; spec convention: every `modules/nixvim/tests/*_spec.lua` is `dofile`d in a fresh headless nvim, fails by raising a Lua error; env vars `SPEC_FIXTURES` (fixtures dir) and a writable empty `XDG_STATE_HOME`.
- Produces: `modules/nixvim/default.nix` with an `imports` list later tasks append to.

- [ ] **Step 1: Add the nixvim input**

In `flake.nix` `inputs`, after `nix-index-database.url = ...;` add:

```nix
    # No `nixpkgs.follows`, per nixvim's advice: it is tested against its
    # own pin. The editor still builds with this flake's pkgs, see nvimEval.
    nixvim.url = "github:nix-community/nixvim";
```

- [ ] **Step 2: Add nvimEval, package and checks**

In `flake.nix` `outputs` `let` block, after `mkHost = ...;` add:

```nix
      # Standalone NixVim build, see modules/nixvim/. Uses this flake's pkgs
      # so overlays and allowUnfree apply and no second nixpkgs is pulled in.
      nvimEval = inputs.nixvim.lib.evalNixvim {
        inherit system;
        modules = [
          ./modules/nixvim
          { nixpkgs.pkgs = pkgs; }
        ];
      };
      nvim = nvimEval.config.build.package;
```

Replace `packages.${system} = import ./pkgs { inherit pkgs; };` with:

```nix
      packages.${system} = import ./pkgs { inherit pkgs; } // {
        inherit nvim;
      };
```

In `checks.${system} = { ... };`, after the `lua-syntax = ...;` attribute add:

```nix
        # NixVim's own startup test: fails on errors or warnings at startup.
        nvim = nvimEval.config.build.test;

        # Headless Lua specs in modules/nixvim/tests/, one fresh nvim each.
        nvim-specs = pkgs.runCommand "nvim-specs" { nativeBuildInputs = [ nvim ]; } ''
          export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config"
          export XDG_CACHE_HOME="$TMPDIR/cache" XDG_DATA_HOME="$TMPDIR/data"
          export SPEC_FIXTURES=${./modules/nixvim/tests/fixtures}
          mkdir -p "$HOME"
          count=0
          for spec in ${./modules/nixvim/tests}/*_spec.lua; do
            echo "== $(basename "$spec")"
            export XDG_STATE_HOME="$TMPDIR/state-$count"
            mkdir -p "$XDG_STATE_HOME"
            nvim --headless -c "lua local ok, err = pcall(dofile, '$spec'); if not ok then io.stderr:write(tostring(err) .. '\n'); vim.cmd('cquit 1') end; vim.cmd('qall!')"
            count=$((count + 1))
          done
          if [ "$count" -eq 0 ]; then
            echo "no specs found" >&2
            exit 1
          fi
          echo "ran $count specs"
          touch "$out"
        '';
```

Create `modules/nixvim/tests/fixtures/.gitkeep` (empty) so the fixtures path exists now.

- [ ] **Step 3: Write the failing spec**

Create `modules/nixvim/tests/options_spec.lua`:

```lua
-- User options from the old options.lua plus the LazyVim baseline (spec: Options).
local o, g = vim.o, vim.g

assert(g.mapleader == " ", "mapleader")
assert(g.maplocalleader == ",", "maplocalleader")

local expected = {
	number = true,
	relativenumber = true,
	tabstop = 4,
	shiftwidth = 4,
	smartindent = true,
	smarttab = true,
	cursorline = true,
	expandtab = false,
	wrap = true,
	mouse = "a",
	showmode = false,
	clipboard = "unnamedplus",
	undofile = true,
	undolevels = 10000,
	ignorecase = true,
	smartcase = true,
	scrolloff = 4,
	sidescrolloff = 8,
	signcolumn = "yes",
	splitright = true,
	splitbelow = true,
	splitkeep = "screen",
	confirm = true,
	completeopt = "menu,menuone,noselect",
	laststatus = 3,
	updatetime = 200,
	timeoutlen = 300,
	pumheight = 10,
	list = true,
	virtualedit = "block",
	wildmode = "longest:full,full",
	foldlevel = 99,
	foldmethod = "expr",
	foldexpr = "v:lua.vim.treesitter.foldexpr()",
	foldtext = "",
}
for name, want in pairs(expected) do
	assert(o[name] == want, string.format("option %s: want %s, got %s", name, vim.inspect(want), vim.inspect(o[name])))
end
assert(o.sessionoptions:find("folds", 1, true), "sessionoptions includes folds")
assert(o.listchars:find("trail:", 1, true), "listchars sets trail")
```

`git add modules/nixvim flake.nix`

- [ ] **Step 4: Minimal module so the flake evaluates, run spec, verify it fails**

Create `modules/nixvim/default.nix`:

```nix
# Standalone NixVim config, built as packages.x86_64-linux.nvim in flake.nix.
{
  imports = [
    ./options.nix
  ];

  viAlias = true;
  vimAlias = true;

  performance.byteCompileLua = {
    enable = true;
    configs = true;
    plugins = true;
    nvimRuntime = true;
  };
}
```

Create `modules/nixvim/options.nix` containing only `{ }`.

Run: `nix flake lock && git add flake.lock modules/nixvim && nix build .#checks.x86_64-linux.nvim-specs -L`
Expected: FAIL, stderr contains `mapleader`.

If evaluation fails with `lib.systems.elaborate: linux-kernel has been removed` (nixvim #4426), add `inputs.nixpkgs.follows = "nixpkgs";` under the nixvim input (turn it into an attrset `nixvim = { url = ...; inputs.nixpkgs.follows = "nixpkgs"; };` and update its comment), `nix flake lock`, retry. If it fails because `nixpkgs.pkgs` conflicts with `system`, drop `inherit system;` from `evalNixvim` and retry.

- [ ] **Step 5: Implement options**

Replace `modules/nixvim/options.nix`:

```nix
# User options carried over from the LazyVim config, plus LazyVim's baseline.
{
  globals = {
    mapleader = " ";
    maplocalleader = ",";
  };

  opts = {
    # user options (old config/nvim/lua/config/options.lua)
    number = true;
    relativenumber = true;
    tabstop = 4;
    shiftwidth = 4;
    smartindent = true;
    smarttab = true;
    cursorline = true;
    expandtab = false;
    wrap = true;
    mouse = "a";
    showmode = false;

    # LazyVim baseline
    clipboard = "unnamedplus";
    undofile = true;
    undolevels = 10000;
    ignorecase = true;
    smartcase = true;
    scrolloff = 4;
    sidescrolloff = 8;
    signcolumn = "yes";
    splitright = true;
    splitbelow = true;
    splitkeep = "screen";
    confirm = true;
    completeopt = "menu,menuone,noselect";
    laststatus = 3;
    updatetime = 200;
    timeoutlen = 300;
    pumheight = 10;
    list = true;
    # Tabs render blank: the user indents with tabs and snacks.indent draws guides.
    listchars = "tab:  ,trail:·,nbsp:␣";
    virtualedit = "block";
    wildmode = "longest:full,full";
    sessionoptions = "buffers,curdir,tabpages,winsize,help,globals,skiprtp,folds";
    foldlevel = 99;
    foldmethod = "expr";
    foldexpr = "v:lua.vim.treesitter.foldexpr()";
    foldtext = "";
  };
}
```

- [ ] **Step 6: Run specs and startup test, verify pass**

Run: `nix build .#checks.x86_64-linux.nvim-specs -L && nix build .#checks.x86_64-linux.nvim -L && nix build .#nvim`
Expected: all succeed; log shows `== options_spec.lua` and `ran 1 specs`.

- [ ] **Step 7: Commit**

```bash
nix fmt
git add flake.nix flake.lock modules/nixvim
git commit -m "Add standalone NixVim package with options and spec runner"
```

---

### Task 2: LazyVim default autocmds

**Files:**
- Create: `modules/nixvim/autocmds.nix`, `modules/nixvim/tests/autocmds_spec.lua`
- Modify: `modules/nixvim/default.nix` (imports)

**Interfaces:**
- Produces: augroups `lazyvim_checktime`, `lazyvim_highlight_yank`, `lazyvim_resize_splits`, `lazyvim_last_loc`, `lazyvim_close_with_q`, `lazyvim_wrap_spell`, `lazyvim_json_conceal`, `lazyvim_auto_create_dir`.

- [ ] **Step 1: Write the failing spec**

Create `modules/nixvim/tests/autocmds_spec.lua`:

```lua
-- LazyVim default autocmds (spec: Autocmds).
local function has_group(name, event)
	local ok, list = pcall(vim.api.nvim_get_autocmds, { group = name, event = event })
	return ok and #list > 0
end

assert(has_group("lazyvim_checktime", "FocusGained"), "checktime")
assert(has_group("lazyvim_highlight_yank", "TextYankPost"), "highlight on yank")
assert(has_group("lazyvim_resize_splits", "VimResized"), "resize splits")
assert(has_group("lazyvim_last_loc", "BufReadPost"), "last loc")
assert(has_group("lazyvim_close_with_q", "FileType"), "close with q")
assert(has_group("lazyvim_wrap_spell", "FileType"), "wrap spell")
assert(has_group("lazyvim_json_conceal", "FileType"), "json conceal")
assert(has_group("lazyvim_auto_create_dir", "BufWritePre"), "auto create dir")

-- behaviour: writing into a missing directory creates it
local dir = vim.fn.tempname() .. "/a/b"
vim.cmd.edit(dir .. "/file.txt")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "x" })
vim.cmd.write()
assert(vim.fn.filereadable(dir .. "/file.txt") == 1, "auto-created parent dir")

-- behaviour: help buffers close with q
vim.cmd.enew()
vim.bo.filetype = "help"
vim.wait(50)
assert(vim.fn.maparg("q", "n") ~= "", "q mapped in help buffer")

-- behaviour: markdown gets wrap + spell
vim.cmd.enew()
vim.bo.filetype = "markdown"
assert(vim.wo.spell == true and vim.wo.wrap == true, "markdown wrap+spell")
```

`git add modules/nixvim/tests/autocmds_spec.lua`

- [ ] **Step 2: Run spec, verify it fails**

Run: `nix build .#checks.x86_64-linux.nvim-specs -L`
Expected: FAIL with `checktime`.

- [ ] **Step 3: Implement autocmds**

Create `modules/nixvim/autocmds.nix`:

```nix
# LazyVim's default autocmds (lua/lazyvim/config/autocmds.lua), ported.
{ lib, ... }:
{
  autoGroups = lib.genAttrs [
    "lazyvim_checktime"
    "lazyvim_highlight_yank"
    "lazyvim_resize_splits"
    "lazyvim_last_loc"
    "lazyvim_close_with_q"
    "lazyvim_wrap_spell"
    "lazyvim_json_conceal"
    "lazyvim_auto_create_dir"
  ] (_: { clear = true; });

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
```

Add `./autocmds.nix` to `imports` in `modules/nixvim/default.nix`.

- [ ] **Step 4: Run specs, verify pass**

Run: `git add modules/nixvim && nix build .#checks.x86_64-linux.nvim-specs -L`
Expected: PASS, `ran 2 specs`. The `q` check uses `vim.wait(50)` because the map is set in `vim.schedule`; if it flakes, raise to `vim.wait(200, function() return vim.fn.maparg("q", "n") ~= "" end)`.

- [ ] **Step 5: Commit**

```bash
nix fmt
git add modules/nixvim
git commit -m "Port LazyVim default autocmds to NixVim"
```

---

### Task 3: Dynamic wallpaper theme

**Files:**
- Create: `modules/nixvim/theme.nix`, `modules/nixvim/lua/dynamic-theme.lua`, `modules/nixvim/colors/dynamic.lua`
- Create: `modules/nixvim/tests/theme_spec.lua`, `modules/nixvim/tests/theme_state_spec.lua`
- Create: `modules/nixvim/tests/fixtures/material_colors_{dark,light,vivid,truncated}.scss`
- Modify: `modules/nixvim/default.nix` (imports)

**Interfaces:**
- Produces Lua module `dynamic-theme` (`require("dynamic-theme")`):
  - `scss_path() -> string`
  - `parse(text: string) -> {dark: boolean, colors: table<string, "#rrggbb">} | nil, err` where `err` is `"empty"` or starts with `"invalid"`
  - `build_palette(parsed) -> palette: table<"base00".."base0F", "#rrggbb">, term: string[16]`
  - `read() -> state | nil, err` (`err` also may be `"missing"`); `state = {dark, palette, term}`
  - `contrast(a, b) -> number`, `oklab_distance(a, b) -> number`, `hex_to_oklch(hex) -> L, C, h`, `oklch_to_hex(L, C, h) -> hex`, `rotation(primary_hex) -> degrees`
  - `HUES` table, `state` field, `apply()`, `reload(is_retry: boolean) -> boolean`, `watch()`, `setup()`
- Produces global `vim.g.dynamic_theme_fallback` (palette table) and colorscheme name `dynamic`.
- Produces `plugins.mini.enable = true` (other tasks add `plugins.mini.modules.*`).

- [ ] **Step 1: Create fixtures**

`modules/nixvim/tests/fixtures/material_colors_dark.scss` (real output from this machine, trimmed to the keys used):

```scss
$darkmode: True;
$transparent: False;
$background: #0F0E0F;
$onBackground: #E9E4E8;
$surfaceContainer: #1A191B;
$surfaceContainerHigh: #201F21;
$onSurface: #E9E4E8;
$onSurfaceVariant: #ADAAAD;
$outline: #777478;
$primary: #C9C4D0;
$error: #EC7C8A;
$term0: #131214;
$term1: #E84CEB;
$term2: #FFBAC2;
$term3: #FFDCE8;
$term4: #91ADD6;
$term5: #CA98DD;
$term6: #93D0F9;
$term7: #EBD1DA;
$term8: #C7B4BB;
$term9: #FFA0F7;
$term10: #FFFCFF;
$term11: #FFFFFF;
$term12: #CADEF6;
$term13: #F8CAFF;
$term14: #F8FBFF;
$term15: #EAE3F2;
```

`material_colors_vivid.scss`: identical to the dark fixture except the line `$primary: #7C4DFF;`.

`material_colors_light.scss`:

```scss
$darkmode: False;
$transparent: False;
$background: #FDF8FA;
$onBackground: #1C1B1E;
$surfaceContainer: #F1ECEF;
$surfaceContainerHigh: #EBE6E9;
$onSurface: #1C1B1E;
$onSurfaceVariant: #49454E;
$outline: #7A757F;
$primary: #65558F;
$error: #BA1A1A;
$term0: #FDF8FA;
$term1: #B3261E;
$term2: #386A20;
$term3: #7D5700;
$term4: #3F5F90;
$term5: #7D4E7D;
$term6: #006A6A;
$term7: #1C1B1E;
$term8: #7A757F;
$term9: #DC362E;
$term10: #4C8A2F;
$term11: #A07000;
$term12: #5A7BB0;
$term13: #9A6A9A;
$term14: #1A8A8A;
$term15: #000000;
```

`material_colors_truncated.scss`: the dark fixture without its last line (`$term15: ...`).

Delete `modules/nixvim/tests/fixtures/.gitkeep`.

- [ ] **Step 2: Write the failing pure-function spec**

Create `modules/nixvim/tests/theme_spec.lua`:

```lua
-- Pure parsing and palette math of dynamic-theme (spec: Dynamic theme).
local T = require("dynamic-theme")

local function fixture(name)
	local f = assert(io.open(vim.env.SPEC_FIXTURES .. "/" .. name, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

-- parse
local dark = assert(T.parse(fixture("material_colors_dark.scss")))
assert(dark.dark == true, "darkmode True")
assert(dark.colors.term0 == "#131214", "hex lowercased: " .. tostring(dark.colors.term0))
local light = assert(T.parse(fixture("material_colors_light.scss")))
assert(light.dark == false, "darkmode False")

local p, err = T.parse("")
assert(p == nil and err == "empty", "empty file: " .. tostring(err))
p, err = T.parse("\n  \n")
assert(p == nil and err == "empty", "whitespace file")
p, err = T.parse(fixture("material_colors_truncated.scss"))
assert(p == nil and err:match("^invalid") and err:match("term15"), "truncated: " .. tostring(err))

-- rotation
assert(T.rotation("#c9c4d0") == 0, "near-grey primary does not rotate")
local rot = T.rotation("#7c4dff")
assert(rot ~= 0 and math.abs(rot) <= 15, "vivid rotation within 15: " .. rot)

-- palette invariants
local ACCENTS = { "base08", "base09", "base0A", "base0B", "base0C", "base0D", "base0E", "base0F" }
local function check(parsed, label)
	local pal, term = T.build_palette(parsed)
	for i = 0, 15 do
		local slot = string.format("base%02X", i)
		assert(type(pal[slot]) == "string" and pal[slot]:match("^#%x%x%x%x%x%x$"), label .. ": " .. slot)
	end
	assert(pal.base00 == parsed.colors.term0, label .. ": base00 equals term0")
	assert(pal.base05 == parsed.colors.onSurface, label .. ": base05 equals onSurface")
	assert(#term == 16 and term[2] == parsed.colors.term1, label .. ": term colors in order")
	assert(T.contrast(pal.base03, pal.base00) >= 3.0, label .. ": comment contrast")
	local hues = {}
	for _, slot in ipairs(ACCENTS) do
		local hex = pal[slot]
		local c = T.contrast(hex, pal.base00)
		assert(c >= 4.5, string.format("%s: %s %s contrast %.2f", label, slot, hex, c))
		local d = T.oklab_distance(hex, pal.base05)
		assert(d >= 0.08, string.format("%s: %s too close to fg (%.3f)", label, slot, d))
		local _, _, h = T.hex_to_oklch(hex)
		hues[#hues + 1] = { slot, h }
	end
	-- 25 degrees by construction; 20 allows for 8-bit rounding
	for i = 1, #hues do
		for j = i + 1, #hues do
			local diff = math.abs(((hues[j][2] - hues[i][2] + 540) % 360) - 180)
			assert(diff >= 20, string.format("%s: %s/%s hue gap %.1f", label, hues[i][1], hues[j][1], diff))
		end
	end
end
check(dark, "dark")
check(light, "light")
check(assert(T.parse(fixture("material_colors_vivid.scss"))), "vivid")
```

`git add modules/nixvim/tests`

- [ ] **Step 3: Run spec, verify it fails**

Run: `nix build .#checks.x86_64-linux.nvim-specs -L`
Expected: FAIL with `module 'dynamic-theme' not found`.

- [ ] **Step 4: Implement the Lua module**

Create `modules/nixvim/lua/dynamic-theme.lua`:

```lua
-- Wallpaper-driven colorscheme. Reads illogical-impulse's material_colors.scss
-- (written last by switchwall.sh, holds M3 roles, term0-15 and $darkmode),
-- builds a mini.base16 palette and exposes it as `:colorscheme dynamic`.
-- colors.json is deliberately ignored: it is written ~330 ms earlier by a
-- different generator and disagrees with the scss.
local M = {}

local REQUIRED = {
	"background",
	"onBackground",
	"onSurface",
	"surfaceContainer",
	"surfaceContainerHigh",
	"outline",
	"onSurfaceVariant",
	"primary",
}
for i = 0, 15 do
	REQUIRED[#REQUIRED + 1] = "term" .. i
end

-- Canonical OKLCH hues per base16 accent slot.
M.HUES = {
	base08 = 25,
	base09 = 55,
	base0A = 90,
	base0B = 145,
	base0C = 200,
	base0D = 250,
	base0E = 305,
	base0F = 0,
}

local atan2 = math.atan2 or function(y, x)
	return math.atan(y, x)
end

local function clamp(x, lo, hi)
	return math.max(lo, math.min(hi, x))
end

function M.scss_path()
	local state = vim.env.XDG_STATE_HOME
	if not state or state == "" then
		state = vim.env.HOME .. "/.local/state"
	end
	return state .. "/quickshell/user/generated/material_colors.scss"
end

function M.parse(text)
	if not text or text:match("^%s*$") then
		return nil, "empty"
	end
	local colors, dark = {}, nil
	for line in text:gmatch("[^\n]+") do
		local name, hex = line:match("^%$(%w+):%s*(#%x%x%x%x%x%x);")
		if name then
			colors[name] = hex:lower()
		end
		local mode = line:match("^%$darkmode:%s*(%a+);")
		if mode then
			dark = mode:lower() == "true"
		end
	end
	if dark == nil then
		return nil, "invalid: missing $darkmode"
	end
	for _, key in ipairs(REQUIRED) do
		if not colors[key] then
			return nil, "invalid: missing $" .. key
		end
	end
	return { dark = dark, colors = colors }
end

-- sRGB / OKLab / OKLCH conversions (Björn Ottosson's matrices).
local function hex_to_rgb(hex)
	return tonumber(hex:sub(2, 3), 16) / 255, tonumber(hex:sub(4, 5), 16) / 255, tonumber(hex:sub(6, 7), 16) / 255
end

local function rgb_to_hex(r, g, b)
	local function byte(x)
		return math.floor(clamp(x, 0, 1) * 255 + 0.5)
	end
	return string.format("#%02x%02x%02x", byte(r), byte(g), byte(b))
end

local function to_linear(c)
	return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
end

local function from_linear(c)
	return c <= 0.0031308 and c * 12.92 or 1.055 * c ^ (1 / 2.4) - 0.055
end

local function linear_to_oklab(r, g, b)
	local l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ^ (1 / 3)
	local m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ^ (1 / 3)
	local s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ^ (1 / 3)
	return 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
end

local function oklab_to_linear(L, a, b)
	local l = (L + 0.3963377774 * a + 0.2158037573 * b) ^ 3
	local m = (L - 0.1055613458 * a - 0.0638541728 * b) ^ 3
	local s = (L - 0.0894841775 * a - 1.2914855480 * b) ^ 3
	return 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
end

local function hex_to_oklab(hex)
	local r, g, b = hex_to_rgb(hex)
	return linear_to_oklab(to_linear(r), to_linear(g), to_linear(b))
end

function M.hex_to_oklch(hex)
	local L, a, b = hex_to_oklab(hex)
	return L, math.sqrt(a * a + b * b), math.deg(atan2(b, a)) % 360
end

local function in_gamut(r, g, b)
	local e = 1e-4
	return r >= -e and r <= 1 + e and g >= -e and g <= 1 + e and b >= -e and b <= 1 + e
end

-- Reduces chroma until the colour fits sRGB, keeping lightness and hue.
function M.oklch_to_hex(L, C, h)
	local rad = math.rad(h)
	local c = C
	local r, g, b = oklab_to_linear(L, c * math.cos(rad), c * math.sin(rad))
	while not in_gamut(r, g, b) and c > 0 do
		c = math.max(0, c - 0.005)
		r, g, b = oklab_to_linear(L, c * math.cos(rad), c * math.sin(rad))
	end
	return rgb_to_hex(from_linear(clamp(r, 0, 1)), from_linear(clamp(g, 0, 1)), from_linear(clamp(b, 0, 1)))
end

local function luminance(hex)
	local r, g, b = hex_to_rgb(hex)
	return 0.2126 * to_linear(r) + 0.7152 * to_linear(g) + 0.0722 * to_linear(b)
end

-- WCAG contrast ratio.
function M.contrast(a, b)
	local la, lb = luminance(a), luminance(b)
	if la < lb then
		la, lb = lb, la
	end
	return (la + 0.05) / (lb + 0.05)
end

function M.oklab_distance(x, y)
	local L1, a1, b1 = hex_to_oklab(x)
	local L2, a2, b2 = hex_to_oklab(y)
	return math.sqrt((L1 - L2) ^ 2 + (a1 - a2) ^ 2 + (b1 - b2) ^ 2)
end

local function hue_diff(from, to)
	return ((to - from + 540) % 360) - 180
end

-- One rotation for the whole hue wheel, so accent spacing never shrinks:
-- the canonical hue nearest the wallpaper primary moves onto it, capped at 15°.
function M.rotation(primary_hex)
	local _, c, ph = M.hex_to_oklch(primary_hex)
	if c < 0.03 then
		return 0
	end
	local best
	for _, h in pairs(M.HUES) do
		local d = hue_diff(h, ph)
		if not best or math.abs(d) < math.abs(best) then
			best = d
		end
	end
	return clamp(best, -15, 15)
end

local function accent(h, dark, bg, fg)
	local L, step = dark and 0.78 or 0.50, dark and 0.03 or -0.03
	local hex
	for _ = 1, 12 do
		hex = M.oklch_to_hex(L, 0.12, h)
		if M.contrast(hex, bg) >= 4.5 and M.oklab_distance(hex, fg) >= 0.08 then
			return hex
		end
		L = clamp(L + step, 0.05, 0.97)
	end
	return hex
end

function M.build_palette(parsed)
	local c, dark = parsed.colors, parsed.dark
	local fL, fC, fh = M.hex_to_oklch(c.onSurface)
	local p = {
		base00 = c.term0,
		base01 = c.surfaceContainer,
		base02 = c.surfaceContainerHigh,
		base03 = c.outline,
		base04 = c.onSurfaceVariant,
		base05 = c.onSurface,
		base06 = M.oklch_to_hex(clamp(fL + (dark and 0.05 or -0.05), 0, 1), fC, fh),
		base07 = c.onBackground,
	}
	if M.contrast(p.base03, p.base00) < 3.0 then
		local l3, c3, h3 = M.hex_to_oklch(p.base03)
		for _ = 1, 12 do
			l3 = clamp(l3 + (dark and 0.03 or -0.03), 0, 1)
			p.base03 = M.oklch_to_hex(l3, c3, h3)
			if M.contrast(p.base03, p.base00) >= 3.0 then
				break
			end
		end
	end
	local rot = M.rotation(c.primary)
	for slot, hue in pairs(M.HUES) do
		p[slot] = accent((hue + rot) % 360, dark, p.base00, p.base05)
	end
	local term = {}
	for i = 0, 15 do
		term[i + 1] = c["term" .. i]
	end
	return p, term
end

-- Runtime state -------------------------------------------------------------

M.state = nil
local warned = false

function M.read()
	local fd = io.open(M.scss_path(), "r")
	if not fd then
		return nil, "missing"
	end
	local text = fd:read("*a")
	fd:close()
	local parsed, err = M.parse(text)
	if not parsed then
		return nil, err
	end
	local palette, term = M.build_palette(parsed)
	return { dark = parsed.dark, palette = palette, term = term }
end

-- Missing or empty files are normal (no illogical-impulse, or mid-write): silent.
local function warn_once(err)
	if warned or err == "missing" or err == "empty" then
		return
	end
	warned = true
	vim.notify("dynamic-theme: " .. err .. " in " .. M.scss_path(), vim.log.levels.WARN)
end

-- Called by colors/dynamic.lua.
function M.apply()
	local s = M.state or { dark = true, palette = vim.g.dynamic_theme_fallback }
	vim.cmd("highlight clear")
	-- nil name: changing 'background' below must not re-source this scheme
	vim.g.colors_name = nil
	local bg = s.dark and "dark" or "light"
	if vim.o.background ~= bg then
		vim.o.background = bg
	end
	require("mini.base16").setup({ palette = s.palette })
	if s.term then
		for i = 0, 15 do
			vim.g["terminal_color_" .. i] = s.term[i + 1]
		end
	end
	vim.g.colors_name = "dynamic"
end

-- Keeps the last good palette on failure; a manual :colorscheme wins.
function M.reload(is_retry)
	local s, err = M.read()
	if s then
		M.state = s
		local name = vim.g.colors_name
		if name == nil or name == "dynamic" then
			vim.cmd.colorscheme("dynamic")
		end
		return true
	end
	if not is_retry then
		vim.defer_fn(function()
			M.reload(true)
		end, 500)
		return false
	end
	warn_once(err)
	return false
end

-- Watches the directory once (files are rewritten in place, never re-armed).
function M.watch()
	if M._watcher or #vim.api.nvim_list_uis() == 0 then
		return
	end
	local dir = vim.fs.dirname(M.scss_path())
	if not vim.uv.fs_stat(dir) then
		return
	end
	local ev, timer = vim.uv.new_fs_event(), vim.uv.new_timer()
	if not ev or not timer then
		return
	end
	local ok = ev:start(dir, {}, function(err, fname)
		if err or fname ~= "material_colors.scss" then
			return
		end
		timer:stop()
		-- schedule_wrap: fs_event/timer callbacks run in a fast context (E5560)
		timer:start(
			300,
			0,
			vim.schedule_wrap(function()
				M.reload(false)
			end)
		)
	end)
	if not ok then
		ev:close()
		timer:close()
		return
	end
	M._watcher = { ev = ev, timer = timer }
	vim.api.nvim_create_autocmd("VimLeavePre", {
		once = true,
		callback = function()
			if not ev:is_closing() then
				ev:stop()
				ev:close()
			end
			if not timer:is_closing() then
				timer:stop()
				timer:close()
			end
		end,
	})
end

function M.setup()
	local s, err = M.read()
	M.state = s
	if not s then
		warn_once(err)
	end
	vim.cmd.colorscheme("dynamic")
	-- UIEnter never fires headless, so checks and --headless runs never watch.
	vim.api.nvim_create_autocmd("UIEnter", { once = true, callback = M.watch })
end

return M
```

Create `modules/nixvim/colors/dynamic.lua`:

```lua
-- `:colorscheme dynamic`, see lua/dynamic-theme.lua.
require("dynamic-theme").apply()
```

Create `modules/nixvim/theme.nix`:

```nix
# Wallpaper-driven colorscheme, see lua/dynamic-theme.lua.
let
  # catppuccin-frappe base16, used until a valid material_colors.scss is read.
  fallback = {
    base00 = "#303446";
    base01 = "#292c3c";
    base02 = "#414559";
    base03 = "#51576d";
    base04 = "#626880";
    base05 = "#c6d0f5";
    base06 = "#f2d5cf";
    base07 = "#babbf1";
    base08 = "#e78284";
    base09 = "#ef9f76";
    base0A = "#e5c890";
    base0B = "#a6d189";
    base0C = "#81c8be";
    base0D = "#8caaee";
    base0E = "#ca9ee6";
    base0F = "#eebebe";
  };
in
{
  # mini.base16 ships in mini.nvim; setup() is called at runtime, not here.
  plugins.mini.enable = true;

  globals.dynamic_theme_fallback = fallback;

  extraFiles = {
    "lua/dynamic-theme.lua".source = ./lua/dynamic-theme.lua;
    "colors/dynamic.lua".source = ./colors/dynamic.lua;
  };

  # Post: runs after every plugin's setup, so ColorScheme reaches them all.
  extraConfigLuaPost = ''
    require("dynamic-theme").setup()
  '';
}
```

Add `./theme.nix` to `imports` in `modules/nixvim/default.nix`.

- [ ] **Step 5: Run spec, verify pass**

Run: `git add modules/nixvim && nix build .#checks.x86_64-linux.nvim-specs -L`
Expected: PASS for `theme_spec.lua`. If an accent assertion fails, read the printed slot/contrast and adjust only the `accent()` starting lightness (dark 0.78 / light 0.50) or step size; do not relax test thresholds.

If `plugins.mini.enable = true` without any `modules` is rejected at eval, replace it in `theme.nix` with `extraPlugins = [ pkgs.vimPlugins.mini-nvim ];` (make the file a `{ pkgs, ... }:` function), and in Task 4 delete that `extraPlugins` line when `ui.nix` enables `plugins.mini` with `modules.icons`.

- [ ] **Step 6: Write the failing runtime spec**

Create `modules/nixvim/tests/theme_state_spec.lua`:

```lua
-- Runtime behaviour: fallback, reload, keep-last-good, warnings, manual scheme.
local T = require("dynamic-theme")

local function fixture(name)
	local f = assert(io.open(vim.env.SPEC_FIXTURES .. "/" .. name, "r"))
	local text = f:read("*a")
	f:close()
	return text
end
local dir = vim.env.XDG_STATE_HOME .. "/quickshell/user/generated"
local path = dir .. "/material_colors.scss"
assert(T.scss_path() == path, "path honours XDG_STATE_HOME: " .. T.scss_path())
local function write(text)
	vim.fn.mkdir(dir, "p")
	local f = assert(io.open(path, "w"))
	f:write(text)
	f:close()
end
local function normal_bg()
	return string.format("#%06x", vim.api.nvim_get_hl(0, { name = "Normal" }).bg)
end

local notified = {}
vim.notify = function(msg, level)
	notified[#notified + 1] = { msg = msg, level = level }
end

-- 1. startup without the file: fallback palette, scheme name set, silent
assert(vim.g.colors_name == "dynamic", "colors_name at startup: " .. tostring(vim.g.colors_name))
assert(normal_bg() == vim.g.dynamic_theme_fallback.base00, "fallback bg: " .. normal_bg())
assert(T._watcher == nil, "no watcher headless")

-- 2. valid file applies, background and terminal colours follow
write(fixture("material_colors_dark.scss"))
assert(T.reload(true) == true, "reload valid")
assert(normal_bg() == "#131214", "bg = term0: " .. normal_bg())
assert(vim.o.background == "dark")
assert(vim.g.terminal_color_1 == "#e84ceb", "terminal_color_1")
assert(vim.g.colors_name == "dynamic")

-- 3. empty file (mid-write): keep last good palette, no warning
write("")
assert(T.reload(true) == false)
assert(normal_bg() == "#131214", "kept palette on empty")
assert(#notified == 0, "no warning on empty")

-- 4. invalid non-empty file: palette kept, exactly one warning
write(fixture("material_colors_truncated.scss"))
assert(T.reload(true) == false)
assert(T.reload(true) == false)
assert(normal_bg() == "#131214", "kept palette on invalid")
assert(#notified == 1 and notified[1].level == vim.log.levels.WARN, "one warning: " .. vim.inspect(notified))

-- 5. light mode flips background
write(fixture("material_colors_light.scss"))
assert(T.reload(true) == true)
assert(vim.o.background == "light", "background light")
assert(normal_bg() == "#fdf8fa")

-- 6. a manual colorscheme survives a wallpaper change
vim.cmd.colorscheme("habamax")
write(fixture("material_colors_dark.scss"))
assert(T.reload(true) == true)
assert(vim.g.colors_name == "habamax", "manual scheme kept: " .. tostring(vim.g.colors_name))
```

`git add modules/nixvim/tests/theme_state_spec.lua`

- [ ] **Step 7: Run all checks, verify pass**

Run: `nix build .#checks.x86_64-linux.nvim-specs -L && nix build .#checks.x86_64-linux.nvim -L`
Expected: PASS, `ran 4 specs`; the startup test passes (no warning without the file). If `theme_state_spec` fails at step 1 because `colors/dynamic.lua` is not found, check `nix build .#nvim && ./result/bin/nvim --headless -c 'lua print(vim.inspect(vim.api.nvim_get_runtime_file("colors/dynamic.lua", true)))' -c q`; the file must appear on the runtimepath via `extraFiles`.

- [ ] **Step 8: Commit**

```bash
nix fmt
git add modules/nixvim
git commit -m "Add wallpaper-driven dynamic colorscheme to NixVim"
```

---

### Task 4: snacks.nvim and UI plugins

**Files:**
- Create: `modules/nixvim/snacks.nix`, `modules/nixvim/ui.nix`, `modules/nixvim/tests/plugins_spec.lua`
- Modify: `modules/nixvim/default.nix` (imports)

**Interfaces:**
- Consumes: `plugins.mini.enable` from Task 3.
- Produces: global `Snacks`; plugins `bufferline`, `lualine`, `which-key`, `mini.icons` (with nvim-web-devicons mock). `plugins_spec.lua` is extended by Task 5.

- [ ] **Step 1: Write the failing spec**

Create `modules/nixvim/tests/plugins_spec.lua`:

```lua
-- Every kept plugin loads with the configured options (spec: Plugins).
local function loads(mod)
	local ok, err = pcall(require, mod)
	assert(ok, "require " .. mod .. ": " .. tostring(err))
end

-- snacks
assert(_G.Snacks ~= nil, "Snacks global")
local sc = Snacks.config
assert(sc.picker.sources.explorer.hidden == true, "explorer shows dotfiles")
assert(sc.picker.sources.files.hidden == true, "files picker shows dotfiles")
for _, name in ipairs({ "notifier", "lazygit", "bigfile", "quickfile", "words", "indent", "input", "explorer", "dashboard" }) do
	assert(sc[name] and sc[name].enabled == true, "snacks." .. name .. " enabled")
end
assert(not (sc.scroll and sc.scroll.enabled), "snacks.scroll disabled")
assert(vim.fn.executable("lazygit") == 1, "lazygit on PATH")
assert(vim.fn.executable("rg") == 1, "ripgrep on PATH")

-- ui
loads("bufferline")
loads("lualine")
loads("which-key")
loads("mini.icons")
assert(package.loaded["nvim-web-devicons"] ~= nil, "devicons mocked by mini.icons")
local lcfg = require("lualine").get_config()
assert(lcfg.options.globalstatus == true, "lualine globalstatus")
assert(lcfg.options.theme == "auto", "lualine auto theme")
```

`git add modules/nixvim/tests/plugins_spec.lua`

- [ ] **Step 2: Run spec, verify it fails**

Run: `nix build .#checks.x86_64-linux.nvim-specs -L`
Expected: FAIL with `Snacks global`.

- [ ] **Step 3: Implement snacks.nix**

```nix
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
      explorer.enabled = true;
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
            action = ":lua Snacks.picker.files({ cwd = vim.fn.expand('~/.dotfiles/modules/nixvim') })";
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
```

- [ ] **Step 4: Implement ui.nix**

```nix
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
```

Add `./snacks.nix` and `./ui.nix` to `imports`.

- [ ] **Step 5: Run checks, verify pass**

Run: `git add modules/nixvim && nix build .#checks.x86_64-linux.nvim-specs -L && nix build .#checks.x86_64-linux.nvim -L`
Expected: PASS. If `Snacks.config.picker` is nil because snacks stores merged options elsewhere, read them via `Snacks.config.get("picker", {})` in the spec (same assertions). If the startup test warns about a missing icon provider for bufferline, keep `mockDevIcons` and set `plugins.web-devicons.enable = false;`.

- [ ] **Step 6: Commit**

```bash
nix fmt
git add modules/nixvim
git commit -m "Add snacks.nvim, bufferline, lualine and which-key to NixVim"
```

---

### Task 5: Editing and workflow plugins

**Files:**
- Create: `modules/nixvim/editing.nix`, `modules/nixvim/tools.nix`
- Modify: `modules/nixvim/tests/plugins_spec.lua`, `modules/nixvim/default.nix`

**Interfaces:**
- Consumes: `plugins.mini` from Tasks 3/4.
- Produces: user commands `:Trouble`, `:GrugFar` (lazy via lz-n), `:Oil`; Lua modules `flash`, `mini.ai`, `mini.pairs`, `mini.surround`, `ts-comments`, `todo-comments`, `oil`, `gitsigns`, `persistence`. mini.surround mappings `gsa gsd gsf gsF gsh gsr gsn`.

- [ ] **Step 1: Extend the spec (failing)**

Append to `modules/nixvim/tests/plugins_spec.lua`:

```lua
-- editing
for _, mod in ipairs({ "flash", "mini.ai", "mini.pairs", "mini.surround", "ts-comments", "todo-comments", "oil" }) do
	loads(mod)
end
assert(require("mini.surround").config.mappings.add == "gsa", "surround gsa")
assert(require("oil.config").view_options.show_hidden == true, "oil shows dotfiles")

-- tools
loads("gitsigns")
loads("persistence")
assert(vim.fn.exists(":Trouble") == 2, ":Trouble command (lazy stub)")
assert(vim.fn.exists(":GrugFar") == 2, ":GrugFar command (lazy stub)")
assert(package.loaded["trouble"] == nil, "trouble lazy until used")
```

`git add modules/nixvim/tests/plugins_spec.lua`

Run: `nix build .#checks.x86_64-linux.nvim-specs -L`
Expected: FAIL with `require flash`.

- [ ] **Step 2: Implement editing.nix**

```nix
# Motions, text objects, pairs, surround, comments and directory editing.
{
  plugins.flash.enable = true;

  plugins.mini.modules = {
    ai = {
      n_lines = 500;
      custom_textobjects = {
        f.__raw = ''require("mini.ai").gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" })'';
        c.__raw = ''require("mini.ai").gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" })'';
      };
    };
    pairs = {
      modes = {
        insert = true;
        command = true;
        terminal = false;
      };
    };
    surround.mappings = {
      add = "gsa";
      delete = "gsd";
      find = "gsf";
      find_left = "gsF";
      highlight = "gsh";
      replace = "gsr";
      update_n_lines = "gsn";
    };
  };

  plugins.ts-comments.enable = true;
  plugins.todo-comments.enable = true;

  plugins.oil = {
    enable = true;
    settings.view_options.show_hidden = true;
  };
}
```

- [ ] **Step 3: Implement tools.nix**

```nix
# Git hunks, diagnostics lists, search/replace and sessions.
{
  plugins.lz-n.enable = true;

  plugins.gitsigns = {
    enable = true;
    settings.on_attach.__raw = ''
      function(buffer)
        local gs = package.loaded.gitsigns
        local function map(mode, l, r, desc)
          vim.keymap.set(mode, l, r, { buffer = buffer, desc = desc })
        end
        map("n", "]h", function() gs.nav_hunk("next") end, "Next Hunk")
        map("n", "[h", function() gs.nav_hunk("prev") end, "Prev Hunk")
        map({ "n", "x" }, "<leader>ghs", ":Gitsigns stage_hunk<CR>", "Stage Hunk")
        map({ "n", "x" }, "<leader>ghr", ":Gitsigns reset_hunk<CR>", "Reset Hunk")
        map("n", "<leader>ghS", gs.stage_buffer, "Stage Buffer")
        map("n", "<leader>ghR", gs.reset_buffer, "Reset Buffer")
        map("n", "<leader>ghp", gs.preview_hunk_inline, "Preview Hunk Inline")
        map("n", "<leader>ghb", function() gs.blame_line({ full = true }) end, "Blame Line")
        map("n", "<leader>ghd", gs.diffthis, "Diff This")
      end
    '';
  };

  # lz-n lazy loading is experimental in nixvim; drop lazyLoad if either misbehaves.
  plugins.trouble = {
    enable = true;
    lazyLoad.settings.cmd = "Trouble";
  };
  plugins.grug-far = {
    enable = true;
    lazyLoad.settings.cmd = "GrugFar";
  };

  plugins.persistence.enable = true;
}
```

Add `./editing.nix` and `./tools.nix` to `imports`.

- [ ] **Step 4: Run checks, verify pass**

Run: `git add modules/nixvim && nix build .#checks.x86_64-linux.nvim-specs -L && nix build .#checks.x86_64-linux.nvim -L`
Expected: PASS. mini.ai's treesitter textobjects need queries from nvim-treesitter-textobjects (added in Task 8); loading does not need them.

- [ ] **Step 5: Commit**

```bash
nix fmt
git add modules/nixvim
git commit -m "Add editing and workflow plugins to NixVim"
```

---

### Task 6: Keymaps and which-key groups

**Files:**
- Create: `modules/nixvim/keymaps.nix`, `modules/nixvim/tests/keymaps_spec.lua`
- Modify: `modules/nixvim/default.nix`

**Interfaces:**
- Consumes: `Snacks` (Task 4), flash/persistence/oil/`:Trouble`/`:GrugFar` (Task 5), `require("conform")` (Task 8; only called when the key is pressed).
- Produces: global Lua function `nixvim_root() -> string` (git root or cwd); augroup `nixvim_lsp_keymaps` on `LspAttach`; toggles `vim.g.disable_autoformat` / `vim.b.disable_autoformat` read by Task 8's conform `format_on_save`.

- [ ] **Step 1: Write the failing spec**

Create `modules/nixvim/tests/keymaps_spec.lua`:

```lua
-- LazyVim-compatible keymaps (spec: Keymaps).
local function has(lhs, mode)
	return vim.fn.maparg(lhs, mode) ~= ""
end

local normal = {
	"<leader><space>", "<leader>/", "<leader>,", "<leader>:",
	"<leader>ff", "<leader>fr", "<leader>fc",
	"<leader>sg", "<leader>sw", "<leader>sh", "<leader>sk", "<leader>sd", "<leader>ss", "<leader>sR", "<leader>sr",
	"<leader>e", "<leader>E", "-",
	"<leader>gg", "<leader>gb", "<leader>gl",
	"[d", "]d", "[e", "]e", "[w", "]w",
	"<S-h>", "<S-l>", "[b", "]b", "<leader>bd", "<leader>bo", "<leader>bb",
	"<C-h>", "<C-j>", "<C-k>", "<C-l>", "<leader>-", "<leader>|", "<leader>wd",
	"<leader>uf", "<leader>uF", "<leader>uw", "<leader>ul", "<leader>ud", "<leader>un",
	"<leader>qq", "<leader>qs", "<leader>ql", "<leader>qd",
	"<leader>xx", "<leader>xX", "<leader>cs", "<leader>cf", "<leader>cd",
	"s", "S", "<C-s>", "<A-j>", "<A-k>",
}
for _, lhs in ipairs(normal) do
	assert(has(lhs, "n"), "missing normal map " .. lhs)
end
for _, lhs in ipairs({ "<C-h>", "<C-j>", "<C-k>", "<C-l>" }) do
	assert(has(lhs, "t"), "missing terminal map " .. lhs)
end
assert(not has("<C-h>", "i"), "window nav must not map insert mode")
assert(has("<leader>sw", "x") and has("<leader>cf", "x"), "visual variants")
assert(has("<", "v") and has(">", "v"), "indent keeps selection")
assert(has("<C-s>", "i"), "save in insert")

assert(type(_G.nixvim_root) == "function" and type(nixvim_root()) == "string", "nixvim_root")

-- format toggles flip the flags conform reads
vim.fn.maparg("<leader>uF", "n", false, true).callback()
assert(vim.g.disable_autoformat == true, "<leader>uF disables globally")
vim.fn.maparg("<leader>uF", "n", false, true).callback()
assert(not vim.g.disable_autoformat, "<leader>uF re-enables")
vim.fn.maparg("<leader>uf", "n", false, true).callback()
assert(vim.b.disable_autoformat == true, "<leader>uf disables for buffer")

-- LSP maps are buffer-local on LspAttach
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_exec_autocmds("LspAttach", { buffer = buf, data = { client_id = 0 } })
for _, lhs in ipairs({ "gd", "gr", "gI", "gy", "gD", "K", "gK", "<leader>ca", "<leader>cr" }) do
	assert(vim.fn.maparg(lhs, "n", false, true).buffer == 1, "buffer-local LSP map " .. lhs)
end
```

`git add modules/nixvim/tests/keymaps_spec.lua`

Run: `nix build .#checks.x86_64-linux.nvim-specs -L`
Expected: FAIL with `missing normal map <leader><space>`.

- [ ] **Step 2: Implement keymaps.nix**

```nix
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
  diag = count: severity: fn "vim.diagnostic.jump({ count = ${count}, severity = ${severity}, float = true })";
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
    (map "n" "<leader><space>" (fn "Snacks.picker.files({ cwd = nixvim_root() })") "Find Files (Root Dir)")
    (map "n" "<leader>/" (fn "Snacks.picker.grep({ cwd = nixvim_root() })") "Grep (Root Dir)")
    (map "n" "<leader>," (fn "Snacks.picker.buffers()") "Buffers")
    (map "n" "<leader>:" (fn "Snacks.picker.command_history()") "Command History")
    (map "n" "<leader>ff" (fn "Snacks.picker.files({ cwd = nixvim_root() })") "Find Files (Root Dir)")
    (map "n" "<leader>fr" (fn "Snacks.picker.recent()") "Recent")
    (map "n" "<leader>fc" (fn "Snacks.picker.files({ cwd = vim.fn.expand('~/.dotfiles/modules/nixvim') })") "Find Config File")
    (map "n" "<leader>sg" (fn "Snacks.picker.grep({ cwd = nixvim_root() })") "Grep (Root Dir)")
    (map [ "n" "x" ] "<leader>sw" (fn "Snacks.picker.grep_word({ cwd = nixvim_root() })") "Word (Root Dir)")
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
    (map "n" "<leader>xX" "<cmd>Trouble diagnostics toggle filter.buf=0<cr>" "Buffer Diagnostics (Trouble)")
    (map "n" "<leader>cs" "<cmd>Trouble symbols toggle<cr>" "Symbols (Trouble)")
    (map [ "n" "x" ] "<leader>cf" (fn ''require("conform").format({ lsp_format = "fallback" })'') "Format")

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
    (map "t" "<C-h>" "<cmd>wincmd h<cr>" "Go to Left Window")
    (map "t" "<C-j>" "<cmd>wincmd j<cr>" "Go to Lower Window")
    (map "t" "<C-k>" "<cmd>wincmd k<cr>" "Go to Upper Window")
    (map "t" "<C-l>" "<cmd>wincmd l<cr>" "Go to Right Window")
    (map "n" "<leader>-" "<C-W>s" "Split Window Below")
    (map "n" "<leader>|" "<C-W>v" "Split Window Right")
    (map "n" "<leader>wd" "<C-W>c" "Delete Window")

    # ui toggles
    (map "n" "<leader>uf" (fn "vim.b.disable_autoformat = not vim.b.disable_autoformat") "Toggle Format on Save (Buffer)")
    (map "n" "<leader>uF" (fn "vim.g.disable_autoformat = not vim.g.disable_autoformat") "Toggle Format on Save (Global)")
    (map "n" "<leader>uw" (fn "vim.wo.wrap = not vim.wo.wrap") "Toggle Wrap")
    (map "n" "<leader>ul" (fn "vim.wo.number = not vim.wo.number; vim.wo.relativenumber = vim.wo.number") "Toggle Line Numbers")
    (map "n" "<leader>ud" (fn "vim.diagnostic.enable(not vim.diagnostic.is_enabled())") "Toggle Diagnostics")
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

    # misc
    (map [ "n" "i" "x" "s" ] "<C-s>" "<cmd>w<cr><esc>" "Save File")
    (map [ "n" "i" ] "<esc>" "<cmd>noh<cr><esc>" "Escape and Clear hlsearch")
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
          local function map(mode, lhs, rhs, desc)
            vim.keymap.set(mode, lhs, rhs, { buffer = event.buf, desc = desc })
          end
          map("n", "gd", function() Snacks.picker.lsp_definitions() end, "Goto Definition")
          map("n", "gr", function() Snacks.picker.lsp_references() end, "References")
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
```

Add `./keymaps.nix` to `imports`.

- [ ] **Step 3: Run checks, verify pass**

Run: `git add modules/nixvim && nix build .#checks.x86_64-linux.nvim-specs -L && nix build .#checks.x86_64-linux.nvim -L`
Expected: PASS. If `keymaps` rejects a list for `mode`, it is accepted by nixvim (`mode` takes string or list); if a `"c"`-mode map with a `__raw` action fails, change that entry's action to `"<cmd>lua require('flash').toggle()<cr>"`.

- [ ] **Step 4: Commit**

```bash
nix fmt
git add modules/nixvim
git commit -m "Add LazyVim-compatible keymaps to NixVim"
```

---

### Task 7: Completion and snippets

**Files:**
- Move: `config/nvim/lua/snippets/` → `modules/nixvim/snippets/` (`git mv`)
- Create: `modules/nixvim/completion.nix`, `modules/nixvim/lua/snippet_util.lua`, `modules/nixvim/tests/completion_spec.lua`
- Modify: `modules/nixvim/snippets/tex/*.lua` (condition helpers only), `modules/nixvim/default.nix`

**Interfaces:**
- Produces Lua module `snippet_util`: `in_mathzone() -> boolean`, `in_env(name: string) -> boolean` (both `false` when vimtex is absent).
- Produces `plugins.blink-cmp.settings.sources.default = [ "lsp" "path" "snippets" "buffer" ]` (Task 8 adds a lua-only `lazydev` provider).

- [ ] **Step 1: Move snippets**

```bash
git mv config/nvim/lua/snippets modules/nixvim/snippets
```

- [ ] **Step 2: Write the failing spec**

Create `modules/nixvim/tests/completion_spec.lua`:

```lua
-- blink.cmp + LuaSnip with the custom snippet library (spec: Completion and snippets).
local ls = require("luasnip")

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")

-- custom tex snippets and autosnippets load for tex buffers
vim.cmd.edit(tmp .. "/a.tex")
vim.wait(100)
local found = false
for _, s in ipairs(ls.get_snippets("tex", { type = "autosnippets" }) or {}) do
	if s.trigger == ";la" then
		found = true
	end
end
assert(found, "tex autosnippet ;la loaded")

-- vimtex-dependent conditions are safe without vimtex (phase 1)
local util = require("snippet_util")
assert(util.in_mathzone() == false, "in_mathzone false without vimtex")
assert(util.in_env("itemize") == false, "in_env false without vimtex")

-- custom lua snippets
vim.cmd.edit(tmp .. "/a.lua")
vim.wait(100)
assert(#(ls.get_snippets("lua") or {}) > 0, "lua snippets loaded")

-- friendly-snippets (python has only friendly-snippets)
vim.cmd.edit(tmp .. "/a.py")
vim.wait(100)
assert(#(ls.get_snippets("python") or {}) > 0, "friendly-snippets loaded for python")

-- blink config
local cfg = require("blink.cmp.config")
assert(cfg.snippets.preset == "luasnip", "blink uses luasnip")
assert(cfg.completion.list.selection.preselect == false, "no preselect")
for _, key in ipairs({ "<CR>", "<C-j>", "<C-l>", "<C-k>", "<C-f>", "<C-d>", "<C-u>", "<Tab>", "<S-Tab>", "<C-space>", "<C-e>" }) do
	assert(cfg.keymap[key] ~= nil, "blink key " .. key)
end
local srcs = table.concat(cfg.sources.default, ",")
assert(srcs == "lsp,path,snippets,buffer", "sources: " .. srcs)
```

`git add modules/nixvim/tests/completion_spec.lua modules/nixvim/snippets`

Run: `nix build .#checks.x86_64-linux.nvim-specs -L`
Expected: FAIL with `module 'luasnip' not found`.

- [ ] **Step 3: Add the vimtex-safe helper and patch tex snippet conditions**

Create `modules/nixvim/lua/snippet_util.lua`:

```lua
-- vimtex-backed snippet conditions that return false instead of erroring
-- when vimtex is not installed or not loaded for the buffer.
local M = {}

function M.in_mathzone()
	local ok, res = pcall(vim.fn["vimtex#syntax#in_mathzone"])
	return ok and res == 1
end

function M.in_env(name)
	local ok, res = pcall(vim.fn["vimtex#env#is_inside"], name)
	return ok and type(res) == "table" and res[1] > 0 and res[2] > 0
end

return M
```

Replace the local `env` and `math` definitions in every tex snippet file:

```bash
for f in modules/nixvim/snippets/tex/*.lua; do
  perl -0pi -e 's/local env = function\(name\)\n.*?\nend\nlocal math = make_condition\(function\(\)\n.*?\nend\)\n/local util = require("snippet_util")\nlocal env = util.in_env\nlocal math = make_condition(util.in_mathzone)\n/s' "$f"
done
grep -rn 'vimtex#' modules/nixvim/snippets && echo "UNPATCHED FILES ABOVE" || echo "all patched"
grep -c 'require("snippet_util")' modules/nixvim/snippets/tex/*.lua
```

Expected: `all patched`, and each of the six files reports `1`.

- [ ] **Step 4: Implement completion.nix**

```nix
# blink.cmp completion with LuaSnip (custom library in ./snippets + friendly-snippets).
{
  plugins.friendly-snippets.enable = true;

  plugins.luasnip = {
    enable = true;
    settings.enable_autosnippets = true;
    fromVscode = [ { } ];
    fromLua = [ { paths = ./snippets; } ];
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
        "<CR>" = [
          {
            __raw = ''
              function(cmp)
                if cmp.get_selected_item() then
                  return cmp.accept()
                end
              end
            '';
          }
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
        "<C-k>" = [
          "select_and_accept"
          "show"
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
```

Add `./completion.nix` to `imports`.

- [ ] **Step 5: Run checks, verify pass**

Run: `git add modules/nixvim && nix build .#checks.x86_64-linux.nvim-specs -L && nix build .#checks.x86_64-linux.nvim -L`
Expected: PASS. If `fromLua`'s `paths` must be a string, use `paths = "${./snippets}";`. If the tex autosnippet is not found because the lazy loader has not fired, add `vim.cmd("doautocmd FileType")` before the lookup in the spec, not an eager load in the config. If `require("blink.cmp.config")` is not a plain table in this blink version, read the same fields from `require("blink.cmp.config").get()`.

- [ ] **Step 6: Commit**

```bash
nix fmt
git add -A modules/nixvim config/nvim
git commit -m "Add blink.cmp and LuaSnip with custom snippets to NixVim"
```

---

### Task 8: Language base, nix and lua

**Files:**
- Create: `modules/nixvim/lang/default.nix`, `modules/nixvim/lang/nix-lua.nix`, `modules/nixvim/tests/lsp_spec.lua`
- Modify: `modules/nixvim/default.nix`

**Interfaces:**
- Consumes: `vim.g.disable_autoformat` / `vim.b.disable_autoformat` (Task 6), `plugins.blink-cmp.settings.sources` (Task 7).
- Produces: `plugins.conform-nvim.settings.formatters_by_ft`, `plugins.lint.lintersByFt` and `lsp.servers` as the extension points phase 2 language files add to; all treesitter grammars for phase 1 and 2.

- [ ] **Step 1: Write the failing spec**

Create `modules/nixvim/tests/lsp_spec.lua`:

```lua
-- LSP, formatting and treesitter base with nix + lua (spec: Languages).
for _, bin in ipairs({ "nixd", "lua-language-server", "nixfmt", "stylua" }) do
	assert(vim.fn.executable(bin) == 1, bin .. " on PATH")
end
assert(vim.lsp.config.nixd ~= nil, "nixd configured")
assert(vim.lsp.config.lua_ls ~= nil, "lua_ls configured")
assert(vim.lsp.is_enabled("nixd"), "nixd enabled")
assert(vim.lsp.is_enabled("lua_ls"), "lua_ls enabled")

-- every grammar for phase 1 and 2 is bundled
local grammars = {
	"nix", "lua", "luadoc", "luap", "vim", "vimdoc", "query", "regex", "bash", "diff",
	"gitcommit", "git_rebase", "gitignore", "markdown", "markdown_inline", "typescript",
	"tsx", "javascript", "jsdoc", "html", "css", "json", "yaml", "toml", "python", "rust",
	"go", "gomod", "gosum", "gowork", "java", "latex", "bibtex", "dockerfile",
}
for _, lang in ipairs(grammars) do
	assert(vim.treesitter.language.add(lang), "grammar " .. lang)
end

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")

-- treesitter highlighting starts for nix
vim.fn.writefile({ "{a=1;}" }, tmp .. "/a.nix")
vim.cmd.edit(tmp .. "/a.nix")
local buf = vim.api.nvim_get_current_buf()
assert(vim.treesitter.highlighter.active[buf] ~= nil, "treesitter highlight active for nix")

-- conform formats nix with nixfmt
require("conform").format({ bufnr = buf, async = false, lsp_format = "never" })
local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
assert(text == "{ a = 1; }", "nixfmt result: " .. text)

-- format on save runs, and the global toggle stops it
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "{b=2;}" })
vim.cmd.write()
assert(vim.fn.readfile(tmp .. "/a.nix")[1] == "{ b = 2; }", "formatted on save")
vim.g.disable_autoformat = true
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "{c=3;}" })
vim.cmd.write()
assert(vim.fn.readfile(tmp .. "/a.nix")[1] == "{c=3;}", "toggle disables format on save")
vim.g.disable_autoformat = nil

-- lazydev completion source only for lua
local cfg = require("blink.cmp.config")
assert(cfg.sources.providers.lazydev ~= nil, "lazydev provider")
```

`git add modules/nixvim/tests/lsp_spec.lua`

Run: `nix build .#checks.x86_64-linux.nvim-specs -L`
Expected: FAIL with `nixd on PATH`.

- [ ] **Step 2: Implement lang/default.nix**

```nix
# Language plumbing shared by lang/*.nix: LSP, formatting, linting, treesitter.
{ config, ... }:
{
  imports = [
    ./nix-lua.nix
  ];

  # Upstream server defaults for the top-level `lsp` module (vim.lsp.config/enable).
  plugins.lspconfig.enable = true;

  extraConfigLua = ''
    vim.diagnostic.config({
      virtual_text = true,
      severity_sort = true,
      float = { border = "rounded" },
    })
  '';

  plugins.conform-nvim = {
    enable = true;
    settings = {
      default_format_opts.lsp_format = "fallback";
      # Toggled by <leader>uf / <leader>uF (keymaps.nix).
      format_on_save.__raw = ''
        function(bufnr)
          if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
            return
          end
          return { timeout_ms = 500, lsp_format = "fallback" }
        end
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
      callback.__raw = ''function() require("lint").try_lint() end'';
    }
  ];

  plugins.treesitter = {
    enable = true;
    settings = {
      highlight.enable = true;
      indent.enable = true;
    };
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
```

- [ ] **Step 3: Implement lang/nix-lua.nix**

```nix
# nix and lua: this repo's own languages.
{ pkgs, ... }:
{
  lsp.servers = {
    nixd.enable = true;
    lua_ls = {
      enable = true;
      config.settings.Lua = {
        workspace.checkThirdParty = false;
        completion.callSnippet = "Replace";
      };
    };
  };

  plugins.lazydev.enable = true;
  plugins.blink-cmp.settings.sources = {
    per_filetype.lua = {
      __unkeyed-1 = "lazydev";
      inherit_defaults = true;
    };
    providers.lazydev = {
      name = "LazyDev";
      module = "lazydev.integrations.blink";
      score_offset = 100;
    };
  };

  plugins.conform-nvim.settings.formatters_by_ft = {
    nix = [ "nixfmt" ];
    lua = [ "stylua" ];
  };

  extraPackages = with pkgs; [
    nixfmt
    stylua
  ];
}
```

Add `./lang` to `imports` in `modules/nixvim/default.nix`.

- [ ] **Step 4: Run checks, verify pass**

Run: `git add modules/nixvim && nix build .#checks.x86_64-linux.nvim-specs -L && nix build .#checks.x86_64-linux.nvim -L`
Expected: PASS, `ran 8 specs`.

Known fallbacks, apply only on the matching failure:
- Evaluation error `attribute '<name>' missing` in `grammarPackages`: that grammar was renamed or dropped in nixpkgs. Remove it from both `grammarPackages` and the spec's `grammars` list, and note it in the commit subject (e.g. "... (no luap grammar)").
- `treesitter highlight active for nix` fails: the packaged nvim-treesitter does not auto-start highlighting. Add to `lang/default.nix`:
  ```nix
  autoGroups.nixvim_ts_start.clear = true;
  autoCmd = [
    {
      event = "FileType";
      group = "nixvim_ts_start";
      callback.__raw = "function(ev) pcall(vim.treesitter.start, ev.buf) end";
    }
  ];
  ```
  (merge into the existing `autoCmd` list).
- `vim.lsp.config.nixd` nil or servers not enabled: run `nix build .#nvim && ./result/bin/nixvim-print-init | grep -n -A5 nixd` and align `lsp.servers.<name>` option names (`enable`, `config`) with what nixvim generates; if the top-level `lsp` module cannot enable them, switch both servers to legacy `plugins.lsp = { enable = true; servers.nixd.enable = true; servers.lua_ls.enable = true; };` (spec: Languages allows this fallback).

- [ ] **Step 5: Commit**

```bash
nix fmt
git add modules/nixvim
git commit -m "Add LSP, formatting and treesitter base with nix and lua to NixVim"
```

---

### Task 9: Cut over home-manager and remove LazyVim

**Files:**
- Modify: `modules/home/neovim.nix` (rewrite), `justfile`, `README.md:45-48`, `docs/MIGRATION-NOTES.md:53-63,127-133`
- Move: `config/nvim/stylua.toml` → `modules/nixvim/stylua.toml`
- Delete: rest of `config/nvim/`

**Interfaces:**
- Consumes: `inputs.self.packages.<system>.nvim` (Task 1). `inputs` reaches home modules through `extraSpecialArgs` in `lib/mk-host.nix`.

- [ ] **Step 1: Check nothing else configures neovim**

Run: `grep -rn "programs.neovim\|config/nvim" --include=*.nix . ; grep -rn "config/nvim" docs README.md justfile scripts`
Expected: hits only in `modules/home/neovim.nix`, `README.md`, `docs/MIGRATION-NOTES.md`. Any other hit must be handled in this task too.

- [ ] **Step 2: Rewrite modules/home/neovim.nix**

```nix
# Installs the standalone NixVim build (modules/nixvim, flake output
# packages.<system>.nvim). Plugins, LSP servers and formatters live inside
# that package; nothing is linked into ~/.config/nvim.
{
  inputs,
  pkgs,
  ...
}:
{
  home.packages = [ inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.nvim ];

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
```

- [ ] **Step 3: Remove the old config**

```bash
git mv config/nvim/stylua.toml modules/nixvim/stylua.toml
git rm -r config/nvim
ls config
```

Expected: `config/nvim` gone; `config/zsh` remains.

- [ ] **Step 4: Update docs and justfile**

`justfile`: after the `sops-edit` recipe add:

```just
# Runs the NixVim build from this checkout without switching, e.g. `just nvim flake.nix`.
nvim *ARGS:
    nix run .#nvim -- {{ ARGS }}
```

`README.md`: replace the line `config/nvim/  config/zsh/     vendored dotfiles` with:

```
modules/nixvim/               standalone NixVim editor config (packages.nvim)
config/zsh/                   vendored dotfiles
```

`docs/MIGRATION-NOTES.md`: replace the whole section `## Neovim: \`lazyvim.json\` is read-only, mason disabled` (heading through the paragraph ending "conflict with the Nix-provided binaries.") with:

```markdown
## Neovim: NixVim build, no LazyVim, no Mason

Neovim is a standalone NixVim build (`modules/nixvim/`, flake output
`packages.x86_64-linux.nvim`), installed by `modules/home/neovim.nix`.
Plugins, LSP servers, formatters and treesitter grammars are all inside
that package; nothing is downloaded at runtime and `~/.config/nvim` is
unused. Try changes without switching: `just nvim <file>`. Specs:
`nix build .#checks.x86_64-linux.nvim-specs -L`.

Colors follow the wallpaper: `modules/nixvim/lua/dynamic-theme.lua`
reads `~/.local/state/quickshell/user/generated/material_colors.scss`
and reloads when illogical-impulse rewrites it. Without that file the
editor uses a built-in catppuccin-frappe palette.

After the first switch, delete LazyVim leftovers once:
`rm -rf ~/.config/nvim ~/.local/share/nvim/lazy ~/.local/state/nvim/lazy`.
```

In the section `## rust-analyzer via rustup, not a standalone package`, replace the sentence fragment "so\n`modules/home/neovim.nix` does not install that package." with "so\nneither `modules/home/` nor the NixVim build installs that package." (keep the rest).

- [ ] **Step 5: Verify the whole flake**

Run:

```bash
git add -A
nix build .#checks.x86_64-linux.nvim-specs -L
nix build .#checks.x86_64-linux.nvim -L
nix path-info -r .#nvim | grep -Ei 'lazy-nvim|lazyvim|mason' && echo "FORBIDDEN PLUGIN IN CLOSURE" || echo "closure clean"
for h in tariognatha tarmantria taractias; do
  nix build ".#nixosConfigurations.$h.config.system.build.toplevel" --dry-run || exit 1
done
nix flake check --no-build
```

Expected: specs and startup test pass; `closure clean`; three dry-runs succeed; `nix flake check --no-build` succeeds (evaluates `lua-syntax` and all checks). If a host fails with a `buildEnv` collision on `bin/nvim`/`bin/vi`/`bin/vim`, something else still installs neovim or vim; find it with `grep -rn "neovim\|vim" modules/home/*.nix modules/nixos/*.nix` and remove the duplicate.

- [ ] **Step 6: Commit**

```bash
nix fmt
git add -A
git commit -m "Switch Neovim to the NixVim build and remove LazyVim"
```

---

### Task 10: Manual verification on the live desktop (user)

Not automatable (needs the Hyprland session, kitty and a wallpaper switch). Hand this checklist to the user after merging the branch and running `sudo nixos-rebuild switch --flake ~/.dotfiles#<host>`:

- [ ] `rm -rf ~/.config/nvim ~/.local/share/nvim/lazy ~/.local/state/nvim/lazy`
- [ ] Open `nvim flake.nix` in kitty: dashboard shows, colours match the kitty background exactly (no seam), `:colorscheme` prints `dynamic`.
- [ ] Switch wallpaper in Quickshell: every open nvim recolours within ~1 s, no notification.
- [ ] Toggle light/dark in Quickshell: `:set background?` follows.
- [ ] `:terminal`: colours match kitty.
- [ ] `:colorscheme habamax`, switch wallpaper: habamax stays.
- [ ] `<leader><space>`, `<leader>/`, `<leader>e`, `-`, `<leader>gg`, `s` (flash), `gsa` (surround), `<S-h>/<S-l>` all work; which-key shows group names after `<leader>`.
- [ ] In a `.nix` file: `:checkhealth vim.lsp` shows nixd attached; `gd`, `K` work; saving formats; `<leader>uf` stops formatting.
- [ ] In a `.lua` file: lua_ls attached, `vim.` completions show via blink, `<CR>` without selection inserts a newline.
- [ ] In a `.tex` file: `;la` autosnippet expands, a friendly-snippet expands via `<C-j>`, `<C-j>`/`<C-l>` jump through fields. (Math-mode-only snippets stay inactive until vimtex lands in phase 2.)
- [ ] Yank flashes a highlight; reopening a file restores the cursor; `q` closes `:help`.
```
