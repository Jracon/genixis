-- The unified search of issue #189 in the editor, and the hand-off of a
-- question to the session agent. <leader>fq runs the fast tier that the
-- `search` wrapper of fish.nix runs (rg, the BM25 of qmd, and semble, after
-- a per-request qmd index refresh) and shows the grouped results in one
-- fzf-lua picker; the preview goes through qmd get, which keeps the line
-- numbers, and falls back to bat for files that no index holds. <leader>a in
-- visual mode bundles the selection with its context, asks the question, and
-- sends it to the claude pane of the ide window through `project ask`, which
-- owns the pane search and the tmux paste. The standalone quick question is
-- `project lmk`, which no mapping here calls.
local M = {}

-- run runs one command and answers its output lines, or nil when it fails
local function run(cmd)
  local out = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil
  end
  out = vim.trim(out)
  if out == "" then
    return nil
  end
  return vim.split(out, "\n")
end

-- qmdIndex says whether this tree holds the qmd index that AGENTS.md
-- commits. findfile walks upward from the directory of the current buffer
-- and checks .qmd/index.yaml before .qmd/index.yml, the walk and the order
-- of qmd itself, so a subdirectory of a checkout also finds the index
local function qmdIndex()
  if vim.fn.findfile(".qmd/index.yaml", ".;") ~= "" then
    return true
  end
  return vim.fn.findfile(".qmd/index.yml", ".;") ~= ""
end

-- refresh runs the per-request qmd refresh of the wrapper: qmd update and
-- qmd embed are cheap, and a stale or empty index is the silent failure that
-- the unified search exists to end
local function refresh()
  if vim.fn.executable("qmd") == 0 or not qmdIndex() then
    return
  end
  run({ "qmd", "update" })
  run({ "qmd", "embed" })
end

-- tags colors the tool name of an entry; the group marker travels with the
-- entry, because the scores of the three tools are not comparable, so the
-- results stay grouped, never fused. The tag holds no space, so the entry
-- still splits on its two-space separators
local function tag(name, color)
  return "\27[" .. color .. ";1m" .. name .. "\27[0m"
end

-- parseRg reads the file:line:col:text lines of rg --vimgrep
local function parseRg(lines, entries)
  for _, line in ipairs(lines) do
    local file, lnum, text = line:match("^(.-):(%d+):%d+:(.*)$")
    if file then
      table.insert(entries, tag("rg", "36") .. "  " .. file .. "  " .. lnum .. "  " .. text)
    end
  end
end

-- parseQmd reads the plain result blocks of qmd (a pipe, so no TTY colours):
-- each block opens with `path:line #docid`, holds a `Title:` line, and ends
-- before the next block
local function parseQmd(lines, entries)
  local file, lnum, title
  local function flush()
    if file then
      table.insert(entries, tag("qmd", "35") .. "  " .. file .. "  " .. lnum .. "  " .. (title or ""))
    end
  end
  for _, line in ipairs(lines) do
    local path, line1 = line:match("^(%S+):(%d+)%s+#")
    if path then
      flush()
      file, lnum, title = path, line1, nil
    elseif file and line:match("^Title:%s") then
      title = line:gsub("^Title:%s*", "")
    end
  end
  flush()
end

-- parseSemble reads the JSON of semble search, whose results array holds
-- file_path, start_line, end_line, and score (the search skill pins the
-- shape); a snippet field rides along when the tool prints one
local function parseSemble(out, entries)
  local ok, decoded = pcall(vim.json.decode, out)
  if not ok or type(decoded) ~= "table" or type(decoded.results) ~= "table" then
    return
  end
  for _, result in ipairs(decoded.results) do
    if type(result) == "table" and result.file_path and result.start_line then
      local text = ""
      if type(result.snippet) == "string" then
        text = vim.trim(result.snippet:gsub("\n", " "))
      end
      table.insert(
        entries,
        tag("semble", "33") .. "  " .. result.file_path .. "  " .. result.start_line .. "  " .. text
      )
    end
  end
end

-- M.fast runs the fast tier and answers the picker entries
function M.fast(query)
  refresh()
  local entries = {}
  if vim.fn.executable("rg") == 1 then
    local lines = run({ "rg", "--vimgrep", "--smart-case", "--max-count", "3", "--", query })
    if lines then
      parseRg(lines, entries)
    end
  end
  if vim.fn.executable("qmd") == 1 then
    local lines = run({ "qmd", "search", "-n", "10", query })
    if lines then
      parseQmd(lines, entries)
    end
  end
  if vim.fn.executable("semble") == 1 then
    local out = vim.fn.system({ "semble", "search", "--content", "all", "-k", "5", "--format", "json", query })
    if vim.v.shell_error == 0 and vim.trim(out) ~= "" then
      parseSemble(out, entries)
    end
  end
  return entries
end

-- leaveVisual ends the visual mode of a mapping, so the input prompt of the
-- question opens on a normal-mode screen
local function leaveVisual()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
end

