-- 'background' comes from the terminal (WezTerm follows the OS appearance), so the colourscheme
-- re-reads it whenever it changes, e.g. `:set background=light`
vim.api.nvim_create_autocmd("OptionSet", {
  pattern = "background",
  callback = function()
    vim.cmd.colorscheme("themes")
  end,
})
vim.cmd.colorscheme("themes")

local wk = require("which-key")
wk.setup({})
wk.add({
  { "<leader>f", group = "find" },
  { "<leader>h", group = "git hunk" },
})
