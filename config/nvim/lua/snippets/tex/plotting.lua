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
	s(
		{
			trig = "pgfplot",
			dscr = "plot via tikz/pgfplot",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "snippet",
		},
		fmt(
			[[
				\begin{figure}[H]
					\begin{center}
						\begin{tikzpicture}
							\begin{axis}[
									title={<>},
									xlabel = {\(<>\)},
									ylabel = {\(<>\)},
									xmin=<>, xmax=<>,
									ymin=<>, ymax=<>,
									xtick={<>},
									ytick={<>},
									grid,
									grid style=dashed,
								]
								\addplot+[
									%only marks,
									%scatter,
									mark=<>,
									mark size=<>
								]
								coordinates {
									(<>)<>
								};
							\end{axis}
						\end{tikzpicture}
					\end{center}
				\end{figure}
				<>
			]],
			{
				i(1),
				i(2),
				i(3),
				i(4, "0"),
				i(5, "100"),
				i(6, "0"),
				i(7, "100"),
				i(8, "0,10,20,30,40,50,60,70,80,90,100"),
				i(9, "0,10,20,30,40,50,60,70,80,90,100"),
				i(10, "*"),
				i(11, "2pt"),
				i(12),
				i(13),
				i(0),
			},
			{ delimiters = "<>" }
		),
		{ condition = line_begin }
	),
}
