local ls = require("luasnip")

assert(
	#(ls.get_snippets("tex", { type = "autosnippets" }) or {}) > 0,
	"custom tex autosnippets loaded eagerly at startup"
)
assert(require("luasnip.session").config.enable_autosnippets == true, "autosnippets still enabled via nixvim settings")

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")

vim.cmd.edit(tmp .. "/a.tex")
assert(vim.bo.filetype == "tex", "a.tex detected as tex, got " .. vim.bo.filetype)
vim.wait(100)
local found = false
for _, s in ipairs(ls.get_snippets("tex", { type = "autosnippets" }) or {}) do
	if s.trigger == ";la" then
		found = true
	end
end
assert(found, "tex autosnippet ;la loaded")

local util = require("snippet_util")
assert(util.in_mathzone() == false, "in_mathzone false without vimtex")
assert(util.in_env("itemize") == false, "in_env false without vimtex")

vim.cmd.edit(tmp .. "/a.lua")
vim.wait(100)
assert(#(ls.get_snippets("lua") or {}) > 0, "lua snippets loaded")

ls.lsp_expand("foo(${1:a}, ${2:b})")
assert(ls.get_active_snip() ~= nil, "snippet active after expand")
vim.api.nvim_feedkeys(vim.keycode("<esc>"), "x", false)
assert(ls.get_active_snip() == nil, "<esc> ends the active snippet")

vim.cmd.edit(tmp .. "/a.py")
vim.wait(100)
assert(#(ls.get_snippets("python") or {}) > 0, "friendly-snippets loaded for python")

-- friendly-snippets must load once: nixvim already injects fromVscode = [{}], and setting it again doubled snippets.
do
	local seen = {}
	for _, s in ipairs(ls.get_snippets("python") or {}) do
		local key = s.trigger .. "\0" .. (s.name or "")
		assert(not seen[key], "duplicate python snippet (trigger=" .. s.trigger .. ", name=" .. tostring(s.name) .. ")")
		seen[key] = true
	end
end

-- blink config
local cfg = require("blink.cmp.config")
local function resolve(v)
	if type(v) == "function" then
		return v()
	end
	return v
end
assert(cfg.snippets.preset == "luasnip", "blink uses luasnip")
assert(resolve(cfg.completion.list.selection.preselect) == false, "no preselect")
for _, key in ipairs({
	"<CR>",
	"<S-CR>",
	"<C-j>",
	"<C-l>",
	"<C-k>",
	"<C-f>",
	"<C-d>",
	"<C-u>",
	"<Tab>",
	"<S-Tab>",
	"<C-space>",
	"<C-e>",
}) do
	assert(cfg.keymap[key] ~= nil, "blink key " .. key)
end

-- <C-k>: exercise the raw function with a fake `cmp`; blink.cmp.config only stores the normalized keymap.
do
	local ck = cfg.keymap["<C-k>"]
	assert(type(ck) == "table" and type(ck[1]) == "function", "<C-k> first entry is a function")
	assert(ck[2] == "fallback", "<C-k> falls back")

	local calls
	local fake_cmp = {
		is_menu_visible = function()
			return calls.menu_visible
		end,
		select_and_accept = function()
			calls.select_and_accept = true
			return true
		end,
		show = function()
			calls.show = true
			return true
		end,
	}

	local tmp = vim.fn.tempname()
	vim.fn.mkdir(tmp, "p")
	vim.cmd.edit(tmp .. "/ck.txt")

	-- Insert mode lets the cursor sit one past the last character; normal-mode nvim_win_set_cursor clamps.
	-- <C-k> fires from insert mode, so match that.
	local saved_ve = vim.o.virtualedit
	vim.o.virtualedit = "onemore"

	calls = { menu_visible = true }
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "foo" })
	vim.api.nvim_win_set_cursor(0, { 1, 3 })
	assert(ck[1](fake_cmp) == true, "<C-k> menu visible: returns true")
	assert(calls.select_and_accept and not calls.show, "<C-k> menu visible: accepts, doesn't show")

	calls = { menu_visible = false }
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "foo" })
	vim.api.nvim_win_set_cursor(0, { 1, 3 })
	assert(ck[1](fake_cmp) == true, "<C-k> after word char: returns true")
	assert(calls.show and not calls.select_and_accept, "<C-k> after word char: shows, doesn't accept")

	calls = { menu_visible = false }
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "foo " })
	vim.api.nvim_win_set_cursor(0, { 1, 4 })
	assert(ck[1](fake_cmp) == nil, "<C-k> after whitespace: falls through to fallback")
	assert(not calls.show and not calls.select_and_accept, "<C-k> after whitespace: neither called")

	calls = { menu_visible = false }
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	assert(ck[1](fake_cmp) == nil, "<C-k> at start of line: falls through to fallback")

	calls = { menu_visible = false }
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "foo_" })
	vim.api.nvim_win_set_cursor(0, { 1, 4 })
	assert(ck[1](fake_cmp) == true, "<C-k> after '_': returns true")
	assert(calls.show and not calls.select_and_accept, "<C-k> after '_': shows, doesn't accept")

	calls = { menu_visible = true }
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "foo" })
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	vim.cmd("normal! gh")
	assert(vim.fn.mode() == "s", "test setup: in select mode, got " .. vim.fn.mode())
	assert(ck[1](fake_cmp) == nil, "<C-k> in select mode: falls through to fallback")
	assert(not calls.show and not calls.select_and_accept, "<C-k> in select mode: neither called")
	vim.cmd("stopinsert")
	vim.api.nvim_feedkeys(vim.keycode("<esc>"), "x", false)

	vim.o.virtualedit = saved_ve
end
local srcs = table.concat(cfg.sources.default, ",")
assert(srcs == "lsp,path,snippets,buffer", "sources: " .. srcs)
