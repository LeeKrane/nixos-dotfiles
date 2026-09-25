-- User options from the old options.lua plus the LazyVim baseline (spec: Options).
local o, g = vim.o, vim.g

assert(g.mapleader == " ", "mapleader")
assert(g.maplocalleader == ",", "maplocalleader")
assert(g.tex_flavor == "latex", "tex_flavor")

local expected = {
	number = true,
	relativenumber = true,
	tabstop = 4,
	shiftwidth = 4,
	smartindent = true,
	smarttab = true,
	cursorline = true,
	expandtab = false,
	wrap = true,
	mouse = "a",
	showmode = false,
	undofile = true,
	undolevels = 10000,
	ignorecase = true,
	smartcase = true,
	scrolloff = 4,
	sidescrolloff = 8,
	signcolumn = "yes",
	splitright = true,
	splitbelow = true,
	splitkeep = "screen",
	confirm = true,
	completeopt = "menu,menuone,noselect",
	laststatus = 3,
	updatetime = 200,
	timeoutlen = 300,
	pumheight = 10,
	list = true,
	virtualedit = "block",
	wildmode = "longest:full,full",
	foldlevel = 99,
	foldmethod = "expr",
	foldexpr = "v:lua.vim.treesitter.foldexpr()",
	foldtext = "",
	termguicolors = true,
}
for name, want in pairs(expected) do
	assert(o[name] == want, string.format("option %s: want %s, got %s", name, vim.inspect(want), vim.inspect(o[name])))
end
assert(o.sessionoptions:find("folds", 1, true), "sessionoptions includes folds")
assert(o.listchars:find("trail:", 1, true), "listchars sets trail")
-- no system clipboard over SSH (OSC 52 reads block); "unnamedplus" otherwise.
-- SSH_TTY is unset in this test run, so the assertion below only exercises
-- the non-SSH branch; the SSH branch is exercised for real underneath it,
-- in a subprocess that actually has SSH_TTY set.
assert(
	o.clipboard == (vim.env.SSH_TTY and "" or "unnamedplus"),
	"clipboard: want " .. (vim.env.SSH_TTY and "" or "unnamedplus") .. ", got " .. o.clipboard
)

-- SSH branch, for real: spawn a fresh headless nvim with SSH_TTY set and
-- read back its vim.o.clipboard. `vim.v.progpath` is the *unwrapped*
-- neovim-byte-compiled binary here (no VIMRUNTIME/package setup -- it
-- fails to even start, missing lua module 'lz.n'), so this uses `nvim` on
-- PATH instead, which is the nixvim wrapper itself (available via the
-- nvim-specs check's `nativeBuildInputs`, see flake.nix).
local function clipboard_subprocess(ssh_tty)
	local base = vim.fn.environ()
	base.SSH_TTY = nil
	local env = ssh_tty and vim.tbl_extend("force", base, { SSH_TTY = ssh_tty }) or base
	return vim.system({
		"nvim",
		"--headless",
		"-c",
		"lua io.stdout:write(vim.o.clipboard)",
		"-c",
		"qa!",
	}, { env = env, text = true }):wait()
end

do
	local res = clipboard_subprocess("x")
	assert(res.code == 0, "SSH_TTY subprocess exited " .. res.code .. ": " .. (res.stderr or ""))
	assert(res.stderr == "", "SSH_TTY subprocess stderr: [" .. tostring(res.stderr) .. "]")
	assert(res.stdout == "", "clipboard over SSH: want empty, got [" .. tostring(res.stdout) .. "]")
end

-- Control: the exact same subprocess machinery, without SSH_TTY, must print
-- "unnamedplus" -- otherwise a broken env/spawn (e.g. SSH_TTY silently not
-- taking effect, or vim.o.clipboard reading some other default) could make
-- the SSH-branch assertion above pass vacuously by both branches printing
-- the same (wrong) thing.
do
	local res = clipboard_subprocess(nil)
	assert(res.code == 0, "control subprocess exited " .. res.code .. ": " .. (res.stderr or ""))
	assert(res.stderr == "", "control subprocess stderr: [" .. tostring(res.stderr) .. "]")
	assert(
		res.stdout == "unnamedplus",
		"clipboard without SSH_TTY: want unnamedplus, got [" .. tostring(res.stdout) .. "]"
	)
end
