---Default configuration, exported for type‑hinting and reuse
local M = {}

---@class ntop.Config
---@field default_signal string      Default signal when killing tasks
---@field border string|table        Border style for the floating UI
---@field refresh_rate_ms integer    Auto‑refresh interval (0 disables)
---@field sort_by "id"|"cpu"|"mem"|"name" Default sort key (may change later)
M.defaults = {
	default_signal = "sigterm",
	border = "rounded",
	refresh_rate_ms = 1000,
	sort_by = "cpu", -- maybe mem is more relevant... will see
}

return M
