vim.g.mapleader = " "
vim.g.maplocalleader = " "

local opt = vim.opt

opt.clipboard = "unnamedplus" -- system clipboard; OSC 52 over SSH
opt.confirm = true
opt.cursorline = true
-- no hidden modified buffers: `:q` on one tab of several asks to save then, rather than keeping the
-- changes in the background until the file is opened again
opt.hidden = false
opt.expandtab = true
opt.ignorecase = true
opt.inccommand = "split"
opt.list = true
opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
opt.number = true
opt.scrolloff = 8
opt.shiftwidth = 2
opt.shortmess:append("I") -- no intro screen on an empty start (the ide editor pane)
opt.signcolumn = "yes"
opt.smartcase = true
opt.splitbelow = true
opt.splitright = true
opt.tabstop = 2
opt.undofile = true
opt.updatetime = 250
opt.wrap = false
