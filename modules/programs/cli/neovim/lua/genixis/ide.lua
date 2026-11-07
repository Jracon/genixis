-- the ide editor pane: yazi (ide-open) and the file tree (genixis.tree) open files
-- here, one tab each, the tree over the same rules as the socket
local M = {}

-- a fresh window's empty, unnamed, unmodified buffer, which a file should replace rather than
-- leave behind as a blank tab
local function blank(buf)
  return vim.api.nvim_buf_get_name(buf) == ""
    and not vim.bo[buf].modified
    and vim.api.nvim_buf_line_count(buf) == 1
    and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
end

-- the editor window of the current tab: the window that is not the file tree.
-- The tree opens files through open() too, and the file must not edit into the
-- tree window
local function editor_win()
  if vim.bo.filetype ~= "neo-tree" then
    return vim.api.nvim_get_current_win()
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= "neo-tree" then
      return win
    end
  end
  return nil
end

-- scheduled, so the --remote-expr call returns at once and prompts (e.g. a swap file) show in the pane
function M.open(paths)
  vim.schedule(function()
    local win = editor_win()
    for _, path in ipairs(paths) do
      local escaped = vim.fn.fnameescape(path)
      if win ~= nil and blank(vim.api.nvim_win_get_buf(win)) then
        vim.api.nvim_win_call(win, function()
          vim.cmd.edit(escaped)
        end)
      else
        -- switches to the tab already showing the file, if there is one
        vim.cmd("tab drop " .. escaped)
      end
    end
  end)
end

-- opens path like open(), and creates the file `done` once its buffer is gone (closed, or nvim
-- quit), so that a blocking caller (ide-edit, for $EDITOR) can wait for the edit to end
function M.edit(path, done)
  M.open({ path })
  vim.schedule(function()
    local buf = vim.fn.bufnr(vim.fn.fnamemodify(path, ":p"))
    local function finish()
      vim.fn.writefile({}, done)
    end
    if buf == -1 then
      return finish()
    end
    vim.api.nvim_create_autocmd({ "BufUnload", "BufDelete", "BufWipeout" }, {
      buffer = buf,
      once = true,
      callback = finish,
    })
    vim.api.nvim_create_autocmd("VimLeavePre", { once = true, callback = finish })
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