-- M.pick asks for the query (the visual selection is the default) and opens
-- the picker of the fast tier
function M.pick()
  local default = ""
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    local start = vim.fn.line("'<")
    local stop = vim.fn.line("'>")
    if stop < start then
      start, stop = stop, start
    end
    local words = {}
    for lnum = start, math.min(stop, start + 5) do
      table.insert(words, vim.trim(vim.fn.getline(lnum)))
    end
    default = table.concat(words, " "):sub(1, 120)
    leaveVisual()
  end
  vim.ui.input({ prompt = "Search> ", default = default }, function(input)
    if not input or vim.trim(input) == "" then
      return
    end
    local entries = M.fast(vim.trim(input))
    if #entries == 0 then
      vim.notify("search: no fast results; try `search --deep` at the prompt", vim.log.levels.WARN)
      return
    end
    M.picker(entries)
  end)
end

-- M.picker shows the entries of one finished fast tier. The fields of an
-- entry are tag, file, line, text, cut on two spaces, so the preview reaches
-- the file and the line of the entry under the cursor
function M.picker(entries)
  require("fzf-lua").fzf_exec(entries, {
    prompt = "Search> ",
    preview = "qmd get {2}:{3}:16 2>/dev/null || bat --color=always --style=numbers --line-range {3}: -- {2}",
    fzf_opts = { ["--delimiter"] = "  ", ["--nth"] = "2.." },
    actions = {
      ["enter"] = function(selected)
        local file, lnum = selected[1]:match("^%S+  (.-)  (%d+)  ")
        if not file then
          return
        end
        vim.cmd("edit " .. vim.fn.fnameescape(file))
        vim.api.nvim_win_set_cursor(0, { tonumber(lnum), 0 })
      end,
    },
  })
end

-- hover collects the hover text of the symbol under the cursor, best effort
local function hover()
  local ok, result = pcall(
    vim.lsp.buf_request_sync,
    0,
    "textDocument/hover",
    vim.lsp.util.make_position_params(),
    600
  )
  if not ok or type(result) ~= "table" then
    return nil
  end
  for _, res in pairs(result) do
    local contents = res and res.result and res.result.contents
    if type(contents) == "string" and contents ~= "" then
      return contents
    end
    if type(contents) == "table" then
      if type(contents.value) == "string" and contents.value ~= "" then
        return contents.value
      end
      if contents[1] then
        local parts = {}
        for _, part in ipairs(contents) do
          table.insert(parts, type(part) == "string" and part or part.value or "")
        end
        local joined = vim.trim(table.concat(parts, "\n"))
        if joined ~= "" then
          return joined
        end
      end
    end
  end
  return nil
end

-- M.ask is the visual-mode ask mapping: it bundles the selection with its
-- context into .scratch/, asks the question, and hands both to project ask
function M.ask()
  local start = vim.fn.line("'<")
  local stop = vim.fn.line("'>")
  if stop < start then
    start, stop = stop, start
  end
  local rel = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":.")
  local selection = {}
  for lnum = start, math.min(stop, start + 60) do
    table.insert(selection, vim.fn.getline(lnum))
  end
  leaveVisual()
  local word = vim.fn.expand("<cword>")
  local lines = {
    "# Question from the editor",
    "",
    "- File: " .. rel,
    "- Lines: " .. start .. "-" .. stop,
  }
  if word ~= "" then
    table.insert(lines, "- Word under cursor: " .. word)
  end
  table.insert(lines, "")
  table.insert(lines, "## Selection")
  table.insert(lines, "")
  table.insert(lines, "```")
  for _, line in ipairs(selection) do
    table.insert(lines, line)
  end
  table.insert(lines, "```")
  local text = hover()
  if text then
    table.insert(lines, "")
    table.insert(lines, "## LSP hover")
    table.insert(lines, "")
    table.insert(lines, "```")
    for _, line in ipairs(vim.split(text, "\n")) do
      table.insert(lines, line)
    end
    table.insert(lines, "```")
  end
  vim.ui.input({ prompt = "Ask the session> " }, function(question)
    if not question or vim.trim(question) == "" then
      return
    end
    local root = vim.fn.system({ "git", "rev-parse", "--show-toplevel" })
    if vim.v.shell_error ~= 0 then
      root = "."
    end
    root = vim.trim(root)
    vim.fn.mkdir(root .. "/.scratch", "p")
    local relscratch = ".scratch/ask-" .. os.date("%Y-%m-%d-%H%M%S") .. ".md"
    vim.fn.writefile(lines, root .. "/" .. relscratch)
    vim.fn.system({ "project", "ask", "--context", relscratch, "--", vim.trim(question) })
    if vim.v.shell_error == 0 then
      vim.notify("ask: the question reached the session pane")
    else
      vim.notify("ask: project ask failed with exit " .. vim.v.shell_error, vim.log.levels.ERROR)
    end
  end)
end

local map = vim.keymap.set
map({ "n", "x" }, "<leader>fq", M.pick, { desc = "Unified search (rg, qmd, semble)" })
map("x", "<leader>a", M.ask, { desc = "Ask the session agent" })

return M
