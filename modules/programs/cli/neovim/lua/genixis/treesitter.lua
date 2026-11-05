-- grammars are installed by Nix (nvim-treesitter.withPlugins in neovim.nix); this only turns them on
vim.api.nvim_create_autocmd("FileType", {
  callback = function(args)
    if pcall(vim.treesitter.start, args.buf) then
      vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
  end,
})

-- text objects select by syntax tree, not by pattern: `af`/`if` take a function, `ac`/`ic` a
-- class (a Go struct; lua and nix hold no class object), `aa`/`ia` an argument of a call or a
-- definition. Functions and classes select linewise, arguments charwise
local map = vim.keymap.set

require("nvim-treesitter-textobjects").setup({
  select = {
    lookahead = true, -- a match can sit after the cursor, as with targets.vim
    selection_modes = {
      ["@class.outer"] = "V",
      ["@function.outer"] = "V",
    },
  },
})

local select = require("nvim-treesitter-textobjects.select")
map({ "x", "o" }, "aa", function()
  select.select_textobject("@parameter.outer", "textobjects")
end, { desc = "Argument" })
map({ "x", "o" }, "ac", function()
  select.select_textobject("@class.outer", "textobjects")
end, { desc = "Class" })
map({ "x", "o" }, "af", function()
  select.select_textobject("@function.outer", "textobjects")
end, { desc = "Function" })
map({ "x", "o" }, "ia", function()
  select.select_textobject("@parameter.inner", "textobjects")
end, { desc = "Argument (inner)" })
map({ "x", "o" }, "ic", function()
  select.select_textobject("@class.inner", "textobjects")
end, { desc = "Class (inner)" })
map({ "x", "o" }, "if", function()
  select.select_textobject("@function.inner", "textobjects")
end, { desc = "Function (inner)" })

-- the same captures jump between functions. The plugin example maps `]m` and friends, but the
-- python ftplugin defines those buffer-locally, and a buffer-local map beats this global one
local move = require("nvim-treesitter-textobjects.move")
map({ "n", "x", "o" }, "]f", function()
  move.goto_next_start("@function.outer", "textobjects")
end, { desc = "Next function start" })
map({ "n", "x", "o" }, "]F", function()
  move.goto_next_end("@function.outer", "textobjects")
end, { desc = "Next function end" })
map({ "n", "x", "o" }, "[f", function()
  move.goto_previous_start("@function.outer", "textobjects")
end, { desc = "Previous function start" })
map({ "n", "x", "o" }, "[F", function()
  move.goto_previous_end("@function.outer", "textobjects")
end, { desc = "Previous function end" })
