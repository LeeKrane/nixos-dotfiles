# NixVim Migration Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the remaining language stacks (data, web, python, go, rust, java, tex, markdown, docker/shell) to the NixVim build from phase 1, each with LSP, formatter, linter and language plugins from Nix.

**Architecture:** One file per language in `modules/nixvim/lang/`, imported from `lang/default.nix`, each adding to the extension points phase 1 created: `lsp.servers`, `plugins.conform-nvim.settings.formatters_by_ft`, `plugins.lint.lintersByFt`, `extraPackages`. Each language gets a headless spec `modules/nixvim/tests/lang_<name>_spec.lua` run by `checks.x86_64-linux.nvim-specs`.

**Tech Stack:** NixVim (`main`), Neovim 0.12, conform.nvim, nvim-lint, rustaceanvim, nvim-jdtls, vimtex, render-markdown, markdown-preview, venv-selector, crates.nvim, SchemaStore.nvim.

**Spec:** `docs/superpowers/specs/2026-09-23-nixvim-migration-design.md` (section Languages). Prerequisite: `docs/superpowers/plans/2026-09-23-nixvim-phase1.md` fully implemented and merged.

## Global Constraints

- All phase 1 Global Constraints apply (commit style, no push/PR, `git add` before `nix build`, `nix fmt`, `command cat`).
- Never bundle rust-analyzer: `dependencies.rust-analyzer.enable = false`; rustaceanvim uses rustup's `rust-analyzer` from `$PATH`.
- Toolchains stay outside the editor: `go` (added to `modules/home/dev.nix` in Task 4), `rustup`, `jdk21`, `nodejs_22`, `texliveMedium` (already in `modules/home/dev.nix`). Do not add them to `extraPackages`.
- Do not bundle TeX into the editor closure: `plugins.vimtex.texlivePackage = null`. Only the small `latexindent` environment is bundled.
- Formatters and linters go in `extraPackages`, server binaries come from the `lsp` module's per-server package defaults.
- Server package names, if an override is ever needed: `dockerls` → `pkgs.dockerfile-language-server`, `bashls` → `pkgs.bash-language-server`, `ts_ls` → `pkgs.typescript-language-server`, `yamlls` → `pkgs.yaml-language-server`, `html`/`cssls`/`jsonls` → `pkgs.vscode-langservers-extracted`.
- Nix and Lua languages and the whole treesitter grammar set were done in phase 1; do not touch them.

## Before starting: carry over phase 1 outcomes

Phase 1 had fallbacks. Before Task 1, read the phase 1 git log and `modules/nixvim/lang/default.nix` and record which were taken, because the code below assumes the primary paths:

1. **LSP wiring**: if phase 1 fell back to legacy `plugins.lsp.servers.<name>.enable` instead of `lsp.servers.<name>.enable`, use the same legacy form in every task below (replace `lsp.servers.X = { enable = true; config.settings = ...; }` by `plugins.lsp.servers.X = { enable = true; settings = ...; }`), and in specs replace `vim.lsp.is_enabled("X")` checks by `vim.lsp.config.X ~= nil` only.
2. **Treesitter start autocmd**: if phase 1 added the `nixvim_ts_start` FileType autocmd, Task 7 must also exclude `tex`/`latex` there (see Task 7 Step 3).
3. **Dropped grammars**: if phase 1 removed a grammar, the language task using it relies on vim syntax instead; do not re-add it.

## Spec helpers (repeated verbatim in every language spec)

Every `lang_*_spec.lua` starts with this block (each spec runs in its own fresh nvim, so it cannot be shared via `require` without adding a runtime file; repeating 25 lines is simpler):

```lua
local function on_path(bins)
	for _, bin in ipairs(bins) do
		assert(vim.fn.executable(bin) == 1, bin .. " on PATH")
	end
end
local function servers(names)
	for _, name in ipairs(names) do
		assert(vim.lsp.config[name] ~= nil, name .. " configured")
		assert(vim.lsp.is_enabled(name), name .. " enabled")
	end
end
local function formats(ext, input, expected, formatters)
	local path = vim.fn.tempname() .. "." .. ext
	vim.fn.writefile(vim.split(input, "\n"), path)
	vim.cmd.edit(path)
	require("conform").format({ bufnr = 0, async = false, lsp_format = "never", formatters = formatters })
	local got = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
	assert(got == expected, ext .. " formatted to " .. vim.inspect(got))
end
local function ft_formatters(ft, want)
	local got = table.concat(require("conform").formatters_by_ft[ft] or {}, ",")
	assert(got == table.concat(want, ","), ft .. " formatters: " .. got)
end
```

## Review Focus

