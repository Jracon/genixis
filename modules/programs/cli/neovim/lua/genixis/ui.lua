-- 'background' comes from the terminal (WezTerm follows the OS appearance), so the colourscheme
-- re-reads it whenever it changes, e.g. `:set background=light`
vim.api.nvim_create_autocmd("OptionSet", {
  pattern = "background",
  callback = function()
    vim.cmd.colorscheme("themes")
  end,
})
vim.cmd.colorscheme("themes")

-- numbered tabs, to go with Ctrl+0..9 (shown once there are two)
function _G.genixis_tabline()
  local s = ""
  for n, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local buf = vim.api.nvim_win_get_buf(vim.api.nvim_tabpage_get_win(tab))
    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
    local hl = tab == vim.api.nvim_get_current_tabpage() and "%#TabLineSel#" or "%#TabLine#"
    s = s .. hl .. "%" .. n .. "T " .. (n % 10) .. " " .. (name == "" and "[No Name]" or name)
    s = s .. (vim.bo[buf].modified and " +" or "") .. " "
  end
  return s .. "%#TabLineFill#%T"
end
vim.o.tabline = "%!v:lua.genixis_tabline()"

local wk = require("which-key")
wk.setup({})
wk.add({
  { "<leader>f", group = "find" },
  { "<leader>h", group = "git hunk" },
})
