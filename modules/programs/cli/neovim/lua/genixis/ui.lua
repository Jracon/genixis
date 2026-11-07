-- 'background' comes from the terminal (WezTerm follows the OS appearance), so the colourscheme
-- re-reads it whenever it changes, e.g. `:set background=light`
vim.api.nvim_create_autocmd("OptionSet", {
  pattern = "background",
  callback = function()
    vim.cmd.colorscheme("themes")
  end,
})
vim.cmd.colorscheme("themes")

-- numbered tabs, to go with Ctrl+0..9; always shown, also with a single file open (issue
-- #193), so the editor window keeps its tab view from the first buffer on
vim.o.showtabline = 2
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

-- the statusline, one line under the tabline's rules: theme groups only, no hex value here.
-- The mode carries the signature colour (through the Title group), the diagnostics count in
-- plain words, and the branch and the position sit right-aligned
vim.api.nvim_set_hl(0, "GenixisMode", { link = "Title" })

-- the branch of the buffer's working tree, read by a background job and cached per buffer:
-- a redraw of the statusline runs no git process, it only reads the cache. FocusGained
-- drops the cache, so a checkout done in another pane shows after the next focus
local branchOf = {}
local function branch()
  local buf = vim.api.nvim_get_current_buf()
  if branchOf[buf] == nil then
    branchOf[buf] = ""
    vim.system(
      { "git", "-C", vim.fn.expand("%:p:h"), "rev-parse", "--abbrev-ref", "HEAD" },
      { text = true },
      function(res)
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(buf) then
            branchOf[buf] = res.code == 0 and res.stdout:gsub("%s+$", "") or ""
            vim.cmd("redrawstatus")
          end
        end)
      end
    )
  end
  return branchOf[buf]
end
vim.api.nvim_create_autocmd("FocusGained", {
  callback = function()
    for b in pairs(branchOf) do
      branchOf[b] = nil
    end
  end,
})

function _G.genixis_statusline()
  local raw = vim.api.nvim_get_mode().mode
  local mode = ({
    n = "normal",
    no = "operator",
    i = "insert",
    R = "replace",
    Rv = "replace",
    v = "visual",
    V = "visual line",
    ["\22"] = "visual block",
    t = "terminal",
    c = "command",
  })[raw] or raw
  local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":.")
  if name == "" then
    name = "[No Name]"
  end
  local counts = vim.diagnostic.count(0)
  local errors = counts[vim.diagnostic.severity.ERROR] or 0
  local warnings = counts[vim.diagnostic.severity.WARN] or 0
  local diag = ""
  if errors > 0 then
    diag = diag .. " %#DiagnosticError#err " .. errors
  end
  if warnings > 0 then
    diag = diag .. " %#DiagnosticWarn#warn " .. warnings
  end
  local b = branch()
  return "%#GenixisMode# "
    .. mode
    .. "%* "
    .. name
    .. diag
    .. "%="
    .. (b ~= "" and b .. " " or "")
    .. "%l:%c %p%% "
end

local wk = require("which-key")
wk.setup({})
wk.add({
  { "<leader>D", group = "debug" },
  { "<leader>f", group = "find" },
  { "<leader>h", group = "git hunk" },
  { "<leader>r", group = "test" },
  { "<leader>t", group = "toggle" },
  { "<leader>v", group = "diff versus base" },
})
