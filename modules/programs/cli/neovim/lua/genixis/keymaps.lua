-- Neovim's built-in LSP maps are kept as-is: K hover, grn rename, gra code action,
-- grr references, gri implementation, gO symbols, [d / ]d diagnostics, Ctrl-s signature help.
-- Ctrl-h/j/k/l move between splits and tmux panes (vim-tmux-navigator).
local map = vim.keymap.set

map("n", "<Esc>", "<cmd>nohlsearch<CR>")
map("n", "<leader>d", vim.diagnostic.open_float, { desc = "Line diagnostics" })
map("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Diagnostics to loclist" })
map("n", "<leader>w", "<cmd>write<CR>", { desc = "Write" })

-- keep the selection when indenting
map("v", "<", "<gv")
map("v", ">", ">gv")
