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

-- TS/JS, Tailwind, HTML, CSS (spec: Languages, web row).
on_path({
	"typescript-language-server",
	"tailwindcss-language-server",
	"vscode-html-language-server",
	"vscode-css-language-server",
	"prettierd",
})
servers({ "ts_ls", "tailwindcss", "html", "cssls" })
-- tailwind's @tailwind/@apply are unknown at-rules to cssls
local css = vim.lsp.config.cssls.settings or {}
for _, lang in ipairs({ "css", "scss", "less" }) do
	local rule = vim.tbl_get(css, lang, "lint", "unknownAtRules")
	assert(rule == "ignore", lang .. ".lint.unknownAtRules: " .. tostring(rule))
end

for _, ft in ipairs({ "javascript", "javascriptreact", "typescript", "typescriptreact", "html", "css", "scss" }) do
	ft_formatters(ft, { "prettierd" })
end

assert(pcall(require, "nvim-ts-autotag"), "ts-autotag loads")

formats("ts", "const a={b:1}", "const a = { b: 1 };")

-- format on save runs prettierd only when a prettier config is found upward (spec: Formatting and linting)
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
saves("ts", "const a={b:1}", "const a={b:1}", nil)
saves("ts", "const a={b:1}", "const a = { b: 1 };", ".prettierrc")
-- a package.json "prettier" key counts as config; a package.json without it does not
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
vim.fn.writefile({ '{ "name": "x" }' }, dir .. "/package.json")
vim.fn.writefile({ "const a={b:1}" }, dir .. "/a.ts")
vim.cmd.edit(dir .. "/a.ts")
vim.cmd.write()
assert(vim.fn.readfile(dir .. "/a.ts")[1] == "const a={b:1}", "package.json without prettier key: unformatted")
vim.fn.writefile({ '{ "name": "x", "prettier": {} }' }, dir .. "/package.json")
vim.cmd.edit(dir .. "/a.ts")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "const a={b:1}" })
vim.cmd.write()
assert(vim.fn.readfile(dir .. "/a.ts")[1] == "const a = { b: 1 };", "package.json prettier key: formatted")
