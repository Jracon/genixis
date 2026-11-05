-- neotest runs the test under the cursor and marks pass and fail in the sign column, which
-- options.lua keeps always on. The adapter holds back where go is not on PATH, so a file
-- outside a Go checkout simply has no tests
local neotest = require("neotest")
neotest.setup({
  adapters = {
    require("neotest-golang")({
      -- the upstream default go_test_args also passes -race, which needs a C compiler; the
      -- devShell of this repository holds none. -count=1 stays, so a re-run of a passing
      -- test is not served from the go test cache
      go_test_args = { "-v", "-count=1" },
    }),
  },
  status = { signs = true },
})

local map = vim.keymap.set
map("n", "<leader>rf", function()
  neotest.run.run(vim.fn.expand("%"))
end, { desc = "Run test file" })
map("n", "<leader>rl", function()
  neotest.run.run_last()
end, { desc = "Run last test" })
map("n", "<leader>ro", function()
  neotest.output.open({ enter = true })
end, { desc = "Test output" })
map("n", "<leader>rr", function()
  neotest.run.run()
end, { desc = "Run nearest test" })
map("n", "<leader>rs", function()
  neotest.summary.toggle()
end, { desc = "Test summary" })
map("n", "<leader>rx", function()
  neotest.run.stop()
end, { desc = "Stop nearest test" })
