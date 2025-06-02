local api = vim.api
local uv = vim.uv or vim.loop
local core = require("ntop.core")
local config = require("ntop.config")

-- Module state
local M = {
  _win = nil,
  _buf = nil,
  _timer = nil,
  state = {
    filter = "",
    sort_by = "cpu",
    max_chart_items = 10
  }
}

-- Helpers
local function human(bytes)
  if bytes > 1024 * 1024 then return string.format("%.1f MB", bytes / (1024 * 1024)) end
  if bytes > 1024 then return string.format("%.1f KB", bytes / 1024) end
  return string.format("%d B", bytes)
end

local function build_header(name_w)
  return string.format("%-3s %-6s %-6s %-9s %-6s %-"..name_w.."s",
    "ID", "PID", "CPU%", "MEM", "TYPE", "NAME")
end

local function table_lines(tasks)
  local cols = math.min(120, vim.o.columns)
  local fixed_w = 3 + 6 + 6 + 9 + 6 + 5
  local name_w = math.max(10, cols - fixed_w)
  local head = build_header(name_w)
  local lines = { head, string.rep("─", #head) }

  for i, t in ipairs(tasks) do
    local line = string.format(
      "%-3d %-6d %-6.1f %-9s %-6s %-"..name_w.."s",
      i,
      t.pid,
      t.cpu,
      human(t.mem),
      t.type:sub(1, 6),
      (t.name or "unknown"):sub(1, name_w)
    )
    lines[#lines + 1] = line
  end
  return lines
end

local function chart_lines(tasks)
  if #tasks == 0 then return {} end
  local max_cpu = 0
  for _, t in ipairs(tasks) do
    if t.cpu > max_cpu then max_cpu = t.cpu end
  end
  if max_cpu == 0 then max_cpu = 1 end

  local cols = math.min(120, vim.o.columns)
  local bar_w = math.max(10, cols - 25)
  local lines = { "", "CPU USAGE (Top " .. M.state.max_chart_items .. ")" }

  for i = 1, math.min(M.state.max_chart_items, #tasks) do
    local t = tasks[i]
    local pct = t.cpu / max_cpu
    local len = math.floor(pct * bar_w)
    local label = string.format("%-6d %-6s", t.pid, t.type:sub(1, 6))
    lines[#lines + 1] = label .. " |" .. string.rep("█", len) ..
                         string.format(" %.1f%%", t.cpu)
  end
  return lines
end

local function wipe()
  if M._timer then
    M._timer:stop()
    M._timer:close()
    M._timer = nil
  end
  if M._win and api.nvim_win_is_valid(M._win) then
    api.nvim_win_close(M._win, true)
  end
  if M._buf and api.nvim_buf_is_valid(M._buf) then
    api.nvim_buf_delete(M._buf, { force = true })
  end
  M._win, M._buf = nil, nil
end

-- Public API ---------------------------------------------------------
function M.refresh()
  if not (M._buf and api.nvim_buf_is_valid(M._buf)) then return end

  local tasks = core.list_tasks(M.state.filter)
  local lines = {}
  vim.list_extend(lines, table_lines(tasks))
  vim.list_extend(lines, chart_lines(tasks))

  -- Ensure we have at least one line to prevent cursor errors
  if #lines == 0 then
    lines = { "No tasks found" }
  end

  api.nvim_buf_set_option(M._buf, "modifiable", true)
  api.nvim_buf_set_lines(M._buf, 0, -1, false, lines)

  -- Only set cursor if we have content and window is valid
  if #lines > 0 and M._win and api.nvim_win_is_valid(M._win) then
    local cursor_line = math.min(3, #lines) -- Default to line 3 (after header) or last line
    api.nvim_win_set_cursor(M._win, {cursor_line, 0})
  end

  api.nvim_buf_set_option(M._buf, "modifiable", false)
end

function M.open()
  if M._win and api.nvim_win_is_valid(M._win) then
    api.nvim_set_current_win(M._win)
    M.refresh()
    return
  end

  -- Create buffer
  M._buf = api.nvim_create_buf(false, true)
  -- for safer measures
  if not M._buf or not api.nvim_buf_is_valid(M._buf) then
    vim.notify("Failed to create ntop buffer", vim.log.levels.ERROR)
    return
  end

  api.nvim_buf_set_name(M._buf, "ntop-dashboard")
  api.nvim_buf_set_option(M._buf, "bufhidden", "wipe")
  api.nvim_buf_set_option(M._buf, "filetype", "ntop")
  api.nvim_buf_set_option(M._buf, "modifiable", false)

  -- Create window
  local width = math.min(120, vim.o.columns - 4)
  local height = math.min(50, vim.o.lines - 4)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  M._win = api.nvim_open_win(M._buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = config.defaults.border,
  })

  -- Key mappings
  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, {
      buffer = M._buf,
      nowait = true,
      silent = true,
      desc = desc
    })
  end

  map("q", wipe, "Close window")
  map("r", M.refresh, "Refresh now")
  map("s", function()
    local sort_cycle = { "cpu", "mem", "id", "name" }
    local current = core._config.sort_by or "cpu"
    local next_index = (vim.tbl_keys(sort_cycle)[current] % #sort_cycle + 1)
    core._config.sort_by = sort_cycle[next_index]
    M.refresh()
  end, "Cycle sort")

  map("/", function()
    vim.ui.input({ prompt = "Filter: " }, function(input)
      if input then
        M.state.filter = input:lower()
        M.refresh()
      end
    end)
  end, "Set filter")

  map("k", function()
    vim.ui.input({ prompt = "PID to kill: " }, function(input)
      if input then
        local pid = tonumber(input)
        if pid then
          core.confirm_and_kill(pid, config.defaults.default_signal)
          vim.defer_fn(M.refresh, 200)
        end
      end
    end)
  end, "Kill task")

  -- Initial render
  M.refresh()

  -- Auto-refresh timer
  local ms = config.defaults.refresh_rate_ms
  if ms > 0 then
    M._timer = uv.new_timer()
    M._timer:start(ms, ms, vim.schedule_wrap(M.refresh))
  end
end

return M
