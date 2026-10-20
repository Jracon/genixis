require("catppuccin").setup({
  flavour = "mocha", -- matches WezTerm
})
vim.cmd.colorscheme("catppuccin")

local wk = require("which-key")
wk.setup({})
wk.add({
  { "<leader>f", group = "find" },
  { "<leader>h", group = "git hunk" },
})
