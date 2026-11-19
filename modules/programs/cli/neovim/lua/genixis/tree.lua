-- the file tree of the editor pane (issue #196): neo-tree in a left split, with
-- git status at the right of each row and the keys of the leader-t group
local M = {}

local map = vim.keymap.set

-- the one call of the tree command: the filesystem source in the left split,
-- with the action of the caller and its extra keys (the reveal of focus).
-- Five call sites built the same table inline
local function execute(action, extra)
  require("neo-tree.command").execute(vim.tbl_extend("keep", extra or {}, {
    action = action,
    position = "left",
    source = "filesystem",
  }))
end

-- the marks of the rows (issue #205): nvim-web-devicons gives each file row
-- the icon and the color of its file type, and neo-tree loads the plugin on
-- its own. The folder glyphs are the nerd font defaults of neo-tree. The
-- terminal font of every host is Maple Mono NF, so the glyphs render
-- (docs/terminal-aesthetic.md). The git marks stay plain, so they render in
-- any terminal font
local function setup()
  require("neo-tree").setup({
    default_component_configs = {
      git_status = {
        symbols = {
          added = "+",
          conflict = "!",
          deleted = "-",
          ignored = "!",
          modified = "M",
          renamed = "R",
          staged = "✓",
          unstaged = "✗",
          untracked = "?",
        },
      },
      icon = {
        -- the fallback of a file with an unknown type, for which
        -- nvim-web-devicons has no icon; the folder glyphs come from the
        -- neo-tree defaults
        default = "?",
      },
    },
    default_source = "filesystem",
    filesystem = {
      filtered_items = {
        -- dotfiles and gitignored rows show, as the yazi pane showed them; a
        -- gitignored row carries the grey ignored mark. H hides them again
        never_show = { ".git" },
        visible = true,
      },
      follow_current_file = { enabled = true, leave_dirs_open = true },
      -- the libuv file watcher refreshes the tree on worktree events and on
      -- events of the git directory (neo-tree registers that watch itself),
      -- so an index-only git command such as git add also moves the git marks
      use_libuv_file_watcher = true,
      window = {
        -- q closes the tree through close_tree below, like the close chords
        mappings = {
          ["<cr>"] = M.open_node,
          ["h"] = "close_node",
          ["l"] = M.open_node,
        },
        width = 34,
      },
    },
    popup_border_style = "rounded",
    sources = { "filesystem" },
  })
end

-- Enter and l: a folder expands and collapses; a file opens in its own tab,
-- under the tab rules of ide-open (genixis.ide.open)
M.open_node = function(state)
  local node = state.tree:get_node()
  if node.type == "directory" then
    state.commands.toggle_node(state)
    return
  end
  require("genixis.ide").open({ node:get_id() })
end

-- shows and hides the tree of the current tab page only (issue #508 re-rules
-- issue #234): the show of one toggle in every tab page diverged the tree
-- state between the tabs and leaked tabs that hold only a tree window
-- (issue #506). The toggle reads the windows of the current tab, so the
-- module holds no shared state: a tree window there closes, and none shows
-- one. The tree windows of the other tabs stay as they are. The show action
-- steals no focus, so the cursor stays in the window of the person
M.toggle = function()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neo-tree" then
      execute("close")
      return
    end
  end
  execute("show")
end

-- focuses the tree and reveals the file of the current tab; from the tree, the
-- key goes back to the editor. A file outside the working directory reveals
-- nothing, because the reveal would ask for a change of the root
M.focus = function()
  if vim.bo.filetype == "neo-tree" then
    vim.cmd("wincmd p")
    return
  end
  local cwd = vim.uv.cwd()
  local file = vim.api.nvim_buf_get_name(0)
  execute("focus", { reveal = file ~= "" and file:sub(1, #cwd + 1) == cwd .. "/" })
end

-- the tree window is not a file: q and the close-file chord leader x close
-- the tree there. The toggle reads the window, so the next leader t t shows
-- the tree of that tab again
local function close_tree()
  if vim.bo.filetype == "neo-tree" then
    pcall(vim.cmd, "close")
  end
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "neo-tree",
  callback = function(args)
    -- the buffer-local no-op (issue #325) holds the global close-file map of
    -- keymaps.lua inert in the tree buffer: without it, the map would run
    -- there, delete the tree buffer, and close a tab with one file window.
    -- The tree closes only through the toggle, q, and leader x
    map("n", "<C-w>", "<nop>", { buffer = args.buf, desc = "No close in the tree" })
    map("n", "<leader>x", close_tree, { buffer = args.buf, desc = "Close the tree" })
    map("n", "q", close_tree, { buffer = args.buf, desc = "Close the tree" })
  end,
})

-- the close chords of keymaps.lua close a tab of one file window with its tree
-- window, but a file window can close by another hand: a typed :q in a file
-- window leaves the tree window as the only window of its tab, and nvim keeps
-- the tab alive (issue #506). The sweep closes such a tab, and the last tab
-- page of the nvim never closes: its tree windows close instead, over one
-- fresh empty window, so nvim stays open
local function sweep(tab)
  if not vim.api.nvim_tabpage_is_valid(tab) then
    -- the close of the window closed the tab with it, as the close chords
    -- close it, or the tab closed before the scheduled run
    return
  end
  local wins = vim.api.nvim_tabpage_list_wins(tab)
  for _, win in ipairs(wins) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= "neo-tree" then
      return
    end
  end
  local tabs = vim.api.nvim_list_tabpages()
  if #tabs > 1 then
    for i, t in ipairs(tabs) do
      if t == tab then
        -- the tab closes with its tree windows, as the close chords close it
        vim.cmd("tabclose " .. i)
        return
      end
    end
    return
  end
  -- the fresh window keeps the last tab open, and no tree window remains.
  -- The split of the tree window copies its fixed width and height into the
  -- fresh window (the renderer of neo-tree sets both on the tree window), so
  -- the fresh window drops both, as a plain file window
  vim.cmd("new")
  vim.cmd("setlocal nowinfixwidth nowinfixheight")
  for _, win in ipairs(wins) do
    vim.api.nvim_win_close(win, true)
  end
end

-- WinClosed fires while the closing window still sits in its tab page, so the
-- callback reads that tab. The check runs scheduled, after the close settles,
-- so a close path that closes the tab itself leaves an invalid tab that stops
-- the sweep
vim.api.nvim_create_autocmd("WinClosed", {
  callback = function(args)
    local win = tonumber(args.file)
    if win == nil then
      return
    end
    local ok, tab = pcall(vim.api.nvim_win_get_tabpage, win)
    if ok then
      vim.schedule(function()
        sweep(tab)
      end)
    end
  end,
})

-- a bare start opens the tree, as the yazi pane was there from the start; a
-- start with files keeps the full width for them
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    if vim.fn.argc() == 0 then
      execute("show")
    end
  end,
})

-- a session of mksession (ide reload) restores the tree window as a dead
-- buffer: close the dead windows, wipe the dead buffers, and open a live tree
-- in their place. The wipe must come first: the renderer refuses a second
-- buffer with the name of the dead one (E95), so the tree opens only over a
-- wiped buffer. A dead buffer with no window (a plain badd of the session)
-- holds the name the same way, so the wipe scans every buffer
vim.api.nvim_create_autocmd("SessionLoadPost", {
  callback = function()
    local had = false
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.fn.bufname(buf):find("^neo%-tree") and vim.bo[buf].filetype ~= "neo-tree" then
        pcall(vim.api.nvim_win_close, win, true)
        had = true
      end
    end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.fn.bufname(buf):find("^neo%-tree") and vim.bo[buf].filetype ~= "neo-tree" then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
    if had then
      -- the session saved its tree windows as dead buffers, so one live tree
      -- goes back into the current tab only (issue #508)
      execute("show")
    end
  end,
})

-- the renderer of neo-tree wraps no row and clamps no scroll itself, so the
-- tree window scrolls past its rows: the wheel and the touchpad move the view
-- until only the last row stays visible, and the horizontal scroll moves it
-- until no row stays visible. One clamp runs on every scroll, in the tree
-- windows only: the left column goes to zero, and the top line stops at the
-- row count minus the window height plus one, so the last row never rises
-- above the bottom edge
vim.api.nvim_create_autocmd("WinScrolled", {
  callback = function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neo-tree" then
        vim.api.nvim_win_call(win, function()
          local view = vim.fn.winsaveview()
          -- leftcol carries the horizontal scroll of a window with wrap off,
          -- the regime of the tree window. skipcol serves smoothscroll only:
          -- it reads 0 while that option is off, which this configuration
          -- never sets. Both fields stand in the dict of winsaveview on every
          -- nvim release from 0.10, the floor of this configuration, so each
          -- field is tested for itself. In lua the number 0 is truthy, so an
          -- or chain over both fields stops at the first one and never reads
          -- the second (issue #307). winrestview writes both back to 0 below
          local last_top = math.max(1, vim.api.nvim_buf_line_count(0) - vim.api.nvim_win_get_height(win) + 1)
          if view.leftcol > 0 or view.skipcol > 0 or view.topline > last_top then
            -- the keys left out keep their value, so the cursor keeps its row.
            -- The clamp scrolls nothing further, so the WinScrolled event of
            -- the clamp finds nothing left to do
            vim.fn.winrestview({ leftcol = 0, skipcol = 0, topline = math.min(view.topline, last_top) })
          end
        end)
      end
    end
  end,
})

setup()

map("n", "<leader>tt", M.toggle, { desc = "File tree" })
map("n", "<leader>tf", M.focus, { desc = "Focus file tree" })

return M
