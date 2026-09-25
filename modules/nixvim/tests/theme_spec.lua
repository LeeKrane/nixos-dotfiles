-- Pure parsing and palette math of dynamic-theme (spec: Dynamic theme).
local T = require("dynamic-theme")

local function fixture(name)
	local f = assert(io.open(vim.env.SPEC_FIXTURES .. "/" .. name, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

-- parse
local dark = assert(T.parse(fixture("material_colors_dark.scss")))
assert(dark.dark == true, "darkmode True")
assert(dark.colors.term0 == "#131214", "hex lowercased: " .. tostring(dark.colors.term0))
local light = assert(T.parse(fixture("material_colors_light.scss")))
assert(light.dark == false, "darkmode False")

local p, err = T.parse("")
assert(p == nil and err == "empty", "empty file: " .. tostring(err))
p, err = T.parse("\n  \n")
assert(p == nil and err == "empty", "whitespace file")
p, err = T.parse(fixture("material_colors_truncated.scss"))
assert(p == nil and err:match("^invalid") and err:match("term15"), "truncated: " .. tostring(err))

-- rotation
assert(T.rotation("#c9c4d0") == 0, "near-grey primary does not rotate")
local rot = T.rotation("#7c4dff")
assert(rot ~= 0 and math.abs(rot) <= 15, "vivid rotation within 15: " .. rot)

-- palette invariants
local ACCENTS = { "base08", "base09", "base0A", "base0B", "base0C", "base0D", "base0E", "base0F" }
local function check(parsed, label)
	local pal, term = T.build_palette(parsed)
	for i = 0, 15 do
		local slot = string.format("base%02X", i)
		assert(type(pal[slot]) == "string" and pal[slot]:match("^#%x%x%x%x%x%x$"), label .. ": " .. slot)
	end
	assert(pal.base00 == parsed.colors.term0, label .. ": base00 equals term0")
	assert(pal.base05 == parsed.colors.onSurface, label .. ": base05 equals onSurface")
	assert(#term == 16 and term[2] == parsed.colors.term1, label .. ": term colors in order")
	assert(T.contrast(pal.base03, pal.base00) >= 3.0, label .. ": comment contrast")
	local hues = {}
	for _, slot in ipairs(ACCENTS) do
		local hex = pal[slot]
		local c = T.contrast(hex, pal.base00)
		assert(c >= 4.5, string.format("%s: %s %s contrast %.2f", label, slot, hex, c))
		local d = T.oklab_distance(hex, pal.base05)
		assert(d >= 0.08, string.format("%s: %s too close to fg (%.3f)", label, slot, d))
		local _, _, h = T.hex_to_oklch(hex)
		hues[#hues + 1] = { slot, h }
	end
	-- 25 degrees by construction; 20 allows for 8-bit rounding
	for i = 1, #hues do
		for j = i + 1, #hues do
			local diff = math.abs(((hues[j][2] - hues[i][2] + 540) % 360) - 180)
			assert(diff >= 20, string.format("%s: %s/%s hue gap %.1f", label, hues[i][1], hues[j][1], diff))
		end
	end
end
check(dark, "dark")
check(light, "light")
check(assert(T.parse(fixture("material_colors_vivid.scss"))), "vivid")
