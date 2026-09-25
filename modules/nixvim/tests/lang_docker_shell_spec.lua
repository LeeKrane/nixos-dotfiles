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

-- Docker and shell (spec: Languages, docker/shell row).
on_path({ "docker-langserver", "hadolint", "bash-language-server", "shellcheck", "shfmt" })
servers({ "dockerls", "bashls" })
ft_formatters("sh", { "shfmt" })
ft_formatters("bash", { "shfmt" })
assert(table.concat(require("lint").linters_by_ft.dockerfile or {}, ",") == "hadolint", "hadolint linter")
formats("sh", "if true;then echo;fi", "if true; then echo; fi")

-- format on save runs shfmt only when an .editorconfig is found upward (spec: Formatting and linting)
local function saves(ext, input, expected, config_file)
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	if config_file then
		vim.fn.writefile({ config_file == ".editorconfig" and "root = true" or "{}" }, dir .. "/" .. config_file)
	end
	local path = dir .. "/a." .. ext
	vim.fn.writefile(vim.split(input, "\n"), path)
	vim.cmd.edit(path)
	vim.cmd.write()
	local got = table.concat(vim.fn.readfile(path), "\n")
	assert(got == expected, ext .. " saved (" .. tostring(config_file) .. ") as " .. vim.inspect(got))
end
saves("sh", "if true;then echo;fi", "if true;then echo;fi", nil)
saves("sh", "if true;then echo;fi", "if true; then echo; fi", ".editorconfig")
