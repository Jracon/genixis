vim.g.mapleader = " "
vim.g.maplocalleader = " "

local opt = vim.opt

opt.clipboard = "unnamedplus" -- system clipboard; OSC 52 over SSH
opt.confirm = true
opt.cursorline = true
opt.expandtab = true
opt.ignorecase = true
opt.inccommand = "split"
opt.list = true
opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
opt.number = true
opt.scrolloff = 8
opt.shiftwidth = 2
opt.signcolumn = "yes"
opt.smartcase = true
opt.splitbelow = true
opt.splitright = true
opt.tabstop = 2
opt.undofile = true
opt.updatetime = 250
opt.wrap = false
