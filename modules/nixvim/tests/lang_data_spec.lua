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

-- JSON, YAML, TOML (spec: Languages, data row).
on_path({ "vscode-json-language-server", "yaml-language-server", "taplo", "prettierd" })
servers({ "jsonls", "yamlls", "taplo" })

local json_schemas = vim.lsp.config.jsonls.settings.json.schemas
assert(type(json_schemas) == "table" and #json_schemas > 50, "jsonls has SchemaStore schemas")
local yaml = vim.lsp.config.yamlls.settings.yaml
assert(yaml.schemaStore.enable == false, "yamlls built-in schema store off")
assert(type(yaml.schemas) == "table" and next(yaml.schemas) ~= nil, "yamlls has SchemaStore schemas")

assert(vim.treesitter.language.get_lang("jsonc") == "json", "jsonc buffers use the json parser")

ft_formatters("json", { "prettierd" })
ft_formatters("jsonc", { "prettierd" })
ft_formatters("yaml", { "prettierd" })
ft_formatters("toml", { "taplo" })

formats("toml", "a=1", "a = 1")
formats("json", '{"a":1}', '{ "a": 1 }')
