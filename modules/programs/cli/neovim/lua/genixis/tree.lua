-- the file tree of the editor pane (issue #196): neo-tree in a left split, with
-- git status at the right of each row and the keys of the leader-t group
local M = {}

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
        mappings = {
          ["<cr>"] = M.open_node,
          ["h"] = "close_node",
          ["l"] = M.open_node,
          ["q"] = "close_window",
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

-- hides and shows the tree of the current tab
M.toggle = function()
  require("neo-tree.command").execute({
    action = "focus",
    position = "left",
    source = "filesystem",
    toggle = true,
  })
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

-- the tree window is not a file: the close-file keys close the tree there
local function close_tree()
  if vim.bo.filetype == "neo-tree" then
    pcall(vim.cmd, "close")
  end
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "neo-tree",
  callback = function(args)
    vim.keymap.set("n", "<C-w>", close_tree, { buffer = args.buf, desc = "Close the tree" })
    vim.keymap.set("n", "<leader>x", close_tree, { buffer = args.buf, desc = "Close the tree" })
  end,
})

-- a bare start opens the tree, as the yazi pane was there from the start; a
-- start with files keeps the full width for them
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    if vim.fn.argc() == 0 then
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
      require("neo-tree.command").execute({
        action = "show",
        position = "left",
        source = "filesystem",
      })
    end
  end,
})

setup()

vim.keymap.set("n", "<leader>tt", M.toggle, { desc = "File tree" })
vim.keymap.set("n", "<leader>tf", M.focus, { desc = "Focus file tree" })

return M
