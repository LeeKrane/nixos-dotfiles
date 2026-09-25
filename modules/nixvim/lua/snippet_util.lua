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
