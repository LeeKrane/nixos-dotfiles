local ls = require("luasnip")
local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local d = ls.dynamic_node
local c = ls.choice_node
local fmt = require("luasnip.extras.fmt").fmt
local fmta = require("luasnip.extras.fmt").fmta
local rep = require("luasnip.extras").rep

local make_condition = require("luasnip.extras.conditions").make_condition
local line_begin = require("luasnip.extras.expand_conditions").line_begin

local env = function(name)
	local is_inside = vim.fn["vimtex#env#is_inside"](name)
	return (is_inside[1] > 0 and is_inside[2] > 0)
end
local math = make_condition(function()
	return vim.fn["vimtex#syntax#in_mathzone"]() == 1
end)

return {
	s({
		trig = "alpha",
		dscr = "alpha",
		wordTrig = "false",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\alpha]],
		}),
	}, { condition = math }),
	s({
		trig = "beta",
		dscr = "beta",
		wordTrig = "false",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\beta]],
		}),
	}, { condition = math }),
	s({
		trig = "gamma",
		dscr = "gamma",
		wordTrig = "false",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\gamma]],
		}),
	}, { condition = math }),
	s({
		trig = "delta",
		dscr = "delta",
		wordTrig = "false",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\delta]],
		}),
	}, { condition = math }),
	s({
		trig = "Delta",
		dscr = "big delta",
		wordTrig = "false",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\Delta]],
		}),
	}, { condition = math }),
	s({
		trig = "omega",
		dscr = "omega",
		wordTrig = "false",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\omega]],
		}),
	}, { condition = math }),
	s({
		trig = ";sigma",
		dscr = "sigma",
		wordTrig = "false",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\sigma]],
		}),
	}, { condition = math }),
	s({
		trig = "Sigma",
		dscr = "big sigma",
		wordTrig = "false",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\Sigma]],
		}),
	}, { condition = math }),
	s({
		trig = "tau",
		dscr = "tau",
		wordTrig = "false",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\tau]],
		}),
	}, { condition = math }),
	s({
		trig = "epsilon",
		dscr = "epsilon",
		wordTrig = "false",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\epsilon]],
		}),
	}, { condition = math }),
}
