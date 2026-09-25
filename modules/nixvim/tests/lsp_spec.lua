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
assert(vim.bo[buf].indentexpr:find("nvim-treesitter", 1, true), "treesitter indent for nix: " .. vim.bo[buf].indentexpr)

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

-- diagnostics: severity-sorted virtual text (lang/default.nix)
assert(vim.diagnostic.config().severity_sort == true, "diagnostics severity_sort")
assert(vim.diagnostic.config().float.border == "rounded", "diagnostics float.border")
