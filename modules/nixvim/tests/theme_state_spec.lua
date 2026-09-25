-- Runtime behaviour: fallback, reload, keep-last-good, warnings, manual scheme.
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

-- 7. latch reset: a successful reload (case 6's trailing reload, above)
-- clears the module's `warned` latch, so a later persistent error in the
-- same session still gets its own warning. Case 4 already tripped the
-- latch once; without the reset this would be silently swallowed.
local before_latch = #notified
write(fixture("material_colors_truncated.scss"))
assert(T.reload(true) == false)
assert(#notified == before_latch + 1, "latch reset: new warning after prior success: " .. vim.inspect(notified))

-- 8. stale retry cancelled: reload(false) failure schedules a single
-- retry timer; a second reload(false) before it fires must cancel the
-- stale one rather than leave it to race the state the second call
-- already applied. Fresh module instance so "zero warnings" is literal.
-- Case 6 above left colors_name = "habamax" (manual scheme survives a
-- wallpaper change); reset it here so a successful reload actually
-- re-renders and normal_bg() reflects it.
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
-- Direct check of the mechanism itself: the first call's timer must be
-- gone, not merely harmless (the scenario above can't otherwise tell a
-- cancelled retry from an uncancelled one that just rereads the same
-- now-valid file).
assert(T3._retry == nil, "stale retry timer was cancelled, not left pending")
assert(
	vim.wait(1200, function()
		return normal_bg() == "#131214"
	end),
	"dark palette applied, no stale-retry interference"
)
assert(normal_bg() == "#131214", "bg = term0: " .. normal_bg())
assert(#notified3 == 0, "no warnings from a cancelled stale retry: " .. vim.inspect(notified3))

-- 9. startup retry: an empty file at setup time (mid-write) is caught by
-- the deferred retry once the writer finishes, without a manual reload.
-- Fresh, freshly-*registered* module: `:colorscheme dynamic` (colors/
-- dynamic.lua) resolves via require("dynamic-theme"), i.e. through
-- package.loaded -- calling setup() on the stale top-of-file `T` here
-- would still make that command resolve to case 8's T3, whose state was
-- already the dark palette applied there. The final wait would then pass
-- immediately without the retry ever running, testing nothing.
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

-- 10. setup() must not warn immediately on a non-missing, non-empty read
-- failure either (e.g. a truncated file mid-write past the $darkmode
-- line): it retries once, silently, like the empty-file case, and only
-- warns if the retry also fails. Case 4 above already tripped the
-- module's module-level `warned` latch, which would mask this assertion
-- (warn_once no-ops once warned), so re-require a fresh module instance
-- via package.loaded rather than reusing `T`.
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

-- 11. fs_event watch: a wallpaper change is picked up without a manual
-- reload call. M.watch() no-ops headless (nvim_list_uis() is empty), so
-- stub it to a non-empty list to actually arm the watcher for this test.
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

-- 12. fs_event watch survives the watched directory being deleted and
-- recreated at the same path (inotify watches an inode, not a path; see
-- M.watch()'s lost-detection logic). Proves the item 1 fix: without it,
-- the watcher would go dead and this case would time out.
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

	-- Delete and recreate synchronously, before control returns to the
	-- event loop: by the time the fs_event callback actually runs, the
	-- directory that's there already has a fresh inode, so the
	-- lost-detection heuristic fires deterministically regardless of what
	-- the raw fs_event args happened to report for the delete itself.
	vim.fn.delete(dir, "rf")
	write(fixture("material_colors_dark.scss"))

	assert(
		vim.wait(3000, function()
			return normal_bg() == "#131214"
		end),
		"fs_event re-armed after the directory was deleted and recreated"
	)

	-- The assertion above is not discriminating on its own: the pre-fix
	-- watcher (dead, never re-armed) also still had its *old* fs_event
	-- handle receiving the IN_DELETE for material_colors.scss inside the
	-- doomed directory, which was enough to trigger one last reload(false)
	-- that reads the (by-then-already-recreated) file by path -- so the bg
	-- goes dark either way, even though the watch itself is dead from then
	-- on. Prove the watch, not just this one read, actually recovered: a
	-- fresh handle replaced the old one, the old one is closed, and a
	-- second write after the recreation is still picked up.
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

-- 13. reload(false) on a wholly missing file must not schedule a retry:
-- nothing changes until the file is created, which the fs_event watcher
-- (or poll_for_dir) already covers. Retrying every 500ms for a file that
-- isn't there at all is pointless busywork.
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

-- 14. setup() symmetry with reload(): on failure, the fallback colorscheme
-- is only applied when nothing has already claimed colors_name -- a manual
-- :colorscheme before setup() runs must survive setup() the same way it
-- survives reload().
do
	package.loaded["dynamic-theme"] = nil
	local T8 = require("dynamic-theme")
	vim.cmd.colorscheme("habamax")
	-- Missing (not just invalid), so this exercises only the colors_name
	-- check, without also incidentally leaving a retry timer armed for
	-- later cases to trip over (see case 13: a missing file schedules none).
	vim.fn.delete(dir, "rf")
	T8.setup()
	assert(vim.g.colors_name == "habamax", "manual scheme survives setup() failure: " .. tostring(vim.g.colors_name))
	assert(T8._retry == nil, "no retry left pending for later cases")
end
