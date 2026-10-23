-- the ide editor pane: yazi (ide-open) opens files here over the --listen socket, one tab each
local M = {}

-- a fresh window's empty, unnamed, unmodified buffer, which a file should replace rather than
-- leave behind as a blank tab
local function blank(buf)
  return vim.api.nvim_buf_get_name(buf) == ""
    and not vim.bo[buf].modified
    and vim.api.nvim_buf_line_count(buf) == 1
    and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
end

-- scheduled, so the --remote-expr call returns at once and prompts (e.g. a swap file) show in the pane
function M.open(paths)
  vim.schedule(function()
    for _, path in ipairs(paths) do
      if blank(vim.api.nvim_get_current_buf()) then
        vim.cmd.edit(vim.fn.fnameescape(path))
      else
        -- switches to the tab already showing the file, if there is one
        vim.cmd("tab drop " .. vim.fn.fnameescape(path))
      end
    end
  end)
end

-- tab n (0 is the 10th), if there is one; tmux's Ctrl+0..9 calls this in ide windows
function M.tab(n)
  n = n == 0 and 10 or n
  if n <= #vim.api.nvim_list_tabpages() then
    vim.cmd.tabnext(n)
  end
end

-- the next (1) or previous (-1) tab, wrapping; tmux's Ctrl+(Shift+)Tab calls this in ide windows
function M.step(d)
  vim.cmd(d > 0 and "tabnext" or "tabprevious")
end

return M
