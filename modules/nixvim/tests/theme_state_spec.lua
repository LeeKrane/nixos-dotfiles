local T = require("dynamic-theme")

local function fixture(name)
	local f = assert(io.open(vim.env.SPEC_FIXTURES .. "/" .. name, "r"))
	local text = f:read("*a")
	f:close()
	return text
end
local dir = vim.env.XDG_STATE_HOME .. "/quickshell/user/generated"
local path = dir .. "/material_colors.scss"
assert(T.scss_path() == path, "path honours XDG_STATE_HOME: " .. T.scss_path())
local function write(text)
	vim.fn.mkdir(dir, "p")
	local f = assert(io.open(path, "w"))
	f:write(text)
	f:close()
end
local function normal_bg()
	return string.format("#%06x", vim.api.nvim_get_hl(0, { name = "Normal" }).bg)
end

local notified = {}
vim.notify = function(msg, level)
	notified[#notified + 1] = { msg = msg, level = level }
end

-- 1. startup without the file: fallback palette, scheme name set, silent
assert(vim.g.colors_name == "dynamic", "colors_name at startup: " .. tostring(vim.g.colors_name))
assert(normal_bg() == vim.g.dynamic_theme_fallback.base00, "fallback bg: " .. normal_bg())
assert(T._watcher == nil, "no watcher headless")

-- 2. valid file applies, background and terminal colours follow
write(fixture("material_colors_dark.scss"))
assert(T.reload(true) == true, "reload valid")
assert(normal_bg() == "#131214", "bg = term0: " .. normal_bg())
assert(vim.o.background == "dark")
assert(vim.g.terminal_color_1 == "#e84ceb", "terminal_color_1")
assert(vim.g.colors_name == "dynamic")

-- 3. empty file (mid-write): keep last good palette, no warning
write("")
assert(T.reload(true) == false)
assert(normal_bg() == "#131214", "kept palette on empty")
assert(#notified == 0, "no warning on empty")

-- 4. invalid non-empty file: palette kept, exactly one warning
write(fixture("material_colors_truncated.scss"))
assert(T.reload(true) == false)
assert(T.reload(true) == false)
assert(normal_bg() == "#131214", "kept palette on invalid")
assert(#notified == 1 and notified[1].level == vim.log.levels.WARN, "one warning: " .. vim.inspect(notified))

-- 5. light mode flips background
write(fixture("material_colors_light.scss"))
assert(T.reload(true) == true)
assert(vim.o.background == "light", "background light")
assert(normal_bg() == "#fdf8fa")

-- 6. a manual colorscheme survives a wallpaper change
vim.cmd.colorscheme("habamax")
write(fixture("material_colors_dark.scss"))
assert(T.reload(true) == true)
assert(vim.g.colors_name == "habamax", "manual scheme kept: " .. tostring(vim.g.colors_name))

-- 7. latch reset: a successful reload clears `warned`, so a later persistent error warns again.
local before_latch = #notified
write(fixture("material_colors_truncated.scss"))
assert(T.reload(true) == false)
assert(#notified == before_latch + 1, "latch reset: new warning after prior success: " .. vim.inspect(notified))

-- 8. stale retry cancelled: a second reload(false) must cancel the retry timer the first one scheduled.
-- Fresh module instance so "zero warnings" is literal. Case 6 left colors_name = "habamax"; reset it
-- so a successful reload re-renders.
vim.cmd.colorscheme("dynamic")
package.loaded["dynamic-theme"] = nil
local T3 = require("dynamic-theme")
local notified3 = {}
vim.notify = function(msg, level)
	notified3[#notified3 + 1] = { msg = msg, level = level }
end
write(fixture("material_colors_truncated.scss"))
assert(T3.reload(false) == false, "first reload(false) fails on truncated file")
vim.wait(100)
write(fixture("material_colors_dark.scss"))
assert(T3.reload(false) == true, "second reload(false) succeeds on dark file")
-- The first call's timer must be gone, not merely harmless.
assert(T3._retry == nil, "stale retry timer was cancelled, not left pending")
assert(
	vim.wait(1200, function()
		return normal_bg() == "#131214"
	end),
	"dark palette applied, no stale-retry interference"
)
assert(normal_bg() == "#131214", "bg = term0: " .. normal_bg())
assert(#notified3 == 0, "no warnings from a cancelled stale retry: " .. vim.inspect(notified3))

-- 9. startup retry: an empty file at setup time is picked up by the deferred retry, without a manual reload.
-- Fresh module: `:colorscheme dynamic` resolves via package.loaded, so setup() on the stale `T` would hit
-- case 8's T3 and the final wait would pass without the retry running.
package.loaded["dynamic-theme"] = nil
local T4 = require("dynamic-theme")
vim.g.colors_name = "dynamic"
write("")
T4.setup()
assert(normal_bg() ~= "#131214", "setup() on an empty file must not read as case 8's leftover dark bg: " .. normal_bg())
write(fixture("material_colors_dark.scss"))
assert(
	vim.wait(1500, function()
		return normal_bg() == "#131214"
	end),
	"startup retry recovers from a mid-write empty file"
)
assert(T4._retry == nil, "startup retry timer cleared itself, nothing left pending for later cases")

-- 10. setup() must not warn at once on a non-missing, non-empty read failure (e.g. truncated mid-write):
-- it retries once silently and warns only if the retry fails. Re-require a fresh module; case 4 already
-- tripped the `warned` latch.
package.loaded["dynamic-theme"] = nil
local T2 = require("dynamic-theme")
local notified2 = {}
vim.notify = function(msg, level)
	notified2[#notified2 + 1] = { msg = msg, level = level }
end
write(fixture("material_colors_truncated.scss"))
T2.setup()
assert(#notified2 == 0, "no immediate warning on setup with a truncated file: " .. vim.inspect(notified2))
write(fixture("material_colors_dark.scss"))
assert(
	vim.wait(1500, function()
		return normal_bg() == "#131214"
	end),
	"setup() retry recovers from a truncated file too"
)
assert(#notified2 == 0, "retry succeeded silently: " .. vim.inspect(notified2))

-- 11. fs_event watch: a wallpaper change is picked up without a manual reload.
-- M.watch() no-ops headless, so stub nvim_list_uis to a non-empty list.
do
	package.loaded["dynamic-theme"] = nil
	local T5 = require("dynamic-theme")
	vim.g.colors_name = "dynamic"
	write(fixture("material_colors_dark.scss"))
	assert(T5.reload(false) == true, "seed T5 with a valid dark palette")

	local saved_list_uis = vim.api.nvim_list_uis
	vim.api.nvim_list_uis = function()
		return { {} }
	end
	T5.watch()
	assert(T5._watcher ~= nil, "watch armed with a stubbed UI")

	write(fixture("material_colors_light.scss"))
	assert(
		vim.wait(2000, function()
			return normal_bg() == "#fdf8fa"
		end),
		"fs_event picked up a wallpaper change without a manual reload"
	)

	vim.api.nvim_list_uis = saved_list_uis
	if T5._watcher then
		T5._watcher.ev:stop()
		T5._watcher.ev:close()
		T5._watcher.timer:stop()
		T5._watcher.timer:close()
		T5._watcher = nil
	end
end

-- 12. fs_event watch survives the directory being deleted and recreated
-- (inotify watches an inode, see M.watch()).
do
	package.loaded["dynamic-theme"] = nil
	local T6 = require("dynamic-theme")
	vim.g.colors_name = "dynamic"
	write(fixture("material_colors_light.scss"))
	assert(T6.reload(false) == true, "seed T6 with a valid light palette")

	local saved_list_uis = vim.api.nvim_list_uis
	vim.api.nvim_list_uis = function()
		return { {} }
	end
	T6.watch()
	assert(T6._watcher ~= nil, "watch armed with a stubbed UI")
	local w0 = T6._watcher

	-- Delete and recreate synchronously: the directory already has a fresh inode when the callback runs,
	-- so lost-detection fires deterministically.
	vim.fn.delete(dir, "rf")
	write(fixture("material_colors_dark.scss"))

	assert(
		vim.wait(3000, function()
			return normal_bg() == "#131214"
		end),
		"fs_event re-armed after the directory was deleted and recreated"
	)

	-- The assertion above does not discriminate alone: a dead watcher's old handle still sees IN_DELETE and
	-- triggers one reload. Prove the watch recovered: a fresh handle replaced the old one, the old one is
	-- closed, and a second write after the recreation is still picked up.
	assert(
		vim.wait(1000, function()
			return T6._watcher ~= nil and T6._watcher ~= w0
		end),
		"watcher re-armed on a fresh handle"
	)
	assert(w0.ev:is_closing(), "stale fs_event handle closed")
	write(fixture("material_colors_light.scss"))
	assert(
		vim.wait(2000, function()
			return normal_bg() == "#fdf8fa"
		end),
		"post-recreate write picked up by the new watch"
	)

	vim.api.nvim_list_uis = saved_list_uis
	if T6._watcher then
		T6._watcher.ev:stop()
		T6._watcher.ev:close()
		T6._watcher.timer:stop()
		T6._watcher.timer:close()
		T6._watcher = nil
	end
end

-- 13. reload(false) on a missing file must not schedule a retry: the watcher or poll_for_dir covers creation.
do
	package.loaded["dynamic-theme"] = nil
	local T7 = require("dynamic-theme")
	vim.g.colors_name = "dynamic"
	vim.fn.delete(dir, "rf")
	assert(T7.reload(false) == false, "reload(false) fails on a missing file")
	assert(T7._retry == nil, "no retry scheduled for a missing file")
	vim.wait(50)
	assert(T7._retry == nil, "still no retry after waiting")
end

-- 14. setup() mirrors reload(): on failure the fallback scheme applies only when nothing claimed
-- colors_name, so a manual :colorscheme survives.
do
	package.loaded["dynamic-theme"] = nil
	local T8 = require("dynamic-theme")
	vim.cmd.colorscheme("habamax")
	-- Missing, not invalid: exercises only the colors_name check, with no retry timer left armed (see case 13).
	vim.fn.delete(dir, "rf")
	T8.setup()
	assert(vim.g.colors_name == "habamax", "manual scheme survives setup() failure: " .. tostring(vim.g.colors_name))
	assert(T8._retry == nil, "no retry left pending for later cases")
end
