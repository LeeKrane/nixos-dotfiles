-- Disable Mason and friends: LSP servers/formatters/DAP adapters are
-- provided declaratively by modules/home/neovim.nix (home.packages), not
-- downloaded at runtime by Mason. Both the current LazyVim plugin names
-- (mason-org/*, since the williamboman -> mason-org GitHub org transfer)
-- and the older williamboman/* names are disabled here: lazy.nvim treats an
-- `{ "<repo>", enabled = false }` spec for a plugin that isn't otherwise
-- referenced as a harmless new (disabled) entry, so listing both spellings
-- is safe regardless of which one this LazyVim version actually uses.
return {
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
  { "mason-org/mason-nvim-dap.nvim", enabled = false },

  { "williamboman/mason.nvim", enabled = false },
  { "williamboman/mason-lspconfig.nvim", enabled = false },
  { "jay-babu/mason-nvim-dap.nvim", enabled = false },
}
