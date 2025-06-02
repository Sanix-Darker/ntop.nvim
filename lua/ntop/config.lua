local M = {}

---@class ntop.Config
---@field default_signal string
---@field border string|table
---@field refresh_rate_ms integer
---@field sort_by string

M.defaults = {
  default_signal = "sigterm",
  border = "rounded",
  refresh_rate_ms = 1000,
  sort_by = "cpu",
}

return M