1. **rust-analyzer silently bundled** (rustaceanvim's dependency default) — expect none in the closure and rustup's binary used. Pinned by `lang_rust_spec.lua` and the closure check in Task 10.
2. **LaTeX math-mode snippets** — expect `$...$` autosnippets to fire now that vimtex is present; requires vimtex syntax, so treesitter highlight must be off for latex. Pinned by `lang_tex_spec.lua` (in_mathzone true inside `$ $`).
3. **Formatter surprises on save in foreign repos** — expect formatters to be exactly those in the spec table per filetype, nothing extra. Pinned by `ft_formatters` assertions in every language spec.
4. **prettierd/latexindent need a writable HOME or perl deps in the sandbox** — expect format round-trips to pass headless. Pinned by `formats(...)` in web, data, markdown and tex specs (fallbacks noted per task).
5. **gopls without `go`** — expect `go` on the user's PATH after the switch. Pinned by the Task 4 dev.nix change and the Task 10 manual check (the sandbox has no `go`, so specs only check configuration).

---

## File Structure

```
modules/nixvim/lang/default.nix     imports list grows by one file per task
modules/nixvim/lang/data.nix        jsonls, yamlls (+SchemaStore), taplo, prettierd
modules/nixvim/lang/web.nix         ts_ls, tailwindcss, html, cssls, prettierd, ts-autotag
modules/nixvim/lang/python.nix      basedpyright, ruff, venv-selector
modules/nixvim/lang/go.nix          gopls, gofumpt, goimports, golangci-lint
modules/nixvim/lang/rust.nix        rustaceanvim (rustup rust-analyzer), crates.nvim
modules/nixvim/lang/java.nix        nvim-jdtls
modules/nixvim/lang/tex.nix         texlab, vimtex, latexindent
modules/nixvim/lang/markdown.nix    marksman, prettierd, render-markdown, markdown-preview
modules/nixvim/lang/docker-shell.nix dockerls, hadolint, bashls, shellcheck, shfmt
modules/nixvim/tests/lang_*_spec.lua one spec per language file
modules/home/dev.nix                + go
docs/MIGRATION-NOTES.md             Go note
```

---

### Task 1: Data (JSON, YAML, TOML)

**Files:**
- Create: `modules/nixvim/lang/data.nix`, `modules/nixvim/tests/lang_data_spec.lua`
- Modify: `modules/nixvim/lang/default.nix` (imports)

**Interfaces:**
- Consumes: `lsp.servers`, `plugins.conform-nvim.settings.formatters_by_ft` (phase 1 Task 8).
- Produces: `prettierd` in `extraPackages` (Tasks 2 and 8 also list it; duplicates in `extraPackages` are harmless).

- [ ] **Step 1: Write the failing spec**

Create `modules/nixvim/tests/lang_data_spec.lua`: the helper block from "Spec helpers", then:

```lua
-- JSON, YAML, TOML (spec: Languages, data row).
on_path({ "vscode-json-language-server", "yaml-language-server", "taplo", "prettierd" })
servers({ "jsonls", "yamlls", "taplo" })

local json_schemas = vim.lsp.config.jsonls.settings.json.schemas
assert(type(json_schemas) == "table" and #json_schemas > 50, "jsonls has SchemaStore schemas")
local yaml = vim.lsp.config.yamlls.settings.yaml
assert(yaml.schemaStore.enable == false, "yamlls built-in schema store off")
assert(type(yaml.schemas) == "table" and next(yaml.schemas) ~= nil, "yamlls has SchemaStore schemas")

ft_formatters("json", { "prettierd" })
ft_formatters("jsonc", { "prettierd" })
ft_formatters("yaml", { "prettierd" })
ft_formatters("toml", { "taplo" })

formats("toml", "a=1", "a = 1")
formats("json", '{"a":1}', '{ "a": 1 }')
```

`git add modules/nixvim/tests/lang_data_spec.lua`

Run: `nix build .#checks.x86_64-linux.nvim-specs -L`
Expected: FAIL with `vscode-json-language-server on PATH`.

- [ ] **Step 2: Implement data.nix**

```nix
# JSON, YAML and TOML.
{ pkgs, ... }:
{
  # Schemas set explicitly: nixvim's plugins.schemastore wires only legacy plugins.lsp servers.
  extraPlugins = [ pkgs.vimPlugins.SchemaStore-nvim ];

  lsp.servers = {
    jsonls = {
      enable = true;
      config.settings.json = {
        schemas.__raw = ''require("schemastore").json.schemas()'';
        validate.enable = true;
      };
    };
    yamlls = {
      enable = true;
      config.settings.yaml = {
        schemaStore = {
          enable = false;
          url = "";
        };
        schemas.__raw = ''require("schemastore").yaml.schemas()'';
        keyOrdering = false;
      };
    };
    taplo.enable = true;
  };

  plugins.conform-nvim.settings.formatters_by_ft = {
    json = [ "prettierd" ];
    jsonc = [ "prettierd" ];
    yaml = [ "prettierd" ];
    toml = [ "taplo" ];
  };

  extraPackages = with pkgs; [
    prettierd
    taplo
  ];
}
```

Add `./data.nix` to `imports` in `modules/nixvim/lang/default.nix`.

- [ ] **Step 3: Run checks, verify pass**

Run: `git add modules/nixvim && nix build .#checks.x86_64-linux.nvim-specs -L && nix build .#checks.x86_64-linux.nvim -L`
Expected: PASS.

Fallbacks, only on the matching failure:
- `require("schemastore")` fails while the LSP config is evaluated (plugin not yet on the runtimepath at that point of init): wrap both `__raw` values as `(function() local ok, s = pcall(require, "schemastore"); return ok and s.json.schemas() or {} end)()` (use `s.yaml.schemas()` for yamlls). If the spec then sees empty schemas, move both server configs into an `extraConfigLuaPost` block calling `vim.lsp.config("jsonls", { settings = { json = { schemas = require("schemastore").json.schemas() } } })` and the yamlls equivalent, and mention it in the commit subject.
- The JSON round-trip fails with prettierd's own output style: prettierd prints `{ "a": 1 }` for a one-key object; if it prints multi-line, use its exact output as `expected` (verify with `nix shell nixpkgs#prettierd -c sh -c 'echo "{\"a\":1}" | prettierd x.json'`).
- prettierd hangs or errors in the sandbox (daemon cannot start): remove the `formats("json", ...)` line only, keep the `ft_formatters` assertions, and add "JSON format on save" to Task 10's manual checklist.

- [ ] **Step 4: Commit**

```bash
nix fmt
git add modules/nixvim
git commit -m "Add JSON, YAML and TOML support to NixVim"
```

---

### Task 2: Web (TypeScript/JavaScript, Tailwind, HTML, CSS)

**Files:**
- Create: `modules/nixvim/lang/web.nix`, `modules/nixvim/tests/lang_web_spec.lua`
- Modify: `modules/nixvim/lang/default.nix` (imports)

**Interfaces:**
- Consumes: phase 1 extension points.
- Produces: `plugins.ts-autotag` (auto-close/rename tags in html/tsx/jsx and markdown).

- [ ] **Step 1: Write the failing spec**

Create `modules/nixvim/tests/lang_web_spec.lua`: helper block, then:

```lua
-- TS/JS, Tailwind, HTML, CSS (spec: Languages, web row).
on_path({
	"typescript-language-server",
	"tailwindcss-language-server",
	"vscode-html-language-server",
	"vscode-css-language-server",
	"prettierd",
})
servers({ "ts_ls", "tailwindcss", "html", "cssls" })

for _, ft in ipairs({ "javascript", "javascriptreact", "typescript", "typescriptreact", "html", "css", "scss" }) do
	ft_formatters(ft, { "prettierd" })
end

assert(pcall(require, "nvim-ts-autotag"), "ts-autotag loads")

formats("ts", "const a={b:1}", "const a = { b: 1 };")
```

`git add modules/nixvim/tests/lang_web_spec.lua`

Run: `nix build .#checks.x86_64-linux.nvim-specs -L`
Expected: FAIL with `typescript-language-server on PATH`.

- [ ] **Step 2: Implement web.nix**

```nix
# TypeScript/JavaScript, Tailwind, HTML and CSS.
{ lib, pkgs, ... }:
{
  lsp.servers = {
    ts_ls.enable = true;
    tailwindcss.enable = true;
    html.enable = true;
    cssls.enable = true;
  };

  plugins.ts-autotag.enable = true;

  plugins.conform-nvim.settings.formatters_by_ft = lib.genAttrs [
    "javascript"
    "javascriptreact"
    "typescript"
    "typescriptreact"
    "html"
    "css"
    "scss"
  ] (_: [ "prettierd" ]);

  extraPackages = [ pkgs.prettierd ];
}
```

Add `./web.nix` to `imports`.

- [ ] **Step 3: Run checks, verify pass**

Run: `git add modules/nixvim && nix build .#checks.x86_64-linux.nvim-specs -L && nix build .#checks.x86_64-linux.nvim -L`
Expected: PASS. If the prettierd round-trip was removed in Task 1 for sandbox reasons, remove the `formats("ts", ...)` line here too and add "TS format on save" to Task 10.

- [ ] **Step 4: Commit**

```bash
nix fmt
git add modules/nixvim
git commit -m "Add TypeScript, Tailwind, HTML and CSS support to NixVim"
```

---

### Task 3: Python

**Files:**
- Create: `modules/nixvim/lang/python.nix`, `modules/nixvim/tests/lang_python_spec.lua`
- Modify: `modules/nixvim/lang/default.nix` (imports), `modules/nixvim/keymaps.nix` (add `<leader>cv`)

**Interfaces:**
- Produces: augroup `nixvim_ruff_hover` (ruff defers hover to basedpyright); `:VenvSelect`; keymap `<leader>cv`.

- [ ] **Step 1: Write the failing spec**

Create `modules/nixvim/tests/lang_python_spec.lua`: helper block, then:

```lua
-- Python (spec: Languages, python row).
on_path({ "basedpyright-langserver", "ruff" })
servers({ "basedpyright", "ruff" })
ft_formatters("python", { "ruff_organize_imports", "ruff_format" })
formats("py", "x=1", "x = 1")

assert(vim.fn.exists(":VenvSelect") == 2, ":VenvSelect command")
assert(vim.fn.maparg("<leader>cv", "n") ~= "", "<leader>cv mapped")
assert(#vim.api.nvim_get_autocmds({ group = "nixvim_ruff_hover", event = "LspAttach" }) == 1, "ruff hover autocmd")
```

`git add modules/nixvim/tests/lang_python_spec.lua`

Run: `nix build .#checks.x86_64-linux.nvim-specs -L`
Expected: FAIL with `basedpyright-langserver on PATH`.

- [ ] **Step 2: Implement python.nix**

```nix
# Python: basedpyright for types, ruff for lint and format.
{ pkgs, ... }:
{
  lsp.servers = {
    basedpyright.enable = true;
    ruff.enable = true;
  };

  # ruff's hover is minimal; leave hover to basedpyright (LazyVim does the same).
  autoGroups.nixvim_ruff_hover.clear = true;
  autoCmd = [
    {
      event = "LspAttach";
      group = "nixvim_ruff_hover";
      callback.__raw = ''
        function(event)
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client.name == "ruff" then
            client.server_capabilities.hoverProvider = false
          end
        end
      '';
    }
  ];

  # venv-selector v2 API (nixvim's own example still shows v1 keys).
  plugins.venv-selector = {
    enable = true;
    settings.options.picker = "snacks";
  };

  plugins.conform-nvim.settings.formatters_by_ft.python = [
    "ruff_organize_imports"
    "ruff_format"
  ];

  extraPackages = [ pkgs.ruff ];
}
```

In `modules/nixvim/keymaps.nix`, add to the `keymaps` list (in the `# pickers` group):

```nix
    (map "n" "<leader>cv" "<cmd>VenvSelect<cr>" "Select VirtualEnv")
```

Add `./python.nix` to `imports`.

- [ ] **Step 3: Run checks, verify pass**

Run: `git add modules/nixvim && nix build .#checks.x86_64-linux.nvim-specs -L && nix build .#checks.x86_64-linux.nvim -L`
Expected: PASS. If nixvim's venv-selector picker assertion rejects `"snacks"`, set `settings.options.picker = "native";` and note it in the commit subject.

- [ ] **Step 4: Commit**

```bash
nix fmt
git add modules/nixvim
git commit -m "Add Python support to NixVim"
```

---

### Task 4: Go (and the Go toolchain)

**Files:**
- Create: `modules/nixvim/lang/go.nix`, `modules/nixvim/tests/lang_go_spec.lua`
- Modify: `modules/nixvim/lang/default.nix` (imports), `modules/home/dev.nix`, `docs/MIGRATION-NOTES.md`

**Interfaces:**
- Produces: `go` on the user's PATH (home-manager), gopls configured with gofumpt.

- [ ] **Step 1: Write the failing spec**

Create `modules/nixvim/tests/lang_go_spec.lua`: helper block, then:

```lua
-- Go (spec: Languages, go row). The go toolchain itself comes from dev.nix, not the editor.
on_path({ "gopls", "gofumpt", "goimports", "golangci-lint" })
servers({ "gopls" })
assert(vim.lsp.config.gopls.settings.gopls.gofumpt == true, "gopls gofumpt")
ft_formatters("go", { "goimports", "gofumpt" })
assert(table.concat(require("lint").linters_by_ft.go or {}, ",") == "golangcilint", "golangci-lint linter")
formats("go", "package main\nfunc main(){}", "package main\n\nfunc main() {}", { "gofumpt" })
```

`git add modules/nixvim/tests/lang_go_spec.lua`

Run: `nix build .#checks.x86_64-linux.nvim-specs -L`
Expected: FAIL with `gopls on PATH`.

- [ ] **Step 2: Implement go.nix**

```nix
# Go. The go toolchain is in modules/home/dev.nix; gopls finds it on PATH.
{ pkgs, ... }:
{
  lsp.servers.gopls = {
    enable = true;
    config.settings.gopls = {
      gofumpt = true;
      usePlaceholders = true;
      staticcheck = true;
      analyses.unusedparams = true;
    };
  };

  # Keep go out of the editor closure (user decision: toolchain from dev.nix).
  dependencies.go.enable = false;

  plugins.conform-nvim.settings.formatters_by_ft.go = [
    "goimports"
    "gofumpt"
  ];
  plugins.lint.lintersByFt.go = [ "golangcilint" ];

  extraPackages = with pkgs; [
    gofumpt
    gotools # goimports
    golangci-lint
  ];
}
```

Add `./go.nix` to `imports`. If `dependencies.go` does not exist in this nixvim revision (evaluation error "option does not exist"), delete that line.

- [ ] **Step 3: Add go to dev.nix**

In `modules/home/dev.nix` `home.packages`, after `rustup` add:

```nix
    go
```

In `docs/MIGRATION-NOTES.md`, after the rust-analyzer section add:

```markdown
## Go toolchain in dev.nix

`go` is installed globally by `modules/home/dev.nix`, like `rustup` and
`jdk21`, because the NixVim build's gopls needs it on `PATH`. The editor
itself does not bundle `go`. Project-specific Go versions still work
through a devShell that puts its own `go` first on `PATH`.
```

- [ ] **Step 4: Run checks, verify pass**

Run:

```bash
git add modules
nix build .#checks.x86_64-linux.nvim-specs -L
nix build .#checks.x86_64-linux.nvim -L
nix build .#nixosConfigurations.tariognatha.config.system.build.toplevel --dry-run
```

Expected: PASS; dry-run succeeds (no `buildEnv` collision on `bin/go`). If gofumpt output differs, run `printf 'package main\nfunc main(){}\n' | nix run nixpkgs#gofumpt` and use its exact output as `expected`.

- [ ] **Step 5: Commit**

```bash
nix fmt
git add modules docs/MIGRATION-NOTES.md
git commit -m "Add Go support to NixVim and go to dev tools"
```

---

### Task 5: Rust

**Files:**
- Create: `modules/nixvim/lang/rust.nix`, `modules/nixvim/tests/lang_rust_spec.lua`
- Modify: `modules/nixvim/lang/default.nix` (imports)

**Interfaces:**
- Consumes: rustup's `rust-analyzer` on the user's PATH (outside the editor).
- Produces: `vim.g.rustaceanvim`; crates.nvim for `Cargo.toml`.

- [ ] **Step 1: Write the failing spec**

Create `modules/nixvim/tests/lang_rust_spec.lua`: helper block, then:

```lua
-- Rust (spec: Languages, rust row). rust-analyzer must NOT come from the editor.
assert(vim.fn.executable("rust-analyzer") == 0, "rust-analyzer must not be bundled (sandbox has no rustup)")
assert(type(vim.g.rustaceanvim) == "table" or type(vim.g.rustaceanvim) == "function", "rustaceanvim configured")
local cfg = type(vim.g.rustaceanvim) == "function" and vim.g.rustaceanvim() or vim.g.rustaceanvim
assert(cfg.server == nil or cfg.server.cmd == nil, "server.cmd unset: rustaceanvim finds rust-analyzer on PATH")
local ra = cfg.server.default_settings["rust-analyzer"]
assert(ra.check.command == "clippy", "clippy on save")

-- crates.nvim loads for Cargo.toml
local path = vim.fn.tempname() .. "/Cargo.toml"
vim.fn.mkdir(vim.fs.dirname(path), "p")
vim.fn.writefile({ "[package]", 'name = "x"' }, path)
vim.cmd.edit(path)
vim.wait(200, function()
	return package.loaded["crates"] ~= nil
end)
assert(package.loaded["crates"] ~= nil, "crates.nvim loaded for Cargo.toml")
```

`git add modules/nixvim/tests/lang_rust_spec.lua`

Run: `nix build .#checks.x86_64-linux.nvim-specs -L`
Expected: FAIL with `rustaceanvim configured`.

- [ ] **Step 2: Implement rust.nix**

```nix
# Rust via rustaceanvim. rust-analyzer comes from rustup (modules/home/dev.nix), never nixpkgs:
# rustaceanvim would otherwise pull nixpkgs' rust-analyzer onto PATH.
{
  dependencies.rust-analyzer.enable = false;

  plugins.rustaceanvim = {
    enable = true;
    settings.server.default_settings.rust-analyzer = {
      cargo.allFeatures = true;
      check.command = "clippy";
      procMacro.enable = true;
    };
  };

  plugins.crates = {
    enable = true;
    settings.completion.crates.enabled = true;
    lazyLoad.settings.event = [ "BufRead Cargo.toml" ];
  };
}
```

Add `./rust.nix` to `imports`.

- [ ] **Step 3: Run checks, verify pass**

Run:

```bash
git add modules/nixvim
nix build .#checks.x86_64-linux.nvim-specs -L
nix build .#checks.x86_64-linux.nvim -L
nix path-info -r .#nvim | grep -i rust-analyzer && echo "RUST-ANALYZER BUNDLED" || echo "not bundled"
```

Expected: PASS and `not bundled`. If the startup test warns that rust-analyzer is missing, that warning is from rustaceanvim's health check only when a rust buffer opens; the startup test opens none, so a warning here means `dependencies.rust-analyzer.enable = false` did not take effect — check the option path in `nixvim-print-init` output. If crates.nvim does not load via the lz-n event pattern, change to `lazyLoad.settings.ft = "toml";`.

- [ ] **Step 4: Commit**

```bash
nix fmt
git add modules/nixvim
git commit -m "Add Rust support to NixVim using rustup's rust-analyzer"
```

---

### Task 6: Java

**Files:**
- Create: `modules/nixvim/lang/java.nix`, `modules/nixvim/tests/lang_java_spec.lua`
- Modify: `modules/nixvim/lang/default.nix` (imports)

**Interfaces:**
- Consumes: `jdk21` / `JAVA_HOME` from `modules/home/dev.nix` at runtime (jdt-language-server's nixpkgs wrapper also carries a JDK).
- Produces: nvim-jdtls started per project with workspace `stdpath("cache")/jdtls/<project>`.

- [ ] **Step 1: Write the failing spec**

Create `modules/nixvim/tests/lang_java_spec.lua`: helper block, then:

```lua
-- Java via nvim-jdtls (spec: Languages, java row). Formatting is LSP formatting.
on_path({ "jdtls" })
assert(pcall(require, "jdtls"), "nvim-jdtls loads")
ft_formatters("java", {})

-- the module starts jdtls from a java FileType hook
local hooks = vim.api.nvim_get_autocmds({ event = "FileType", pattern = "java" })
assert(#hooks > 0, "java FileType hook for jdtls")
```

`git add modules/nixvim/tests/lang_java_spec.lua`

Run: `nix build .#checks.x86_64-linux.nvim-specs -L`
Expected: FAIL with `jdtls on PATH`.

- [ ] **Step 2: Implement java.nix**

```nix
# Java via nvim-jdtls; one workspace per project under the nvim cache dir.
{ pkgs, ... }:
{
  plugins.jdtls = {
    enable = true;
    jdtLanguageServerPackage = pkgs.jdt-language-server;
    settings = {
      cmd = [
        "jdtls"
        "-data"
        {
          __raw = ''vim.fn.stdpath("cache") .. "/jdtls/" .. vim.fn.fnamemodify(vim.fs.root(0, { "gradlew", "mvnw", "pom.xml", "build.gradle", ".git" }) or vim.fn.getcwd(), ":t")'';
        }
      ];
      root_dir.__raw = ''vim.fs.root(0, { "gradlew", "mvnw", "pom.xml", "build.gradle", ".git" })'';
    };
  };
}
```

Add `./java.nix` to `imports`.

- [ ] **Step 3: Run checks, verify pass**

Run: `git add modules/nixvim && nix build .#checks.x86_64-linux.nvim-specs -L && nix build .#checks.x86_64-linux.nvim -L`
Expected: PASS.

Fallbacks:
- If nixvim's jdtls module evaluates `settings.cmd`/`root_dir` once at startup instead of per buffer (the startup test would then create a workspace for the check sandbox's cwd; harmless, but wrong per project): replace the module's start logic with `plugins.jdtls.settings = { }` plus an explicit FileType autocmd in java.nix:
  ```nix
  autoGroups.nixvim_jdtls.clear = true;
  autoCmd = [
    {
      event = "FileType";
      group = "nixvim_jdtls";
      pattern = "java";
      callback.__raw = ''
        function()
          local root = vim.fs.root(0, { "gradlew", "mvnw", "pom.xml", "build.gradle", ".git" }) or vim.fn.getcwd()
          require("jdtls").start_or_attach({
            cmd = { "jdtls", "-data", vim.fn.stdpath("cache") .. "/jdtls/" .. vim.fn.fnamemodify(root, ":t") },
            root_dir = root,
          })
        end
      '';
    }
  ];
  ```
  and keep `plugins.jdtls.enable = true; jdtLanguageServerPackage = pkgs.jdt-language-server;` only if the module does not add its own start hook; otherwise use `extraPlugins = [ pkgs.vimPlugins.nvim-jdtls ]; extraPackages = [ pkgs.jdt-language-server ];` instead of `plugins.jdtls`.

- [ ] **Step 4: Commit**

```bash
nix fmt
git add modules/nixvim
git commit -m "Add Java support to NixVim"
```

---

### Task 7: LaTeX

**Files:**
- Create: `modules/nixvim/lang/tex.nix`, `modules/nixvim/tests/lang_tex_spec.lua`
- Modify: `modules/nixvim/lang/default.nix` (imports; and the `nixvim_ts_start` autocmd if phase 1 added it)

**Interfaces:**
- Consumes: `snippet_util.in_mathzone()` / `in_env()` (phase 1 Task 7), system `texliveMedium` (latexmk, pdflatex) at runtime.
- Produces: vimtex active for tex; tex math-mode autosnippets functional.

- [ ] **Step 1: Write the failing spec**

Create `modules/nixvim/tests/lang_tex_spec.lua`: helper block, then:

```lua
-- LaTeX (spec: Languages, tex row).
on_path({ "texlab", "latexindent" })
servers({ "texlab" })
ft_formatters("tex", { "latexindent" })
assert(vim.g.loaded_vimtex == 1, "vimtex loaded (not lazy)")

-- vimtex syntax drives math-zone detection, so treesitter highlight is off for latex
local path = vim.fn.tempname() .. ".tex"
vim.fn.writefile({ "\\documentclass{article}", "\\begin{document}", "a $x + y$ b", "\\end{document}" }, path)
vim.cmd.edit(path)
local buf = vim.api.nvim_get_current_buf()
assert(vim.bo[buf].filetype == "tex", "filetype tex")
assert(vim.treesitter.highlighter.active[buf] == nil, "treesitter highlight off for tex")
vim.api.nvim_win_set_cursor(0, { 3, 4 }) -- inside $x + y$
local util = require("snippet_util")
assert(util.in_mathzone() == true, "in_mathzone inside $...$")
vim.api.nvim_win_set_cursor(0, { 3, 0 }) -- the leading "a"
assert(util.in_mathzone() == false, "not in math outside $...$")

formats("tex", "\\begin{itemize}\n\\item a\n\\end{itemize}", "\\begin{itemize}\n\t\\item a\n\\end{itemize}")
```

`git add modules/nixvim/tests/lang_tex_spec.lua`

Run: `nix build .#checks.x86_64-linux.nvim-specs -L`
Expected: FAIL with `texlab on PATH`.

- [ ] **Step 2: Implement tex.nix**

```nix
# LaTeX: vimtex (compile/view/motions, uses the system texliveMedium) + texlab + latexindent.
{ pkgs, ... }:
let
  # Only latexindent is bundled; TeX itself stays in modules/home/dev.nix.
  latexindent = pkgs.texliveBasic.withPackages (ps: [ ps.latexindent ]);
in
{
  plugins.vimtex = {
    enable = true;
    texlivePackage = null;
    settings = {
      view_method = "general";
      quickfix_mode = 0;
    };
  };

  # vimtex's syntax is what vimtex#syntax#in_mathzone reads; treesitter would replace it.
  plugins.treesitter.settings.highlight.disable = [ "latex" ];

  lsp.servers.texlab.enable = true;

  plugins.conform-nvim.settings.formatters_by_ft.tex = [ "latexindent" ];
  extraPackages = [ latexindent ];
}
```

Add `./tex.nix` to `imports`.

- [ ] **Step 3: If phase 1 added the `nixvim_ts_start` autocmd, exclude tex**

Only if `modules/nixvim/lang/default.nix` contains `nixvim_ts_start`: change its callback to

```nix
      callback.__raw = ''
        function(ev)
          if vim.bo[ev.buf].filetype ~= "tex" then
            pcall(vim.treesitter.start, ev.buf)
          end
        end
      '';
```

- [ ] **Step 4: Run checks, verify pass**

Run: `git add modules/nixvim && nix build .#checks.x86_64-linux.nvim-specs -L && nix build .#checks.x86_64-linux.nvim -L`
Expected: PASS.

Fallbacks:
- `latexindent` fails with missing Perl modules: use `pkgs.texlive.combine { inherit (pkgs.texlive) scheme-infraonly latexindent; }` for the `latexindent` binding; if that also fails, drop it from `extraPackages` (texliveMedium in dev.nix ships `latexindent` on the user's PATH), remove `"latexindent"` from `on_path` and the `formats` line in the spec, and add "tex format on save" to Task 10's checklist.
- latexindent's default indent is a tab only if its defaults say so; if the round-trip differs only in indentation characters, run `printf '\\begin{itemize}\n\\item a\n\\end{itemize}\n' > /tmp/x.tex && nix shell nixpkgs#texliveMedium -c latexindent /tmp/x.tex` and use that exact output as `expected`.
- `in_mathzone` false inside `$...$` in headless: add `vim.cmd("syntax sync fromstart")` and `vim.cmd("redraw")` before the assertion in the spec; if still false, the vimtex syntax is not active — check `vim.b.current_syntax == "tex"` and that `plugins.treesitter.settings.highlight.disable` took effect.
- `texlivePackage` not an option in this nixvim revision: remove that line and check `nix path-info -r .#nvim | grep -i texlive-` only lists the small latexindent environment.

- [ ] **Step 5: Commit**

```bash
nix fmt
git add modules/nixvim
git commit -m "Add LaTeX support to NixVim with vimtex"
```

---

### Task 8: Markdown

**Files:**
- Create: `modules/nixvim/lang/markdown.nix`, `modules/nixvim/tests/lang_markdown_spec.lua`
- Modify: `modules/nixvim/lang/default.nix` (imports), `modules/nixvim/keymaps.nix` (`<leader>cp`)

**Interfaces:**
- Produces: `:MarkdownPreviewToggle` (lazy, lz-n), render-markdown in-buffer rendering, keymap `<leader>cp`.

- [ ] **Step 1: Write the failing spec**

Create `modules/nixvim/tests/lang_markdown_spec.lua`: helper block, then:

```lua
-- Markdown (spec: Languages, markdown row).
on_path({ "marksman", "prettierd" })
servers({ "marksman" })
ft_formatters("markdown", { "prettierd" })
assert(pcall(require, "render-markdown"), "render-markdown loads")
assert(vim.fn.exists(":MarkdownPreviewToggle") == 2, ":MarkdownPreviewToggle command")
assert(vim.fn.maparg("<leader>cp", "n") ~= "", "<leader>cp mapped")
formats("md", "#  Title", "# Title")
```

`git add modules/nixvim/tests/lang_markdown_spec.lua`

Run: `nix build .#checks.x86_64-linux.nvim-specs -L`
Expected: FAIL with `marksman on PATH`.

- [ ] **Step 2: Implement markdown.nix**

```nix
# Markdown: marksman, prettierd, in-buffer rendering and browser preview.
{ pkgs, ... }:
{
  lsp.servers.marksman.enable = true;

  plugins.render-markdown.enable = true;

  plugins.markdown-preview = {
    enable = true;
    lazyLoad.settings = {
      ft = "markdown";
      cmd = [
        "MarkdownPreview"
        "MarkdownPreviewToggle"
      ];
    };
  };

  plugins.conform-nvim.settings.formatters_by_ft.markdown = [ "prettierd" ];
  extraPackages = [ pkgs.prettierd ];
}
```

In `modules/nixvim/keymaps.nix` `keymaps`, add:

```nix
    (map "n" "<leader>cp" "<cmd>MarkdownPreviewToggle<cr>" "Markdown Preview")
```

Add `./markdown.nix` to `imports`.

- [ ] **Step 3: Run checks, verify pass**

Run: `git add modules/nixvim && nix build .#checks.x86_64-linux.nvim-specs -L && nix build .#checks.x86_64-linux.nvim -L`
Expected: PASS. If Task 1 removed prettierd round-trips, remove the `formats("md", ...)` line here too. If `:MarkdownPreviewToggle` is missing because lz-n stubs only the first `cmd`, drop `lazyLoad` for markdown-preview entirely.

- [ ] **Step 4: Commit**

```bash
nix fmt
git add modules/nixvim
git commit -m "Add Markdown support to NixVim"
```

---

### Task 9: Docker and shell

**Files:**
- Create: `modules/nixvim/lang/docker-shell.nix`, `modules/nixvim/tests/lang_docker_shell_spec.lua`
- Modify: `modules/nixvim/lang/default.nix` (imports)

**Interfaces:**
- Produces: dockerls + hadolint for Dockerfiles; bashls (runs shellcheck itself when on PATH) + shfmt for sh/bash.

- [ ] **Step 1: Write the failing spec**

Create `modules/nixvim/tests/lang_docker_shell_spec.lua`: helper block, then:

```lua
-- Docker and shell (spec: Languages, docker/shell row).
on_path({ "docker-langserver", "hadolint", "bash-language-server", "shellcheck", "shfmt" })
servers({ "dockerls", "bashls" })
ft_formatters("sh", { "shfmt" })
ft_formatters("bash", { "shfmt" })
assert(table.concat(require("lint").linters_by_ft.dockerfile or {}, ",") == "hadolint", "hadolint linter")
formats("sh", "if true;then echo;fi", "if true; then echo; fi")
```

`git add modules/nixvim/tests/lang_docker_shell_spec.lua`

Run: `nix build .#checks.x86_64-linux.nvim-specs -L`
Expected: FAIL with `docker-langserver on PATH`.

- [ ] **Step 2: Implement docker-shell.nix**

```nix
# Dockerfiles and shell scripts. bashls runs shellcheck itself when it is on PATH.
{ pkgs, ... }:
{
  lsp.servers = {
    dockerls.enable = true;
    bashls.enable = true;
  };

  plugins.conform-nvim.settings.formatters_by_ft = {
    sh = [ "shfmt" ];
    bash = [ "shfmt" ];
  };
  plugins.lint.lintersByFt.dockerfile = [ "hadolint" ];

  extraPackages = with pkgs; [
    shfmt
    shellcheck
    hadolint
  ];
}
```

Add `./docker-shell.nix` to `imports`.

- [ ] **Step 3: Run checks, verify pass**

Run: `git add modules/nixvim && nix build .#checks.x86_64-linux.nvim-specs -L && nix build .#checks.x86_64-linux.nvim -L`
Expected: PASS. If shfmt splits the `if` onto several lines, run `echo 'if true;then echo;fi' | nix run nixpkgs#shfmt` and use its exact output as `expected`.

- [ ] **Step 4: Commit**

```bash
nix fmt
git add modules/nixvim
git commit -m "Add Docker and shell support to NixVim"
```

---

### Task 10: Whole-flake verification and manual checklist

**Files:** none changed unless a check fails.

- [ ] **Step 1: Automated verification**

```bash
nix build .#checks.x86_64-linux.nvim-specs -L
nix build .#checks.x86_64-linux.nvim -L
nix path-info -r .#nvim | grep -Ei 'lazy-nvim|lazyvim|mason|rust-analyzer|texlive-combined|texlive-medium' && echo "FORBIDDEN IN CLOSURE" || echo "closure clean"
for h in tariognatha tarmantria taractias; do
  nix build ".#nixosConfigurations.$h.config.system.build.toplevel" --dry-run || exit 1
done
nix flake check --no-build
```

Expected: `ran 17 specs` (8 from phase 1 + 9 language specs), `closure clean`, three dry-runs and the flake check succeed.

- [ ] **Step 2: Hand the manual checklist to the user**

After `sudo nixos-rebuild switch --flake ~/.dotfiles#<host>` and `rustup component add rust-analyzer rust-src` (once per user, if not done):

- [ ] `.json` in a repo with a `package.json`: schema completion for keys; format on save.
- [ ] `.yaml` GitHub workflow file: schema validation errors show for a bad key.
- [ ] `.ts`/`.tsx`: ts_ls attached, tailwind classes complete in `className`, closing tag auto-renames.
- [ ] `.py` in a uv project: basedpyright types, ruff diagnostics, `<leader>cv` lists the project venv.
- [ ] `.go` in a module: `go version` works in the shell; gopls attached, imports added on save.
- [ ] `.rs` in a cargo project: `:checkhealth rustaceanvim` shows rustup's rust-analyzer; clippy warnings on save; `Cargo.toml` shows crate versions.
- [ ] `.java` in a gradle/maven project: jdtls attaches (first start takes a while), workspace dir under `~/.cache/nvim/jdtls/`.
- [ ] `.tex`: `<localleader>ll` (`,ll`) compiles with latexmk, `<localleader>lv` opens the PDF; math-mode autosnippets fire inside `$...$` only; texlab diagnostics.
- [ ] `.md`: rendered in buffer, `<leader>cp` opens browser preview.
- [ ] `Dockerfile`: hadolint warnings; `.sh`: shellcheck diagnostics via bashls, shfmt on save.
- [ ] Any items the fallbacks moved here from automated specs (prettierd/latexindent round-trips).
