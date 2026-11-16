-- The one shell-out helper of the lua tree (issue #369): search.lua and
-- review.lua ran the same body, one command through vim.fn.system and the
-- read of its stdout, as two named copies and five inline ones. Every
-- function here answers nil when the command fails or prints nothing, so a
-- caller reads nil as failure. raw is the exception: it also answers the
-- success bit, because the diff flow holds its own policy for an empty
-- answer, an empty diff or an empty file version
local M = {}

-- raw answers the trimmed stdout of one command and whether it exited zero;
-- the caller holds the policy for a failure and for an empty answer
function M.raw(cmd)
  local out = vim.trim(vim.fn.system(cmd))
  return out, vim.v.shell_error == 0
end

-- out answers the trimmed stdout of one command, or nil when the command
-- failed or printed nothing
function M.out(cmd)
  local out, ok = M.raw(cmd)
  if not ok or out == "" then
    return nil
  end
  return out
end

-- lines answers the stdout lines of one command, or nil when the command
-- failed or printed nothing
function M.lines(cmd)
  local out = M.out(cmd)
  if out == nil then
    return nil
  end
  return vim.split(out, "\n")
end

-- git answers the trimmed stdout of one git command, or nil when the command
-- failed or printed nothing
function M.git(args)
  return M.out(vim.list_extend({ "git" }, args))
end

-- root answers the root of the working tree, or "." outside one
function M.root()
  return M.git({ "rev-parse", "--show-toplevel" }) or "."
end

return M
