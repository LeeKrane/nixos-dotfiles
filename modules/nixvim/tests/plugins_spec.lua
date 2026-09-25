-- Every kept plugin loads with the configured options (spec: Plugins).
local function loads(mod)
	local ok, err = pcall(require, mod)
	assert(ok, "require " .. mod .. ": " .. tostring(err))
end

-- snacks
assert(_G.Snacks ~= nil, "Snacks global")
local sc = Snacks.config
assert(sc.picker.sources.explorer.hidden == true, "explorer shows dotfiles")
assert(sc.picker.sources.files.hidden == true, "files picker shows dotfiles")
for _, name in ipairs({ "notifier", "lazygit", "bigfile", "quickfile", "words", "indent", "input", "explorer", "dashboard" }) do
	assert(sc[name] and sc[name].enabled == true, "snacks." .. name .. " enabled")
end
assert(not (sc.scroll and sc.scroll.enabled), "snacks.scroll disabled")
-- oil owns directory buffers (spec); snacks explorer stays the <leader>e sidebar only
assert(sc.explorer.replace_netrw == false, "snacks explorer must not replace netrw")
assert(vim.fn.executable("lazygit") == 1, "lazygit on PATH")
assert(vim.fn.executable("rg") == 1, "ripgrep on PATH")

-- ui
loads("bufferline")
loads("lualine")
loads("which-key")
loads("mini.icons")
local dev_ok, devicons = pcall(require, "nvim-web-devicons")
assert(dev_ok and type(devicons.get_icon) == "function", "nvim-web-devicons provided (mini.icons mock)")
assert(#vim.api.nvim_get_runtime_file("lua/nvim-web-devicons.lua", true) == 0, "real nvim-web-devicons not bundled; mock only")
local lcfg = require("lualine").get_config()
assert(lcfg.options.globalstatus == true, "lualine globalstatus")
assert(lcfg.options.theme == "auto", "lualine auto theme")

-- editing
for _, mod in ipairs({ "flash", "mini.ai", "mini.pairs", "mini.surround", "ts-comments", "todo-comments", "oil" }) do
	loads(mod)
end
assert(require("mini.surround").config.mappings.add == "gsa", "surround gsa")
assert(require("oil.config").view_options.show_hidden == true, "oil shows dotfiles")

-- tools
loads("gitsigns")
loads("persistence")
assert(vim.fn.exists(":Trouble") == 2, ":Trouble command (lazy stub)")
assert(vim.fn.exists(":GrugFar") == 2, ":GrugFar command (lazy stub)")
assert(package.loaded["trouble"] == nil, "trouble lazy until used")
