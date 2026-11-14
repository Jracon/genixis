-- the ide editor pane: yazi (ide-open) and the file tree (genixis.tree) open files
-- here, one tab each, the tree over the same rules as the socket, and the session
-- of the claude pane follows its own edits through follow()
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

-- opens one file under the tab rules: a blank fresh buffer is reused, a file that is
-- already open switches to its tab, and anything else opens in its own tab
local function drop(path)
  local escaped = vim.fn.fnameescape(path)
  local win = editor_win()
  if win ~= nil and blank(vim.api.nvim_win_get_buf(win)) then
    vim.api.nvim_win_call(win, function()
      vim.cmd.edit(escaped)
    end)
  else
    -- switches to the tab already showing the file, if there is one
    vim.cmd("tab drop " .. escaped)
  end
end

-- scheduled, so the --remote-expr call returns at once and prompts (e.g. a swap file) show in the pane
function M.open(paths)
  vim.schedule(function()
    for _, path in ipairs(paths) do
      drop(path)
    end
  end)
end

-- the buffers whose reload skip the pane already stated once: repeated follows of one
-- modified buffer stay quiet until the buffer reloads again
local skip_stated = {}

-- follows one file that the session of the claude pane changed (issue #190): open()
-- for one file, plus the reload. An unmodified buffer re-reads from disk, so the pane
-- shows what the session wrote; a modified buffer never reloads, because the unsaved
-- edits of the person win, and the pane states the skip once. Scheduled like open(),
-- and the pane is never selected: the follow runs behind the session, so the focus of
-- the person stays in the claude pane
function M.follow(path)
  vim.schedule(function()
    local full = vim.fn.fnamemodify(path, ":p")
    local buf = vim.fn.bufnr(full)
    if buf ~= -1 and vim.bo[buf].modified then
      drop(full)
      if not skip_stated[buf] then
        skip_stated[buf] = true
        vim.notify(
          "ide: " .. vim.fn.fnamemodify(full, ":~") .. " holds unsaved edits; showing it without a reload",
          vim.log.levels.WARN
        )
      end
      return
    end
    drop(full)
    if buf ~= -1 then
      -- the buffer existed: reload it from disk, whatever window holds it
      skip_stated[buf] = nil
      vim.cmd("checktime " .. buf)
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
