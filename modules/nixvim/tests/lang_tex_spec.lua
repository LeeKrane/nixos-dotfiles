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

-- LaTeX (spec: Languages, tex row).
on_path({ "texlab" })
-- latexindent runs from an absolute store path: its TeX env must not leak onto PATH
local li = require("conform").get_formatter_info("latexindent")
assert(li.available, "latexindent available: " .. tostring(li.available_msg))
assert(vim.startswith(li.command, "/nix/store/"), "latexindent absolute store path: " .. li.command)
assert(vim.fn.exepath("pdflatex") == "", "pdflatex must not come from the editor: " .. vim.fn.exepath("pdflatex"))
assert(vim.fn.executable("latexindent") == 0, "latexindent env not on PATH")
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

-- latexindent writes indent.log into its cwd unless -g redirects it
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
vim.cmd.cd(dir)
formats("tex", "\\begin{itemize}\n\\item a\n\\end{itemize}", "\\begin{itemize}\n\t\\item a\n\\end{itemize}")
assert(vim.fn.filereadable(dir .. "/indent.log") == 0, "latexindent left indent.log in cwd")
assert(
	vim.fn.filereadable(vim.fs.dirname(vim.api.nvim_buf_get_name(0)) .. "/indent.log") == 0,
	"latexindent left indent.log next to file"
)
