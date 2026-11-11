require("blink.cmp").setup({
  completion = {
    documentation = { auto_show = true },
  },
  keymap = { preset = "default" }, -- Ctrl-y accept, Ctrl-n/p select, Ctrl-space open
  signature = { enabled = true },
  snippets = { preset = "luasnip" }, -- luasnip expands; its jump commands come with the preset
})

-- the snippet set of friendly-snippets, loaded per filetype
require("luasnip.loaders.from_vscode").lazy_load()

-- brackets and quotes close as their opener is typed; blink.cmp keeps its own keys, and its
-- bracket insertion after an accepted function stays beside it
require("nvim-autopairs").setup({})

-- format on save; add a filetype here alongside its formatter in neovim.nix
require("conform").setup({
  format_on_save = {
    lsp_format = "fallback",
    -- the wait of one slow formatter caps at a quarter second (issue #193): a save that a
    -- close triggers (the Yes of its dialog), and every plain write, then never stalls a
    -- full second on a busy server. The formatters here answer in 10-40 ms when warm, so
    -- the cap only ever hits a server that is busy or cold
    timeout_ms = 250,
  },
  formatters_by_ft = {
    -- go has no entry: the lsp_format fallback makes gopls format Go files
    lua = { "stylua" },
    nix = { "nixfmt" },
    python = { "ruff_format" },
  },
})

-- :Format formats the file now (issue #195): the same formatters as the save, with the language
-- server as the fallback. The command palette of Ctrl+Shift+P below lists it, so it has its key
vim.api.nvim_create_user_command("Format", function()
  require("conform").format({ async = true, lsp_format = "fallback" })
end, { desc = "Format the file now" })

-- load the project's .envrc (direnv) so its tools are on nvim's PATH
require("direnv").setup({})

local fzf = require("fzf-lua")
fzf.setup({})
local map = vim.keymap.set
map("n", "<leader><leader>", fzf.buffers, { desc = "Buffers" })
-- Ctrl+F searches the open file (issue #165): a Tool-layer chord of nvim only, which takes
-- the place of the former leader-grep of the buffer and shadows the nvim default that
-- pages one screen forward (Ctrl+B pages back); fish keeps its Ctrl+F forward-char
map("n", "<C-f>", fzf.lgrep_curbuf, { desc = "Search in the open file" })
-- Ctrl+Shift+F searches the contents of all files in the working directory (issue #193),
-- the same picker as <leader>fg. Inside tmux the chord reaches an nvim pane as M-F:
-- tmux.nix rewrites it, because a pane cannot read Shift on a control key without the
-- kitty protocol (the Shift+Enter row of docs/keymap.md shows the same limit). A pane
-- without tmux delivers the chord as C-S-f, so both maps open the same picker. Finding
-- files by name stays on <leader>ff and in yazi
map("n", "<C-S-f>", fzf.live_grep, { desc = "Grep" })
map("n", "<M-F>", fzf.live_grep, { desc = "Grep" })
map("n", "<leader>fd", fzf.diagnostics_workspace, { desc = "Diagnostics" })
map("n", "<leader>ff", fzf.files, { desc = "Files" })
map("n", "<leader>fg", fzf.live_grep, { desc = "Grep" })
map("n", "<leader>fh", fzf.helptags, { desc = "Help" })
map("n", "<leader>fk", fzf.keymaps, { desc = "Keymaps" })
map("n", "<leader>fr", fzf.resume, { desc = "Resume last search" })
-- the live variant: gopls answers null for the empty query, so the plain picker closes
-- at once; this one queries the server on each keystroke and stays open (issue #299)
map("n", "<leader>fs", fzf.lsp_live_workspace_symbols, { desc = "Workspace symbols" })

-- project-wide find and replace; the buffer previews every match, and only the replace
-- actions write files. One named instance per window: a second call focuses the open search
require("grug-far").setup({})
map("n", "<leader>fa", function()
  require("grug-far").open({ instanceName = "project" })
end, { desc = "Find and replace" })
-- Ctrl+Shift+H replaces in the open file (issue #195): the current file is the only path of the
-- search, so the window lists its matches alone. The IDE replace key is Ctrl+H, which a terminal
-- sends as Backspace, so the chord takes Shift. Inside tmux a pane cannot read Shift on a control
-- key, so tmux rewrites the chord to M-H as it rewrites Ctrl+Shift+F (tmux.nix); the M-H map
-- serves that rewrite, the C-S-h map a pane without tmux. One instance per file: a second call
-- in the same file focuses its window, and another file opens its own
local replace_in_file = function()
  require("grug-far").open({
    instanceName = vim.fn.expand("%:p"),
    prefills = { paths = vim.fn.expand("%:p") },
  })
end
map("n", "<C-S-h>", replace_in_file, { desc = "Replace in the open file" })
map("n", "<M-H>", replace_in_file, { desc = "Replace in the open file" })

-- the command palette of Ctrl+Shift+P (issue #195): the fzf-lua picker of the Ex commands, on
-- the palette key of the IDE editors. WezTerm binds its own Ctrl+Shift+P to its palette, so
-- wezterm.nix disables the default; inside tmux the pane reads M-P, the rewrite of tmux.nix,
-- and the C-S-p map serves a pane without tmux
map("n", "<C-S-p>", fzf.commands, { desc = "Command palette" })
map("n", "<M-P>", fzf.commands, { desc = "Command palette" })

-- yazi in a floating window; picked files open as buffers (several go to the quickfix list)
require("yazi").setup({
  open_for_directories = true, -- `nvim some/dir` opens yazi instead of netrw
})
map("n", "<leader>e", "<cmd>Yazi<CR>", { desc = "Yazi at current file" })
map("n", "<leader>E", "<cmd>Yazi cwd<CR>", { desc = "Yazi at working directory" })

local gitsigns = require("gitsigns")
gitsigns.setup({
  on_attach = function(buf)
    local function bmap(lhs, rhs, desc)
      map("n", lhs, rhs, { buffer = buf, desc = desc })
    end
    bmap("]h", function()
      gitsigns.nav_hunk("next")
    end, "Next hunk")
    bmap("[h", function()
      gitsigns.nav_hunk("prev")
    end, "Previous hunk")
    bmap("<leader>hb", gitsigns.blame_line, "Blame line")
    bmap("<leader>hp", gitsigns.preview_hunk, "Preview hunk")
    bmap("<leader>hr", gitsigns.reset_hunk, "Reset hunk")
    bmap("<leader>hs", gitsigns.stage_hunk, "Stage hunk")
  end,
})
