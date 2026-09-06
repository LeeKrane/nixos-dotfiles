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
local circuitikz = make_condition(function()
	return env("circuitikz")
end)
-- TODO: move make_condition kind of syntax to all snippet files
-- TODO: show_condition (all snippets with conditions)

return {
	s(
		{
			trig = ";ctikz",
			dscr = "circuitikz environment",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "autosnippet",
		},
		fmt(
			[[
				\begin{figure}[H]
					\begin{center}
						\begin{circuitikz}
							\draw
								(0, 0)
								<>
						\end{circuitikz}
						\caption{<>}
					\end{center}
				\end{figure}
				<>
			]],
			{
				i(1),
				i(2),
				i(0),
			},
			{ delimiters = "<>" }
		),
		{ condition = line_begin }
	),
	s(
		{
			trig = "dr",
			dscr = "draw environment",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "autosnippet",
		},
		fmt(
			[[
				\draw
					(<>, <>)
					<>
			]],
			{
				i(1),
				i(2),
				i(0),
			},
			{ delimiters = "<>" }
		),
		{ condition = line_begin * circuitikz }
	),
	s(
		{
			trig = "n",
			dscr = "circuitikz node",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "autosnippet",
		},
		fmt(
			[[
				to [ <> ] (<>, <>)
				<>
			]],
			{
				i(1),
				i(2),
				i(3),
				i(0),
			},
			{ delimiters = "<>" }
		),
		{ condition = line_begin * circuitikz }
	),
	s(
		{
			trig = "s",
			dscr = "short",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "autosnippet",
		},
		fmt(
			[[
				to [ short ] (<>, <>)
				<>
			]],
			{
				i(1),
				i(2),
				i(0),
			},
			{ delimiters = "<>" }
		),
		{ condition = line_begin * circuitikz }
	),
	s(
		{
			trig = "r",
			dscr = "resistor",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "autosnippet",
		},
		fmt(
			[[
				to [ R, l=${}$, v>=~ ] ({}, {})
				{}
			]],
			{
				i(1),
				i(2),
				i(3),
				i(0),
			},
			{ delimiters = "{}" }
		),
		{ condition = line_begin * circuitikz }
	),
	s(
		{
			trig = "vv",
			dscr = "voltage source",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "autosnippet",
		},
		fmt(
			[[
				to [ V, v<=${}$ ] ({}, {})
				{}
			]],
			{
				i(1),
				i(2),
				i(3),
				i(0),
			},
			{ delimiters = "{}" }
		),
		{ condition = line_begin * circuitikz }
	),
	s(
		{
			trig = "am",
			dscr = "ampmeter",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "autosnippet",
		},
		fmt(
			[[
				to [ rmeterwa, t=A, l=${}$ ] ({}, {})
				{}
			]],
			{
				i(1),
				i(2),
				i(3),
				i(0),
			},
			{ delimiters = "{}" }
		),
		{ condition = line_begin * circuitikz }
	),
	s(
		{
			trig = "vm",
			dscr = "voltmeter",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "autosnippet",
		},
		fmt(
			[[
				to [ rmeterwa, t=V, l=${}$ ] ({}, {})
				{}
			]],
			{
				i(1),
				i(2),
				i(3),
				i(0),
			},
			{ delimiters = "{}" }
		),
		{ condition = line_begin * circuitikz }
	),
	s(
		{
			trig = "led",
			dscr = "led diode",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "autosnippet",
		},
		fmt(
			[[
				to [ leDo, v>=~ ] ({}, {})
				{}
			]],
			{
				i(1),
				i(2),
				i(0),
			},
			{ delimiters = "{}" }
		),
		{ condition = line_begin * circuitikz }
	),
	s(
		{
			trig = "c",
			dscr = "capacitor",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "autosnippet",
		},
		fmt(
			[[
				to [ C, l=${}$, v>=~ ] ({}, {})
				{}
			]],
			{
				i(1),
				i(2),
				i(3),
				i(0),
			},
			{ delimiters = "{}" }
		),
		{ condition = line_begin * circuitikz }
	),
}
