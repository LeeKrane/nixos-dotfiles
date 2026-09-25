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

-- Go (spec: Languages, go row). The go toolchain itself comes from dev.nix, not the editor.
on_path({ "gopls", "gofumpt", "golangci-lint" })
-- goimports runs from an absolute store path; gotools' other binaries (bundle, ...) stay off PATH
local gi = require("conform").get_formatter_info("goimports")
assert(gi.available, "goimports available: " .. tostring(gi.available_msg))
assert(vim.startswith(gi.command, "/nix/store/"), "goimports absolute store path: " .. gi.command)
-- ("bundle" is not a usable probe: the ruby provider env also ships one)
assert(vim.fn.executable("goimports") == 0 and vim.fn.executable("stringer") == 0, "gotools must not be on PATH")
assert(vim.fn.executable("go") == 0, "go must not be on PATH")
servers({ "gopls" })
assert(vim.lsp.config.gopls.settings.gopls.gofumpt == true, "gopls gofumpt")
ft_formatters("go", { "goimports", "gofumpt" })
assert(table.concat(require("lint").linters_by_ft.go or {}, ",") == "golangcilint", "golangci-lint linter")

-- Disable gopls before opening a .go buffer below: its root_dir handler shells
-- out to `go env` synchronously (nvim-lspconfig lsp/gopls.lua, identify_go_dir),
-- and the sandbox has no `go` on PATH by design, so autostart would crash the spec.
vim.lsp.enable("gopls", false)
formats("go", "package main\nfunc main(){}", "package main\n\nfunc main() {}", { "gofumpt" })

-- golangci-lint is slow: lint go only on save, other filetypes on read/insert-leave too
local lint = require("lint")
local calls = 0
local real = lint.try_lint
lint.try_lint = function()
	calls = calls + 1
end
local gobuf = vim.api.nvim_get_current_buf()
assert(vim.bo[gobuf].filetype == "go", "go buffer")
for _, ev in ipairs({ "BufReadPost", "InsertLeave" }) do
	vim.api.nvim_exec_autocmds(ev, { group = "nixvim_lint", buffer = gobuf })
end
assert(calls == 0, "go not linted on read/insert-leave: " .. calls)
vim.api.nvim_exec_autocmds("BufWritePost", { group = "nixvim_lint", buffer = gobuf })
assert(calls == 1, "go linted on save: " .. calls)
local luabuf = vim.api.nvim_create_buf(true, false)
vim.bo[luabuf].filetype = "lua"
vim.api.nvim_exec_autocmds("BufReadPost", { group = "nixvim_lint", buffer = luabuf })
assert(calls == 2, "other filetypes still linted on read: " .. calls)
lint.try_lint = real
