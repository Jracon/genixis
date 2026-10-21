require("blink.cmp").setup({
  completion = {
    documentation = { auto_show = true },
  },
  keymap = { preset = "default" }, -- Ctrl-y accept, Ctrl-n/p select, Ctrl-space open
  signature = { enabled = true },
})

-- format on save; add a filetype here alongside its formatter in neovim.nix
require("conform").setup({
  format_on_save = {
    lsp_format = "fallback",
    timeout_ms = 1000,
  },
  formatters_by_ft = {
    lua = { "stylua" },
    nix = { "nixfmt" },
  },
})

-- load the project's .envrc (direnv) so its tools are on nvim's PATH
require("direnv").setup({})

local fzf = require("fzf-lua")
fzf.setup({})
local map = vim.keymap.set
map("n", "<leader><leader>", fzf.buffers, { desc = "Buffers" })
map("n", "<leader>/", fzf.lgrep_curbuf, { desc = "Grep buffer" })
map("n", "<leader>fd", fzf.diagnostics_workspace, { desc = "Diagnostics" })
map("n", "<leader>ff", fzf.files, { desc = "Files" })
map("n", "<leader>fg", fzf.live_grep, { desc = "Grep" })
map("n", "<leader>fh", fzf.helptags, { desc = "Help" })
map("n", "<leader>fk", fzf.keymaps, { desc = "Keymaps" })
map("n", "<leader>fr", fzf.resume, { desc = "Resume last search" })

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
