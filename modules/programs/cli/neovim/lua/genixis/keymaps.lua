-- Neovim's built-in LSP maps are kept as-is: K hover, grn rename, gra code action,
-- grr references, gri implementation, gO symbols, [d / ]d diagnostics, Ctrl-s signature help.
local map = vim.keymap.set

map("n", "<Esc>", "<cmd>nohlsearch<CR>")
map("n", "<leader>d", vim.diagnostic.open_float, { desc = "Line diagnostics" })
map("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Diagnostics to loclist" })
map("n", "<leader>w", "<cmd>write<CR>", { desc = "Write" })

-- close the file but keep nvim open; `:q` in the ide editor pane would quit nvim. A file in a tab
-- of its own closes the tab, otherwise the window stays. The tree window of the tab is no file
-- window: it does not keep the tab open
local function file_wins()
  local n = 0
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= "neo-tree" then
      n = n + 1
    end
  end
  return n
end

local function closeBuffer()
  local buf = vim.api.nvim_get_current_buf()
  if #vim.api.nvim_list_tabpages() > 1 and file_wins() == 1 then
    -- bdelete alone leaves the tab open on an empty buffer: close it, with the
    -- tree window. A cancelled confirm prompt keeps the buffer and the tab
    local tab = vim.api.nvim_get_current_tabpage()
    vim.cmd("confirm bdelete " .. buf)
    if vim.api.nvim_tabpage_is_valid(tab) and not vim.api.nvim_buf_is_valid(buf) then
      vim.cmd("tabclose")
    end
    return
  end
  -- leaving a modified buffer asks to save (no 'hidden'); cancelling keeps it open
  pcall(vim.cmd, #vim.fn.getbufinfo({ buflisted = 1 }) > 1 and "bprevious" or "enew")
  if vim.api.nvim_get_current_buf() == buf then
    return
  end
  vim.cmd("confirm bdelete " .. buf)
end

map("n", "<leader>x", closeBuffer, { desc = "Close buffer" })
-- Ctrl+W closes the editor tab (issue #165): a Tool-layer chord of nvim only. It shadows
-- the window-command prefix of nvim; :wincmd still moves between the split of a diff or of
-- an inccommand preview. fish keeps its Ctrl+W at the prompt, and yazi binds no Ctrl+W
map("n", "<C-w>", closeBuffer, { desc = "Close buffer" })

-- Ctrl+1..9 go to that tab, Ctrl+0 the 10th, Ctrl+(Shift+)Tab the next (previous); in ide windows tmux takes these keys and calls the
-- same function over the socket, so they work from any pane
for n = 0, 9 do
  map("n", "<C-" .. n .. ">", function()
    require("genixis.ide").tab(n)
  end, { desc = "Tab " .. (n == 0 and 10 or n) })
end
map("n", "<C-Tab>", function()
  require("genixis.ide").step(1)
end, { desc = "Next tab" })
map("n", "<C-S-Tab>", function()
  require("genixis.ide").step(-1)
end, { desc = "Previous tab" })

-- j/k move by screen line in wrapped text; with a count they keep moving by real lines
map({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { expr = true })
map({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { expr = true })
map({ "n", "x" }, "<Down>", "v:count == 0 ? 'gj' : 'j'", { expr = true })
map({ "n", "x" }, "<Up>", "v:count == 0 ? 'gk' : 'k'", { expr = true })

-- insert mode: the arrows move by screen line too, but still drive the completion menu
map("i", "<Down>", "pumvisible() ? '<Down>' : '<C-o>gj'", { expr = true })
map("i", "<Up>", "pumvisible() ? '<Up>' : '<C-o>gk'", { expr = true })
-- Home/End go to the start/end of the screen line
map({ "n", "x" }, "<Home>", "g<Home>")
map({ "n", "x" }, "<End>", "g<End>")
map("i", "<Home>", "<C-o>g<Home>")
map("i", "<End>", "<C-o>g<End>")

-- keep the selection when indenting
map("v", "<", "<gv")
map("v", ">", ">gv")
