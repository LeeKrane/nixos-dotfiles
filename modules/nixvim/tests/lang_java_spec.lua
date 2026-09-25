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

-- Java via nvim-jdtls (spec: Languages, java row). Formatting is LSP formatting.
on_path({ "jdtls" })
assert(pcall(require, "jdtls"), "nvim-jdtls loads")
ft_formatters("java", {})

-- the module starts jdtls from a java FileType hook
local hooks = vim.api.nvim_get_autocmds({ event = "FileType", pattern = "java" })
assert(#hooks > 0, "java FileType hook for jdtls")

-- the hook starts jdtls for the event's buffer, with one workspace per project
-- root (not per basename) and blink's capabilities. Stub start_or_attach so the
-- sandbox never launches a JVM.
local jdtls = require("jdtls")
local real = jdtls.start_or_attach
local seen = {}
jdtls.start_or_attach = function(config, opts, start_opts)
	table.insert(seen, { config = config, start_opts = start_opts })
end
local base = vim.fn.tempname()
local bufs = {}
for _, parent in ipairs({ "a", "b" }) do
	local root = base .. "/" .. parent .. "/proj"
	vim.fn.mkdir(root, "p")
	vim.fn.writefile({}, root .. "/pom.xml")
	vim.fn.writefile({ "class A {}" }, root .. "/A.java")
	vim.cmd.edit(root .. "/A.java")
	table.insert(bufs, { buf = vim.api.nvim_get_current_buf(), root = root })
end
jdtls.start_or_attach = real
assert(#seen == 2, "jdtls start per java buffer: " .. #seen)
local function data_dir(cmd)
	for i, arg in ipairs(cmd) do
		if arg == "-data" then
			return cmd[i + 1]
		end
	end
end
for i, s in ipairs(seen) do
	assert(s.start_opts and s.start_opts.bufnr == bufs[i].buf, "start_or_attach bufnr from the event")
	assert(s.config.root_dir == bufs[i].root, "root_dir " .. tostring(s.config.root_dir))
	assert(
		s.config.capabilities and s.config.capabilities.textDocument.completion.completionItem.snippetSupport,
		"blink capabilities"
	)
end
local d1, d2 = data_dir(seen[1].config.cmd), data_dir(seen[2].config.cmd)
assert(
	d1 and d2 and d1 ~= d2,
	"same-basename projects get distinct workspaces: " .. tostring(d1) .. " vs " .. tostring(d2)
)
assert(vim.startswith(d1, vim.fn.stdpath("cache") .. "/jdtls/"), "workspace under cache/jdtls: " .. d1)
