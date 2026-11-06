-- The diff flow of a review worktree (issue #181): what changed against the
-- base branch, at three depths. The quickfix lists the files, one file opens
-- beside its version at the base, and three surfaces render the whole branch
-- in a tmux popup: lazygit (delta renders its diffs), hunk, and tuicr. The
-- base is the projectBase of the branch when the git config names one, else
-- the branch that origin/HEAD names, else main.
local M = {}

-- gitOut runs one git command and returns its trimmed stdout, or nil when
-- the command fails
local function gitOut(args)
  local out = vim.fn.system(vim.list_extend({ "git" }, args))
  if vim.v.shell_error ~= 0 then
    return nil
  end
  out = vim.trim(out)
  if out == "" then
    return nil
  end
  return out
end

-- M.base is the branch that the worktree works against
function M.base()
  local branch = gitOut({ "branch", "--show-current" })
  if branch then
    local configured = gitOut({ "config", "--get", "branch." .. branch .. ".projectBase" })
    if configured then
      return configured
    end
  end
  local head = gitOut({ "rev-parse", "--abbrev-ref", "origin/HEAD" })
  if head then
    return (head:gsub("^origin/", ""))
  end
  return "main"
end

-- M.files fills the quickfix with the files that differ from the base
function M.files()
  local base = M.base()
  local range = base .. "...HEAD"
  local out = vim.fn.system({ "git", "diff", "--name-only", range })
  if vim.v.shell_error ~= 0 then
    vim.notify("review: git diff " .. range .. " failed", vim.log.levels.WARN)
    return
  end
  local items = {}
  for _, name in ipairs(vim.split(vim.trim(out), "\n")) do
    if name ~= "" then
      table.insert(items, { filename = name, text = "differs from " .. base })
    end
  end
  vim.fn.setqflist({}, " ", { title = "diff " .. range, items = items })
  vim.cmd("cwindow")
  if #items == 0 then
    vim.notify("review: nothing differs from " .. base)
  end
end

-- M.file shows the current file beside its version at the base, as one diff
function M.file()
  local base = M.base()
  local rel = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":.")
  if rel == "" then
    vim.notify("review: this buffer holds no file name", vim.log.levels.WARN)
    return
  end
  local out = vim.fn.system({ "git", "show", base .. ":" .. rel })
  if vim.v.shell_error ~= 0 then
    vim.notify("review: " .. rel .. " holds no version at " .. base, vim.log.levels.WARN)
    return
  end
  local name = rel .. " @ " .. base
  local existing = vim.fn.bufnr(name)
  if existing ~= -1 then
    vim.cmd("bdelete " .. existing)
  end
  vim.cmd("leftabove vertical new")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(out, "\n"))
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  vim.cmd("diffthis")
  vim.cmd("wincmd l")
  vim.cmd("diffthis")
end

-- popup runs one command of the flow in a tmux popup over the worktree. The
-- call blocks until the popup closes, so nvim waits while its owner reads
local function popup(command)
  if vim.env.TMUX == nil then
    vim.notify("review: the diff surfaces open in a tmux popup", vim.log.levels.WARN)
    return
  end
  local root = gitOut({ "rev-parse", "--show-toplevel" }) or "."
  local args = vim.list_extend(
    { "tmux", "display-popup", "-E", "-d", root, "-h", "90%", "-w", "90%" },
    command
  )
  vim.fn.system(args)
end

-- M.lazygit opens lazygit at the worktree root: delta renders its diffs, and
-- its branches view shows the divergence from the base branch
function M.lazygit()
  popup({ "lazygit" })
end

-- M.hunk reads the whole branch against the base, with watch mode while the
-- branch moves
function M.hunk()
  popup({ "hunk", "diff", M.base() .. "...HEAD" })
end

-- M.tuicr reads the same range with vim keys and note capture. Do not use
-- its submit command: the owner writes to the forge
function M.tuicr()
  popup({ "tuicr", "-r", M.base() .. "..HEAD" })
end

local map = vim.keymap.set
map("n", "<leader>vd", M.file, { desc = "Diff file vs base" })
map("n", "<leader>vg", M.lazygit, { desc = "lazygit (delta diffs)" })
map("n", "<leader>vh", M.hunk, { desc = "hunk: branch vs base" })
map("n", "<leader>vq", M.files, { desc = "Files vs base (quickfix)" })
map("n", "<leader>vt", M.tuicr, { desc = "tuicr: branch vs base" })

return M
