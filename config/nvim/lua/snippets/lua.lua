local ls = require("luasnip")
local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local d = ls.dynamic_node
local fmt = require("luasnip.extras.fmt").fmt
local fmta = require("luasnip.extras.fmt").fmta
local rep = require("luasnip.extras").rep
local line_begin = require("luasnip.extras.expand_conditions").line_begin
local c = ls.choice_node

return {
	s(
		{
			trig = "snipf",
			dscr = "A snippet to create other formatted snippets.",
		},
		fmt(
			[=[
				s(
					{
						trig="<>",
						dscr="<>",
						wordTrig="<>",
						regTrig="<>",
						snippetType="<>",
					},
					fmt(
						[[
							<>
						]],
						{
							<>
						},
						{ delimiters = "<>" }
					),
					{ <> }
				),
				<>
			]=],
			{
				i(1),
				i(2),
				c(3, { t("true"), t("false") }),
				c(4, { t("false"), t("true") }),
				c(5, { t("snippet"), t("autosnippet") }),
				i(6),
				i(7),
				i(8, "<>"),
				c(9, {
					t("condition = line_begin,"),
					t("condition = math,"),
					t("condition = circuitikz,"),
					t("condition = line_begin * circuitikz,"),
					t("condition = "),
					t(""),
				}),
				i(0),
			},
			{
				delimiters = "<>",
				condition = line_begin,
			}
		)
	),
	s(
		{
			trig = "snipt",
			dscr = "A snippet to create other text snippets.",
		},
		fmt(
			[=[
				s({
					trig="<>",
					dscr="<>",
					wordTrig="<>",
					regTrig="<>",
					snippetType="<>",
				}, {
					t({
						<>
					}),
				}, { <> }),
				<>
			]=],
			{
				i(1),
				i(2),
				c(3, { t("true"), t("false") }),
				c(4, { t("false"), t("true") }),
				c(5, { t("snippet"), t("autosnippet") }),
				i(6),
				c(7, {
					t("condition = line_begin"),
					t("condition = math"),
					t("condition = circuitikz"),
					t("condition = line_begin * circuitikz"),
					t("condition = "),
					t(""),
				}),
				i(0),
			},
			{
				delimiters = "<>",
				condition = line_begin,
			}
		)
	),
}
