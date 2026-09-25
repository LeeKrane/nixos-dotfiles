-- Wallpaper-driven colorscheme. Reads illogical-impulse's material_colors.scss
-- (written last by switchwall.sh, holds M3 roles, term0-15 and $darkmode),
-- builds a mini.base16 palette and exposes it as `:colorscheme dynamic`.
-- colors.json is deliberately ignored: it is written ~330 ms earlier by a
-- different generator and disagrees with the scss.
local M = {}

local REQUIRED = {
	"background",
	"onBackground",
	"onSurface",
	"surfaceContainer",
	"surfaceContainerHigh",
	"outline",
	"onSurfaceVariant",
	"primary",
}
for i = 0, 15 do
	REQUIRED[#REQUIRED + 1] = "term" .. i
end

-- Canonical OKLCH hues per base16 accent slot.
M.HUES = {
	base08 = 25,
	base09 = 55,
	base0A = 90,
	base0B = 145,
	base0C = 200,
	base0D = 250,
	base0E = 305,
	base0F = 0,
}

local function clamp(x, lo, hi)
	return math.max(lo, math.min(hi, x))
end

function M.scss_path()
	local state = vim.env.XDG_STATE_HOME
	if not state or state == "" then
		state = vim.env.HOME .. "/.local/state"
	end
	return state .. "/quickshell/user/generated/material_colors.scss"
end

function M.parse(text)
	if not text or text:match("^%s*$") then
		return nil, "empty"
	end
	local colors, dark = {}, nil
	for line in text:gmatch("[^\n]+") do
		local name, hex = line:match("^%$(%w+):%s*(#%x%x%x%x%x%x);")
		if name then
			colors[name] = hex:lower()
		end
		local mode = line:match("^%$darkmode:%s*(%a+);")
		if mode then
			dark = mode:lower() == "true"
		end
	end
	if dark == nil then
		return nil, "invalid: missing $darkmode"
	end
	for _, key in ipairs(REQUIRED) do
		if not colors[key] then
			return nil, "invalid: missing $" .. key
		end
	end
	return { dark = dark, colors = colors }
end

-- sRGB helpers for luminance/contrast (WCAG has no equivalent in mini.colors).
local function hex_to_rgb(hex)
	return tonumber(hex:sub(2, 3), 16) / 255, tonumber(hex:sub(4, 5), 16) / 255, tonumber(hex:sub(6, 7), 16) / 255
end

local function to_linear(c)
	return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
end

-- mini.colors' oklab/oklch use l on 0-100 and a/b/c on a roughly-matching
-- 100x scale (see :h MiniColors-color-spaces: "Adjust accordingly by
-- dividing/multiplying output by 100"); hex_to_oklch/oklch_to_hex keep their
-- previous public contract of l in [0, 1] and c around 0.12, so convert at
-- the boundary. adjust_lightness = false keeps the raw (non-"Intermission")
-- Oklab math the previous hand-rolled matrices used, so existing thresholds
-- (contrast, oklab distance, hue gap) keep meaning unchanged.
function M.hex_to_oklch(hex)
	local ok = require("mini.colors").convert(hex, "oklch", { adjust_lightness = false })
	return (ok.l or 0) / 100, (ok.c or 0) / 100, ok.h or 0
end

-- Reduces chroma until the colour fits sRGB, keeping lightness and hue
-- (mini.colors' default gamut_clip = "chroma" does this for us).
function M.oklch_to_hex(L, C, h)
	return require("mini.colors").convert(
		{ l = L * 100, c = C * 100, h = h },
		"hex",
		{ adjust_lightness = false, gamut_clip = "chroma" }
	)
end

local function luminance(hex)
	local r, g, b = hex_to_rgb(hex)
	return 0.2126 * to_linear(r) + 0.7152 * to_linear(g) + 0.0722 * to_linear(b)
end

-- WCAG contrast ratio.
function M.contrast(a, b)
	local la, lb = luminance(a), luminance(b)
	if la < lb then
		la, lb = lb, la
	end
	return (la + 0.05) / (lb + 0.05)
end

function M.oklab_distance(x, y)
	local ox = require("mini.colors").convert(x, "oklab", { adjust_lightness = false })
	local oy = require("mini.colors").convert(y, "oklab", { adjust_lightness = false })
	local dl = ((ox.l or 0) - (oy.l or 0)) / 100
	local da = ((ox.a or 0) - (oy.a or 0)) / 100
	local db = ((ox.b or 0) - (oy.b or 0)) / 100
	return math.sqrt(dl ^ 2 + da ^ 2 + db ^ 2)
end

local function hue_diff(from, to)
	return ((to - from + 540) % 360) - 180
end

-- One rotation for the whole hue wheel, so accent spacing never shrinks:
-- the canonical hue nearest the wallpaper primary moves onto it, capped at 15°.
function M.rotation(primary_hex)
	local _, c, ph = M.hex_to_oklch(primary_hex)
	if c < 0.03 then
		return 0
	end
	local best
	for _, h in pairs(M.HUES) do
		local d = hue_diff(h, ph)
		if not best or math.abs(d) < math.abs(best) then
			best = d
		end
	end
	return clamp(best, -15, 15)
end

local function accent(h, dark, bg, fg)
	local L, step = dark and 0.78 or 0.50, dark and 0.03 or -0.03
	local hex
	for _ = 1, 12 do
		hex = M.oklch_to_hex(L, 0.12, h)
		if M.contrast(hex, bg) >= 4.5 and M.oklab_distance(hex, fg) >= 0.08 then
			return hex
		end
		L = clamp(L + step, 0.05, 0.97)
	end
	return hex
end

function M.build_palette(parsed)
	local c, dark = parsed.colors, parsed.dark
	local fL, fC, fh = M.hex_to_oklch(c.onSurface)
	local p = {
		base00 = c.term0,
		base01 = c.surfaceContainer,
		base02 = c.surfaceContainerHigh,
		base03 = c.outline,
		base04 = c.onSurfaceVariant,
		base05 = c.onSurface,
		base06 = M.oklch_to_hex(clamp(fL + (dark and 0.05 or -0.05), 0, 1), fC, fh),
		base07 = c.onBackground,
	}
	if M.contrast(p.base03, p.base00) < 3.0 then
		local l3, c3, h3 = M.hex_to_oklch(p.base03)
		for _ = 1, 12 do
			l3 = clamp(l3 + (dark and 0.03 or -0.03), 0, 1)
			p.base03 = M.oklch_to_hex(l3, c3, h3)
			if M.contrast(p.base03, p.base00) >= 3.0 then
				break
			end
		end
	end
	local rot = M.rotation(c.primary)
	for slot, hue in pairs(M.HUES) do
		p[slot] = accent((hue + rot) % 360, dark, p.base00, p.base05)
	end
	local term = {}
	for i = 0, 15 do
		term[i + 1] = c["term" .. i]
	end
	return p, term
end

-- Runtime state -------------------------------------------------------------

M.state = nil
local warned = false

function M.read()
	local fd = io.open(M.scss_path(), "r")
	if not fd then
		return nil, "missing"
	end
	local text = fd:read("*a")
	fd:close()
	local parsed, err = M.parse(text)
	if not parsed then
		return nil, err
	end
	local palette, term = M.build_palette(parsed)
	return { dark = parsed.dark, palette = palette, term = term }
end

-- Missing or empty files are normal (no illogical-impulse, or mid-write): silent.
local function warn_once(err)
	if warned or err == "missing" or err == "empty" then
		return
	end
	warned = true
	vim.notify("dynamic-theme: " .. err .. " in " .. M.scss_path(), vim.log.levels.WARN)
end

-- Called by colors/dynamic.lua.
function M.apply()
	local s = M.state or { dark = true, palette = vim.g.dynamic_theme_fallback }
	vim.cmd("highlight clear")
	-- nil name: changing 'background' below must not re-source this scheme
	vim.g.colors_name = nil
	local bg = s.dark and "dark" or "light"
	if vim.o.background ~= bg then
		vim.o.background = bg
	end
	require("mini.base16").setup({ palette = s.palette })
	if s.term then
		for i = 0, 15 do
			vim.g["terminal_color_" .. i] = s.term[i + 1]
		end
	end
	vim.g.colors_name = "dynamic"
end

-- Cancels the single pending retry timer, if any.
local function cancel_retry()
	if M._retry then
		if not M._retry:is_closing() then
			M._retry:stop()
			M._retry:close()
		end
		M._retry = nil
	end
end

-- Schedules exactly one retry of reload(true) 500ms out. Only one retry is
-- ever in flight: cancel_retry() (called from reload(false)) clears a stale
-- one before this schedules a fresh one.
local function schedule_retry()
	local timer = vim.uv.new_timer()
	if not timer then
		return
	end
	M._retry = timer
	timer:start(
		500,
		0,
		vim.schedule_wrap(function()
			-- The raw libuv timer already fired by the time this
			-- vim.schedule_wrap callback actually runs on the main loop;
			-- cancel_retry() may have stopped+closed it and cleared
			-- M._retry (or even armed a *new* retry) in that window. A
			-- stale callback must not still call reload(true) once it's
			-- been superseded.
			if M._retry ~= timer then
				return
			end
			if not timer:is_closing() then
				timer:stop()
				timer:close()
			end
			M._retry = nil
			M.reload(true)
		end)
	)
end

-- Keeps the last good palette on failure; a manual :colorscheme wins.
-- is_retry = false means "a new file event/call": cancel any stale pending
-- retry before doing our own work, and schedule a fresh one on failure.
-- is_retry = true is the retry itself (or a caller forcing an immediate,
-- non-retrying attempt): failure goes straight to warn_once.
function M.reload(is_retry)
	if not is_retry then
		cancel_retry()
	end
	local s, err = M.read()
	if s then
		-- Reset the warning latch on every successful read, so a later
		-- persistent error in the same session still gets its own warning
		-- (still at most one warning per failure streak).
		warned = false
		M.state = s
		local name = vim.g.colors_name
		if name == nil or name == "dynamic" then
			vim.cmd.colorscheme("dynamic")
		end
		return true
	end
	if not is_retry then
		-- "missing" means the file doesn't exist at all (no
		-- illogical-impulse, or its generator directory not written yet):
		-- nothing changes until it's created, which the fs_event watcher
		-- (or poll_for_dir, if the directory itself is missing) already
		-- covers. Retrying every 500ms for a file that isn't there is
		-- pointless busywork.
		if err ~= "missing" then
			schedule_retry()
		end
		return false
	end
	warn_once(err)
	return false
end

-- Polls every 10s for `dir` to (re)appear, then re-arms watch() and reloads.
local function poll_for_dir(dir)
	local poll = vim.uv.new_timer()
	if not poll then
		return
	end
	poll:start(
		10000,
		10000,
		vim.schedule_wrap(function()
			if poll:is_closing() then
				return
			end
			if not vim.uv.fs_stat(dir) then
				return
			end
			poll:stop()
			poll:close()
			M.watch()
			M.reload(false)
		end)
	)
	vim.api.nvim_create_autocmd("VimLeavePre", {
		once = true,
		callback = function()
			if not poll:is_closing() then
				poll:stop()
				poll:close()
			end
		end,
	})
end

-- Watches the directory once. Files are rewritten in place, so the fs_event
-- itself is never re-armed for a normal write; if the directory is removed
-- and recreated out from under the watch (e.g. illogical-impulse's
-- generator directory gets recreated), the watch goes stale -- inotify
-- watches an inode, not a path, so a fresh directory at the same path needs
-- a fresh watch. Detect that and re-arm.
function M.watch()
	if M._watcher or #vim.api.nvim_list_uis() == 0 then
		return
	end
	local dir = vim.fs.dirname(M.scss_path())
	local dir_stat = vim.uv.fs_stat(dir)
	if not dir_stat then
		-- Directory doesn't exist yet (illogical-impulse not started): poll
		-- for it instead of never watching at all.
		poll_for_dir(dir)
		return
	end
	local dir_ino = dir_stat.ino
	local ev, timer = vim.uv.new_fs_event(), vim.uv.new_timer()
	if not ev or not timer then
		return
	end
	local function stop_watcher()
		if not ev:is_closing() then
			ev:stop()
			ev:close()
		end
		if not timer:is_closing() then
			timer:stop()
			timer:close()
		end
	end
	local ok = ev:start(dir, {}, function(err, fname)
		-- vim.uv.* is fast-context safe; vim.api/vim.fn/vim.cmd (inside
		-- poll_for_dir/M.watch/M.reload, via nvim_create_autocmd) are not,
		-- hence schedule_wrap below.
		local now_stat = vim.uv.fs_stat(dir)
		local lost = err ~= nil or now_stat == nil or now_stat.ino ~= dir_ino or fname == vim.fs.basename(dir)
		if lost then
			stop_watcher()
			M._watcher = nil
			vim.schedule_wrap(function()
				if vim.uv.fs_stat(dir) then
					-- The directory (or a fresh one at the same path)
					-- exists right now: re-arm immediately and reload,
					-- rather than falling through to the 10s poll and
					-- waiting out its first interval for nothing.
					M.watch()
					M.reload(false)
				else
					poll_for_dir(dir)
				end
			end)()
			return
		end
		if fname ~= "material_colors.scss" then
			return
		end
		timer:stop()
		-- schedule_wrap: fs_event/timer callbacks run in a fast context (E5560)
		timer:start(
			300,
			0,
			vim.schedule_wrap(function()
				M.reload(false)
			end)
		)
	end)
	if not ok then
		stop_watcher()
		return
	end
	M._watcher = { ev = ev, timer = timer }
	vim.api.nvim_create_autocmd("VimLeavePre", {
		once = true,
		callback = stop_watcher,
	})
end

function M.setup()
	M.state = nil
	-- reload(false) applies on success and schedules the silent single
	-- retry on failure ("missing" stays silent, see warn_once); on failure
	-- we still need to install the "dynamic" scheme once, using the
	-- fallback palette, since M.state is nil -- but only when nothing else
	-- has claimed colors_name already, matching reload()'s own manual-scheme
	-- check (a manual :colorscheme before setup() runs, e.g. from init.lua
	-- ordering, must not be clobbered by the fallback either).
	if not M.reload(false) then
		local name = vim.g.colors_name
		if name == nil or name == "dynamic" then
			vim.cmd.colorscheme("dynamic")
		end
	end
	-- UIEnter never fires headless, so checks and --headless runs never watch.
	vim.api.nvim_create_autocmd("UIEnter", { once = true, callback = M.watch })
end

vim.api.nvim_create_autocmd("VimLeavePre", {
	once = true,
	callback = cancel_retry,
})

return M
