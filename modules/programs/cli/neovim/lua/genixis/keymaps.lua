-- Neovim's built-in LSP maps are kept as-is: K hover, grn rename, gra code action,
-- grr references, gri implementation, grt type definition, grx code lens, gO symbols, [d / ]d diagnostics.
local map = vim.keymap.set

map("n", "<Esc>", "<cmd>nohlsearch<CR>")
map("n", "<leader>d", vim.diagnostic.open_float, { desc = "Line diagnostics" })
map("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Diagnostics to loclist" })
map("n", "<leader>w", "<cmd>write<CR>", { desc = "Write" })
-- Ctrl+S writes the file, the same action as the leader w chord (issue #195). The chord is one
-- byte, so ssh and tmux pass it unchanged, and nvim runs the pane tty in raw mode, so no pane
-- freezes on XOFF. The insert-mode map replaces the built-in LSP signature help of the key:
-- blink.cmp shows the signature window by itself while a person types in a call (editing.lua).
-- fish keeps its Ctrl+S for the search of the completion pager, and yazi keeps its Ctrl+S to
-- cancel an ongoing search
map("n", "<C-s>", "<cmd>write<CR>", { desc = "Write" })
map("i", "<C-s>", "<cmd>write<CR>", { desc = "Write" })

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
    -- tree window. A cancelled confirm prompt keeps the buffer and the tab.
    -- bdelete unlists a named buffer but keeps its handle valid (issue #288):
    -- the guard reads the listed state, before and after, not the handle. A
    -- buffer that was never listed (a help page, the tree) keeps its tab
    local tab = vim.api.nvim_get_current_tabpage()
    local listed = vim.bo[buf].buflisted
    vim.cmd("confirm bdelete " .. buf)
    if vim.api.nvim_tabpage_is_valid(tab) and listed and not vim.bo[buf].buflisted then
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
-- Ctrl+T opens a new editor tab with an empty buffer, with no file in it (issue #195); the tab
-- rules of ide-open then reuse the blank buffer for the next file that opens, from the tree or
-- from yazi. The map shadows the nvim tag-stack jump of normal mode and the one-shiftwidth
-- indent of insert mode; neither is in use. WezTerm holds the plain key as the legacy alias of
-- its new-tab key, so wezterm.nix disables the alias. fish keeps its Ctrl+T transpose, and the
-- default yazi keymap binds no Ctrl+T
map({ "n", "i" }, "<C-t>", "<cmd>tabnew<CR>", { desc = "New tab" })

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
