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

-- Python (spec: Languages, python row).
on_path({ "basedpyright-langserver", "ruff" })
servers({ "basedpyright", "ruff" })
local bp = vim.lsp.config.basedpyright.settings or {}
local mode = vim.tbl_get(bp, "basedpyright", "analysis", "typeCheckingMode")
assert(mode == "standard", "basedpyright typeCheckingMode: " .. tostring(mode))
assert(
	vim.tbl_get(bp, "basedpyright", "disableOrganizeImports") == true,
	"basedpyright leaves organize imports to ruff"
)
ft_formatters("python", { "ruff_organize_imports", "ruff_format" })
formats("py", "x=1", "x = 1")

assert(vim.fn.exists(":VenvSelect") == 2, ":VenvSelect command")
-- <leader>cv is buffer-local to python buffers (formats() above left a .py buffer current)
assert(vim.bo.filetype == "python", "python buffer current")
assert(vim.fn.maparg("<leader>cv", "n", false, true).buffer == 1, "<leader>cv buffer-local in python")
vim.cmd.enew()
vim.bo.filetype = "lua"
assert(vim.fn.maparg("<leader>cv", "n") == "", "<leader>cv absent outside python")
assert(#vim.api.nvim_get_autocmds({ group = "nixvim_ruff_hover", event = "LspAttach" }) == 1, "ruff hover autocmd")
