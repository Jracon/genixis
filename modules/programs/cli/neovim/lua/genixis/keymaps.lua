-- Neovim's built-in LSP maps are kept as-is: K hover, grn rename, gra code action,
-- grr references, gri implementation, gO symbols, [d / ]d diagnostics, Ctrl-s signature help.
local map = vim.keymap.set

map("n", "<Esc>", "<cmd>nohlsearch<CR>")
map("n", "<leader>d", vim.diagnostic.open_float, { desc = "Line diagnostics" })
map("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Diagnostics to loclist" })
map("n", "<leader>w", "<cmd>write<CR>", { desc = "Write" })
-- close the file but keep nvim open; `:q` in the ide editor pane would quit nvim. A file in a tab
-- of its own closes the tab, otherwise the window stays
map("n", "<leader>x", function()
  local buf = vim.api.nvim_get_current_buf()
  if #vim.api.nvim_list_tabpages() > 1 and #vim.api.nvim_tabpage_list_wins(0) == 1 then
    vim.cmd("confirm bdelete " .. buf)
    return
  end
  vim.cmd("bprevious")
  if vim.api.nvim_get_current_buf() == buf then
    vim.cmd("enew")
  end
  vim.cmd("confirm bdelete " .. buf)
end, { desc = "Close buffer" })

-- Ctrl+1..9 go to that tab, Ctrl+0 the 10th; in ide windows tmux takes these keys and calls the
-- same function over the socket, so they work from any pane
for n = 0, 9 do
  map("n", "<C-" .. n .. ">", function()
    require("genixis.ide").tab(n)
  end, { desc = "Tab " .. (n == 0 and 10 or n) })
end

-- keep the selection when indenting
map("v", "<", "<gv")
map("v", ">", ">gv")
