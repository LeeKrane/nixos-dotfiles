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
		trig = ";la",
		dscr = "leftarrow",
		wordTrig = "true",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\leftarrow]],
		}),
	}, { condition = math }),
	s({
		trig = ";La",
		dscr = "Leftarrow",
		wordTrig = "true",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\Leftarrow]],
		}),
	}, { condition = math }),
	s({
		trig = ";ra",
		dscr = "rightarrow",
		wordTrig = "true",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\rightarrow]],
		}),
	}, { condition = math }),
	s({
		trig = ";Ra",
		dscr = "Rightarrow",
		wordTrig = "true",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\Rightarrow]],
		}),
	}, { condition = math }),
	s({
		trig = ";lra",
		dscr = "leftrightarrow",
		wordTrig = "true",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\leftrightarrow]],
		}),
	}, { condition = math }),
	s({
		trig = ";Lra",
		dscr = "Leftrightarrow",
		wordTrig = "true",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\Leftrightarrow]],
		}),
	}, { condition = math }),
	s({
		trig = ";;",
		dscr = "cdot",
		wordTrig = "true",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\cdot]],
		}),
	}, { condition = math }),
	s(
		{
			trig = ";txt",
			dscr = "text",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "autosnippet",
		},
		fmt(
			[[
				\text{<>}<>
			]],
			{
				i(1),
				i(0),
			},
			{ delimiters = "<>" }
		),
		{ condition = math }
	),
	s(
		{
			trig = ";fr",
			dscr = "fraction",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "autosnippet",
		},
		fmt(
			[[
				\frac{<>}{<>}<>
			]],
			{
				i(1),
				i(2),
				i(0),
			},
			{ delimiters = "<>" }
		),
		{ condition = math }
	),
	s(
		{
			trig = ";ul",
			dscr = "underline",
			wordTrig = "false",
			regTrig = "false",
			snippetType = "autosnippet",
		},
		fmt(
			[[
				\underline{<>}<>
			]],
			{
				i(1),
				i(0),
			},
			{ delimiters = "<>" }
		),
		{ condition = math }
	),
	s(
		{
			trig = ";dul",
			dscr = "double underline",
			wordTrig = "false",
			regTrig = "false",
			snippetType = "autosnippet",
		},
		fmt(
			[[
				\underline{\underline{<>}}<>
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
		trig = ";appr",
		dscr = "approx",
		wordTrig = "false",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\approx]],
		}),
	}, { condition = math }),
	s(
		{
			trig = ";ol",
			dscr = "overline",
			wordTrig = "false",
			regTrig = "false",
			snippetType = "autosnippet",
		},
		fmt([[\overline{<>}<>]], {
			i(1),
			i(0),
		}, { delimiters = "<>" }),
		{ condition = math }
	),

	-- s(
	-- 	{
	-- 		trig="([%a%)%]%}])00",
	-- 		dscr="lower number",
	-- 		wordTrig="false",
	-- 		regTrig="true",
	-- 		snippetType="autosnippet",
	-- 	},
	-- 	fmta(
	-- 		"<>_{<>}",
	-- 		{
	-- 			f( function(_, snip) return snip.captures[1] end ),
	-- 			t("0")
	-- 		},
	-- 	)
	-- ),
}
