-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.g.maplocalleader = ","

-- alias definitions the editor settings
local set = vim.opt

-- basic settings
set.number = true -- enable line numbers
set.relativenumber = true -- enable relative line numbers
set.tabstop = 4 -- number of spaces a tab represents
set.shiftwidth = 4 -- number of spaces for each indentation
set.smartindent = true -- automatically indent new lines
set.smarttab = true -- 'shiftwidth' positions at line begin, 'tabstop' everywhere else
set.cursorline = true -- highlight the current line
set.expandtab = false -- force use of actual tabs instead of spaces
set.wrap = true -- force line wrapping
set.termguicolors = true -- enable 24-bit rgb colors
set.mouse = "a" -- enable mouse usage everywhere -- TODO check if works
set.showmode = false -- disable '-- INSERT/VISUAL/... --' in bottom line
-- set.updatetime = 500 -- set the 'write to disk after inactivity' time to 500ms
-- set.timeoutlen = 750 -- set the wait time for mapped sequence completion to 750ms
set.encoding = "utf-8" -- set the editor encoding to utf-8 -- TODO check if works

-- filetype plugins
vim.cmd("filetype plugin indent on")
