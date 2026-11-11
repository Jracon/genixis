-- the file tree of the editor pane (issue #196): neo-tree in a left split, with
-- git status at the right of each row and the keys of the leader-t group
local M = {}

-- the toggle state shared by every editor tab (issue #234): an nvim window
-- belongs to one tab page only, so one tree window across tabs is not
-- possible. The state on means a tree window in every tab. Leader t t turns
-- it, and the other points that open or close the tree keep it correct
local visible = false

-- runs fn in every tab page in turn. The call makes its tab the current one
-- for fn, so a window command of fn lands in that tab
local function each_tab(fn)
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    -- pcall: the close of a tab that holds only the tree window closes the
    -- tab with it, so a tab of the list can be gone before its turn
    pcall(vim.api.nvim_tabpage_call, tab, fn)
  end
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
        -- q closes the tree through close_tree below, so it turns the shared
        -- toggle off like the close chords
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

-- hides and shows the tree in every editor tab at once: on, the show action
-- runs in every tab page; off, the close action runs the same way. The show
-- action steals no focus, so the cursor stays in the window of the person
M.toggle = function()
  visible = not visible
  each_tab(function()
    require("neo-tree.command").execute({
      action = visible and "show" or "close",
      position = "left",
      source = "filesystem",
    })
  end)
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
  require("neo-tree.command").execute({
    action = "focus",
    position = "left",
    reveal = file ~= "" and file:sub(1, #cwd + 1) == cwd .. "/",
    source = "filesystem",
  })
end

-- the tree window is not a file: the close-file keys and q close the tree
-- there. The shared toggle goes off with the window, so the next leader t t
-- shows every tree again
local function close_tree()
  if vim.bo.filetype == "neo-tree" then
    visible = false
    pcall(vim.cmd, "close")
  end
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "neo-tree",
  callback = function(args)
    vim.keymap.set("n", "<C-w>", close_tree, { buffer = args.buf, desc = "Close the tree" })
    vim.keymap.set("n", "<leader>x", close_tree, { buffer = args.buf, desc = "Close the tree" })
    vim.keymap.set("n", "q", close_tree, { buffer = args.buf, desc = "Close the tree" })
  end,
})

-- a new tab starts with the tree while the shared toggle is on. The tab drop
-- of ide-open (genixis.ide.open) enters each tab it creates, so a new file
-- tab gets the tree too
vim.api.nvim_create_autocmd("TabNewEntered", {
  callback = function()
    if visible then
      require("neo-tree.command").execute({
        action = "show",
        position = "left",
        source = "filesystem",
      })
    end
  end,
})

-- a bare start opens the tree, as the yazi pane was there from the start, and
-- the shared toggle reads on; a start with files keeps the full width for
-- them
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    if vim.fn.argc() == 0 then
      visible = true
      require("neo-tree.command").execute({
        action = "show",
        position = "left",
        source = "filesystem",
      })
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
      visible = true
      -- the session saved one tree window per tab, so a live tree goes back
      -- into every tab
      each_tab(function()
        require("neo-tree.command").execute({
          action = "show",
          position = "left",
          source = "filesystem",
        })
      end)
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

vim.keymap.set("n", "<leader>tt", M.toggle, { desc = "File tree" })
vim.keymap.set("n", "<leader>tf", M.focus, { desc = "Focus file tree" })

return M
