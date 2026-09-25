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

-- Rust (spec: Languages, rust row). rust-analyzer must NOT come from the editor.
assert(vim.fn.executable("rust-analyzer") == 0, "rust-analyzer must not be bundled (sandbox has no rustup)")
assert(type(vim.g.rustaceanvim) == "table" or type(vim.g.rustaceanvim) == "function", "rustaceanvim configured")
local cfg = type(vim.g.rustaceanvim) == "function" and vim.g.rustaceanvim() or vim.g.rustaceanvim
assert(cfg.server == nil or cfg.server.cmd == nil, "server.cmd unset: rustaceanvim finds rust-analyzer on PATH")
local ra = cfg.server.default_settings["rust-analyzer"]
assert(ra.check.command == "clippy", "clippy on save")

-- crates.nvim loads for Cargo.toml
local path = vim.fn.tempname() .. "/Cargo.toml"
vim.fn.mkdir(vim.fs.dirname(path), "p")
vim.fn.writefile({ "[package]", 'name = "x"' }, path)
vim.cmd.edit(path)
vim.wait(200, function()
	return package.loaded["crates"] ~= nil
end)
assert(package.loaded["crates"] ~= nil, "crates.nvim loaded for Cargo.toml")
-- in-process LSP (completion/hover/actions) instead of the nvim-cmp source;
-- crates.nvim 0.7.x keeps the built config in crates.state.cfg (lua/crates/init.lua: setup)
local ccfg = require("crates.state").cfg
assert(ccfg.lsp.enabled == true, "crates lsp enabled")
assert(ccfg.lsp.completion and ccfg.lsp.hover and ccfg.lsp.actions, "crates lsp completion/hover/actions")
assert(ccfg.completion.crates.enabled == true, "crates name completion (feeds the lsp completion too)")
