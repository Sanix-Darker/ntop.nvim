-- Minimal init.lua for CI & local test runs
vim.opt.runtimepath:append(vim.fn.getcwd())

-- Mock uv if needed
if not vim.uv then
  vim.uv = vim.loop or {}
end

-- Mock process_kill if needed
if not vim.uv.process_kill then
  vim.uv.process_kill = function(pid_or_handle, sig)
    if type(pid_or_handle) == "number" then
      return os.execute("kill -" .. (sig or "TERM") .. " " .. pid_or_handle) == 0
    end
    return false
  end
end

require("ntop").setup({
  refresh_rate_ms = 0, -- disable auto timer during tests
})
