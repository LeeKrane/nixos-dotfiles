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

local util = require("snippet_util")
local env = util.in_env
local math = make_condition(util.in_mathzone)

return {
	s(
		{
			trig = "si",
			dscr = "si environment",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "autosnippet",
		},
		fmt(
			[[
				\si{<>}<>
			]],
			{
				i(1),
				i(0),
			},
			{ delimiters = "<>" }
		),
		{ condition = math }
	),
	s({
		trig = "ohm",
		dscr = "ohm",
		wordTrig = "false",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\ohm]],
		}),
	}, { condition = math }),
	s({
		trig = "kohm",
		dscr = "kohm",
		wordTrig = "false",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\kohm]],
		}),
	}, { condition = math }),
	s({
		trig = "uV",
		dscr = "microvolts",
		wordTrig = "false",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\uV]],
		}),
	}, { condition = math }),
	s({
		trig = "um",
		dscr = "micrometer",
		wordTrig = "false",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\um]],
		}),
	}, { condition = math }),
	s({
		trig = "uA",
		dscr = "microampere",
		wordTrig = "false",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\uA]],
		}),
	}, { condition = math }),
	s({
		trig = "uF",
		dscr = "microfarad",
		wordTrig = "false",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\uF]],
		}),
	}, { condition = math }),
	s({
		trig = "degC",
		dscr = "degree celsius",
		wordTrig = "false",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\degree C]],
		}),
	}, { condition = math }),
}
