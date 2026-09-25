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
	-- expr maps let the key pass through raw inside floating terminals
	-- (e.g. lazygit), matching LazyVim's behavior there.
	assert(vim.fn.maparg(lhs, "t", false, true).expr == 1, "terminal map " .. lhs .. " must be expr")
end
assert(not has("<C-h>", "i"), "window nav must not map insert mode")
assert(has("<leader>sw", "x") and has("<leader>cf", "x"), "visual variants")
assert(has("<", "v") and has(">", "v"), "indent keeps selection")
assert(has("<C-s>", "i"), "save in insert")

-- j/k move by display line over wrapped lines (LazyVim default; user sets wrap=true)
assert(has("j", "n"), "missing normal map j")
assert(has("k", "x"), "missing visual map k")

assert(type(_G.nixvim_root) == "function" and type(nixvim_root()) == "string", "nixvim_root")

-- format toggles flip the flags conform reads
vim.fn.maparg("<leader>uF", "n", false, true).callback()
assert(vim.g.disable_autoformat == true, "<leader>uF disables globally")
vim.fn.maparg("<leader>uF", "n", false, true).callback()
assert(not vim.g.disable_autoformat, "<leader>uF re-enables")
vim.fn.maparg("<leader>uf", "n", false, true).callback()
assert(vim.b.disable_autoformat == true, "<leader>uf disables for buffer")

-- LSP maps are buffer-local on LspAttach. Target only our own handler's
-- group: firing this on every LspAttach handler (no group) also reaches
-- other plugins' global handlers (e.g. nvim-jdtls's), which rightly assert
-- a real client behind client_id and would fail on this fake id.
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_exec_autocmds("LspAttach", { group = "nixvim_lsp_keymaps", buffer = buf, data = { client_id = 0 } })
for _, lhs in ipairs({ "gd", "gr", "gI", "gy", "gD", "K", "gK", "<leader>ca", "<leader>cr" }) do
	assert(vim.fn.maparg(lhs, "n", false, true).buffer == 1, "buffer-local LSP map " .. lhs)
end
-- nvim 0.12's global grr/gra/grn/gri/grt make plain `gr` wait on timeoutlen
-- unless it opts out.
assert(vim.fn.maparg("gr", "n", false, true).nowait == 1, "gr must be nowait")
