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
			trig = ";env",
			dscr = "environment",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "autosnippet",
		},
		fmt(
			[[
				\begin{<>}
					<>
				\end{<>}
				<>
			]],
			{
				i(1),
				i(2),
				rep(1),
				i(0),
			},
			{ delimiters = "<>" }
		),
		{ condition = line_begin }
	),
	s(
		{
			trig = ";eenv",
			dscr = "environment with attribute",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "autosnippet",
		},
		fmt(
			[[
				\begin{<>}{<>}
					<>
				\end{<>}
				<>
			]],
			{
				i(1),
				i(2),
				i(3),
				rep(1),
				i(0),
			},
			{ delimiters = "<>" }
		),
		{ condition = line_begin }
	),
	s(
		{
			trig = ";sc",
			dscr = "section",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "autosnippet",
		},
		fmt(
			[[
				\section{<>}
			]],
			{
				i(1),
			},
			{ delimiters = "<>" }
		),
		{ condition = line_begin }
	),
	s(
		{
			trig = ";ssc",
			dscr = "subsection",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "autosnippet",
		},
		fmt(
			[[
				\subsection{<>}
			]],
			{
				i(1),
			},
			{ delimiters = "<>" }
		),
		{ condition = line_begin }
	),
	s(
		{
			trig = ";sssc",
			dscr = "subsubsection",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "autosnippet",
		},
		fmt(
			[[
				\subsubsection{<>}
			]],
			{
				i(1),
			},
			{ delimiters = "<>" }
		),
		{ condition = line_begin }
	),
	s({
		trig = ";np",
		dscr = "newpage",
		wordTrig = "true",
		regTrig = "false",
		snippetType = "autosnippet",
	}, {
		t({
			[[\newpage]],
		}),
	}, { condition = line_begin }),
	s(
		{
			trig = "tabc",
			dscr = "centered tabular environment",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "snippet",
		},
		fmt(
			[[
				\begin{figure}[H]
					\begin{center}
						\begin{tabular}{<>}
							<>
						\end{tabular}
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
			trig = "tabgg",
			dscr = "tabular environment: 'gegeben, gesucht'",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "snippet",
		},
		fmt(
			[[
				\begin{figure}[H]
					Gegeben:~
					\begin{tabular}{<>}
						\hline
						<>
						\\ \hline
						<>
						\\ \hline
					\end{tabular}
				\end{figure}

				\vspace{-0.5cm}

				\begin{figure}[H]
					Gesucht:~
					\begin{tabular}{<>}
						\hline
						<>
						\\ \hline
					\end{tabular}
				\end{figure}
				<>
			]],
			{
				i(1),
				i(2),
				i(3),
				i(4),
				i(5),
				i(0),
			},
			{ delimiters = "<>" }
		),
		{ condition = line_begin }
	),
	s(
		{
			trig = "fig",
			dscr = "figure with graphics",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "snippet",
		},
		fmt(
			[[
				\begin{figure}[<>]
					\centering
					\includegraphics[width=<>\textwidth]{<>}
					\caption{<>}
				\end{figure}
				<>
			]],
			{
				i(1, "!htpb"),
				i(2, "0.9"),
				i(3, "<image-path>"),
				i(4, "<caption>"),
				i(0),
			},
			{ delimiters = "<>" }
		),
		{ condition = line_begin }
	),
	s(
		{
			trig = "figduo",
			dscr = "figure with two graphics next to each other",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "snippet",
		},
		fmt(
			[[
				\begin{figure}[<>]
					\centering
					\begin{minipage}{<>\textwidth}
						\centering
						\includegraphics[width=\textwidth]{<>}
						\caption{<>}
					\end{minipage}\hfill
					\begin{minipage}{<>\textwidth}
						\centering
						\includegraphics[width=\textwidth]{<>}
						\caption{<>}
					\end{minipage}
				\end{figure}
				<>
			]],
			{
				i(1, "!htbp"),
				i(2, "0.45"),
				i(3, "<image-1-path>"),
				i(4, "<caption-1>"),
				i(5, "0.45"),
				i(6, "<image-2-path>"),
				i(7, "<caption-2>"),
				i(0),
			},
			{ delimiters = "<>" }
		),
		{ condition = line_begin }
	),
	s(
		{
			trig = "figtrio",
			dscr = "figure with three graphics next to each other",
			wordTrig = "true",
			regTrig = "false",
			snippetType = "snippet",
		},
		fmt(
			[[
				\begin{figure}[<>]
					\centering
					\begin{minipage}{<>\textwidth}
						\centering
						\includegraphics[width=\textwidth]{<>}
						\caption{<>}
					\end{minipage}
					\begin{minipage}{<>\textwidth}
						\centering
						\includegraphics[width=\textwidth]{<>}
						\caption{<>}
					\end{minipage}
					\begin{minipage}{<>\textwidth}
						\centering
						\includegraphics[width=\textwidth]{<>}
						\caption{<>}
					\end{minipage}
				\end{figure}
				<>
			]],
			{
				i(1, "!htbp"),
				i(2, "0.3"),
				i(3, "<image-1-path>"),
				i(4, "<caption-1>"),
				i(5, "0.3"),
				i(6, "<image-2-path>"),
				i(7, "<caption-2>"),
				i(8, "0.3"),
				i(9, "<image-3-path>"),
				i(10, "<caption-3>"),
				i(0),
			},
			{ delimiters = "<>" }
		),
		{ condition = line_begin }
	),
}
