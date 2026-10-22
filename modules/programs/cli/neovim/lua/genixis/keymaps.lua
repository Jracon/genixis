-- Neovim's built-in LSP maps are kept as-is: K hover, grn rename, gra code action,
-- grr references, gri implementation, gO symbols, [d / ]d diagnostics, Ctrl-s signature help.
local map = vim.keymap.set

map("n", "<Esc>", "<cmd>nohlsearch<CR>")
map("n", "<leader>d", vim.diagnostic.open_float, { desc = "Line diagnostics" })
map("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Diagnostics to loclist" })
map("n", "<leader>w", "<cmd>write<CR>", { desc = "Write" })
-- close the file but keep the window (and nvim) open; `:q` in the ide editor pane would quit nvim
map("n", "<leader>x", function()
  local buf = vim.api.nvim_get_current_buf()
  vim.cmd("bprevious")
  if vim.api.nvim_get_current_buf() == buf then
    vim.cmd("enew")
  end
  vim.cmd("confirm bdelete " .. buf)
end, { desc = "Close buffer" })

-- keep the selection when indenting
map("v", "<", "<gv")
map("v", ">", ">gv")
