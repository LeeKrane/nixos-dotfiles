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

-- Markdown (spec: Languages, markdown row).
on_path({ "marksman", "prettierd" })
servers({ "marksman" })
ft_formatters("markdown", { "prettierd" })
assert(pcall(require, "render-markdown"), "render-markdown loads")
assert(vim.fn.exists(":MarkdownPreviewToggle") == 2, ":MarkdownPreviewToggle command")
formats("md", "#  Title", "# Title")
-- <leader>cp is buffer-local to markdown buffers
assert(vim.fn.maparg("<leader>cp", "n", false, true).buffer == 1, "<leader>cp buffer-local in markdown")
vim.cmd.enew()
vim.bo.filetype = "lua"
assert(vim.fn.maparg("<leader>cp", "n") == "", "<leader>cp absent outside markdown")
