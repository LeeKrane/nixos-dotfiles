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
