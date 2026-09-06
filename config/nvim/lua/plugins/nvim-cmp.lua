return {
	{
		"hrsh7th/nvim-cmp",
		---@param opts cmp.ConfigSchema
		opts = function(_, opts)
			local has_words_before = function()
				unpack = unpack or table.unpack
				local line, col = unpack(vim.api.nvim_win_get_cursor(0))
				return col ~= 0
					and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
			end

			local luasnip = require("luasnip")
			local cmp = require("cmp")

			-- stop enter from autocompleting
			opts.preselect = cmp.PreselectMode.None
			opts.completion = {
				completeopt = "noselect",
			}
			opts.mapping = vim.tbl_extend("force", opts.mapping, {
				["<CR>"] = cmp.mapping.confirm({ select = false }),
				["<S-CR>"] = cmp.mapping.confirm({ select = true }),
				["<C-j>"] = cmp.mapping(function(fallback)
					-- if cmp.visible() then
					-- You could replace select_next_item() with confirm({ select = true }) to get VS Code autocompletion behavior
					-- cmp.select_next_item()
					-- cmp.confirm({ select = true })
					-- You could replace the expand_or_jumpable() calls with expand_or_locally_jumpable()
					-- this way you will only jump inside the snippet region
					if luasnip.expand_or_jumpable() then
						luasnip.expand_or_jump()
						-- elseif has_words_before() then
						-- cmp.complete()
					else
						fallback()
					end
				end, { "i", "s" }),
				["<C-k>"] = cmp.mapping(function(fallback)
					if cmp.visible() then
						-- You could replace select_next_item() with confirm({ select = true }) to get VS Code autocompletion behavior
						-- cmp.select_next_item()
						cmp.confirm({ select = true })
						-- You could replace the expand_or_jumpable() calls with expand_or_locally_jumpable()
						-- this way you will only jump inside the snippet region
						-- elseif luasnip.expand_or_jumpable() then
						-- luasnip.expand_or_jump()
					elseif has_words_before() then
						cmp.complete()
					else
						fallback()
					end
				end, { "i", "s" }),
				["<C-l>"] = cmp.mapping(function(fallback)
					-- if cmp.visible() then
					-- cmp.select_prev_item()
					-- elseif luasnip.jumpable(-1) then
					if luasnip.jumpable(-1) then
						luasnip.jump(-1)
					else
						fallback()
					end
				end, { "i", "s" }),
				-- allow choice selection for luasnip
				["<C-f>"] = cmp.mapping(function(fallback)
					if luasnip.choice_active() then
						luasnip.change_choice(1)
					end
				end, { "i", "s" }),
			})
		end,
	},
}
