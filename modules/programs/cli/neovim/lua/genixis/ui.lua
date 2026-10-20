require("tokyonight").setup({
  style = "night", -- matches WezTerm's "Tokyo Night"
})
vim.cmd.colorscheme("tokyonight")

local wk = require("which-key")
wk.setup({})
wk.add({
  { "<leader>f", group = "find" },
  { "<leader>h", group = "git hunk" },
})
