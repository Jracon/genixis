-- nvim-dap debugs a program through the debug adapter protocol. nvim-dap-go wires Go to
-- delve, which extraPackages of neovim.nix and the devShell of this repository install, and
-- nvim-dap-ui opens the variable, call stack, and REPL views around the debugged buffer. A
-- file outside a Go checkout holds no debug configuration, so the keys report that
local dap = require("dap")
local dapui = require("dapui")

require("dap-go").setup({})
dapui.setup({})

-- the views follow the session: they open once the program stops and close when it ends
dap.listeners.after.event_initialized["dapui_config"] = function()
  dapui.open()
end
dap.listeners.before.event_terminated["dapui_config"] = function()
  dapui.close()
end
dap.listeners.before.event_exited["dapui_config"] = function()
  dapui.close()
end

local map = vim.keymap.set
map("n", "<leader>Db", dap.toggle_breakpoint, { desc = "Breakpoint" })
map("n", "<leader>Dc", dap.continue, { desc = "Continue or start" })
map("n", "<leader>Di", dap.step_into, { desc = "Step into" })
map("n", "<leader>DO", dap.step_out, { desc = "Step out" })
map("n", "<leader>Do", dap.step_over, { desc = "Step over" })
map("n", "<leader>Dt", dapui.toggle, { desc = "Debug UI" })
