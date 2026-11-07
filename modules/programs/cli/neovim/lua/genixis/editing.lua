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
    timeout_ms = 1000,
  },
  formatters_by_ft = {
    -- go has no entry: the lsp_format fallback makes gopls format Go files
    lua = { "stylua" },
    nix = { "nixfmt" },
    python = { "ruff_format" },
  },
})

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
-- Ctrl+Shift+F finds files by name (issue #165). Inside tmux the chord reaches an nvim
-- pane as M-F: tmux.nix rewrites it, because a pane cannot read Shift on a control key
-- without the kitty protocol (the Shift+Enter row of docs/keymap.md shows the same limit).
-- A pane without tmux delivers the chord as C-S-f, so both maps open the same picker
map("n", "<C-S-f>", fzf.files, { desc = "Files" })
map("n", "<M-F>", fzf.files, { desc = "Files" })
map("n", "<leader>fd", fzf.diagnostics_workspace, { desc = "Diagnostics" })
map("n", "<leader>ff", fzf.files, { desc = "Files" })
map("n", "<leader>fg", fzf.live_grep, { desc = "Grep" })
map("n", "<leader>fh", fzf.helptags, { desc = "Help" })
map("n", "<leader>fk", fzf.keymaps, { desc = "Keymaps" })
map("n", "<leader>fr", fzf.resume, { desc = "Resume last search" })
map("n", "<leader>fs", fzf.lsp_workspace_symbols, { desc = "Workspace symbols" })

-- project-wide find and replace; the buffer previews every match, and only the replace
-- actions write files. One named instance: a second call focuses the open search
require("grug-far").setup({})
map("n", "<leader>fa", function()
  require("grug-far").open({ instanceName = "project" })
end, { desc = "Find and replace" })

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
