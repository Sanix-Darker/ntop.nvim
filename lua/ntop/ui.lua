local api  = vim.api
local uv   = vim.uv or vim.loop
local core = require("ntop.core")

-- Safe access to user config
local ok_conf, conf_mod = pcall(require, "ntop.config")
local function cfg()
  if not ok_conf then return {} end
  local o = conf_mod and conf_mod.opts
  if type(o) == "function" then
    local ok, res = pcall(o); return ok and res or {}
  end
  return type(o) == "table" and o or {}
end

-- Module state
local M = { _win = nil, _buf = nil, _timer = nil }

-- Helpers
local function human(bytes)
  if bytes > 1024 * 1024 then return string.format("%.1fM", bytes / 1024 / 1024) end
  if bytes > 1024        then return string.format("%.1fK", bytes / 1024)        end
  return tostring(bytes)
end

-- full-width header is rebuilt every refresh to match current `columns`
local function build_header(name_w)
  return string.format("%-3s %-6s %-6s %-7s %-6s %- "..name_w.."s",
    "No", "PID", "CPU%", "RSS", "TYPE", "NAME")
end

local function table_lines(tasks)
  local cols    = vim.o.columns
  local fixed_w = 4 + 7 + 7 + 8 + 7                   -- spaces + No/PID/CPU/RSS/TYPE columns
  local name_w  = math.max(10, cols - fixed_w - 1)    -- -1 for safety
  local head    = build_header(name_w)
  local lines   = { head, string.rep("─", #head) }

  for i, t in ipairs(tasks) do
    local line = string.format(
      "%-3d %-6s %-6.1f %-7s %-6s %- "..name_w.."s",
      i,
      t.pid or "-",
      t.cpu or 0,
      human(t.mem or 0),
      t.type or "-",
      (t.name or "?"):sub(1, name_w)
    )
    lines[#lines + 1] = line
  end
  return lines
end

local function chart_lines(tasks)
  if #tasks == 0 then return {} end
  local max_cpu   = 0
  for _, t in ipairs(tasks) do if t.cpu > max_cpu then max_cpu = t.cpu end end
  if max_cpu == 0 then max_cpu = 1 end                      -- avoid div/0

  local cols      = vim.o.columns
  local bar_w     = cols - 20                               -- leave space for label
  local lines     = { "", "CPU USAGE CHART" }

  for _, t in ipairs(tasks) do
    local pct     = math.min(t.cpu / max_cpu, 1)
    local len     = math.floor(pct * bar_w)
    local label   = string.format("%-6s %-6s", t.pid or "-", t.type or "-")
    lines[#lines + 1] = label .. " |" .. string.rep("#", len)
  end
  return lines
end

local function wipe()
  if M._timer then M._timer:stop(); M._timer:close(); M._timer = nil end
  if M._win and api.nvim_win_is_valid(M._win) then api.nvim_win_close(M._win, true) end
  if M._buf and api.nvim_buf_is_valid(M._buf) then api.nvim_buf_delete(M._buf, { force = true }) end
  M._win, M._buf = nil, nil
end

-- --------------------------------------------------------------------
-- Public API
-- --------------------------------------------------------------------
function M.refresh()
  if not (M._buf and api.nvim_buf_is_valid(M._buf)) then return end
  local tasks = core.list_tasks("")
  local lines = table_lines(tasks)
  vim.list_extend(lines, chart_lines(tasks))

  api.nvim_buf_set_option(M._buf, "modifiable", true)
  api.nvim_buf_set_lines(M._buf, 0, -1, false, lines)
  api.nvim_buf_set_option(M._buf, "modifiable", false)
end

function M.open()
  if M._win and api.nvim_win_is_valid(M._win) then api.nvim_set_current_win(M._win); M.refresh(); return end

  -- create scratch buffer
  M._buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_option(M._buf, "bufhidden", "wipe")
  api.nvim_buf_set_option(M._buf, "filetype", "ntop")

  -- full-width floating window
  local W, H = vim.o.columns, math.floor(vim.o.lines * 0.60)
  local row  = math.floor((vim.o.lines - H) / 2)

  M._win = api.nvim_open_win(M._buf, true, {
    relative = "editor",
    row      = row,
    col      = 0,
    width    = W,
    height   = H,
    style    = "minimal",
    border   = cfg().border or "single",
  })

  -- keymaps
  local function map(lhs, fn)
    api.nvim_buf_set_keymap(M._buf, "n", lhs, "", { noremap = true, silent = true, nowait = true, callback = fn })
  end
  map("q", wipe)
  map("r", M.refresh)
  map("k", function()
    local lnr = api.nvim_win_get_cursor(M._win)[1]
    if lnr <= 2 then return end
    local line = api.nvim_buf_get_lines(M._buf, lnr - 1, lnr, false)[1] or ""
    local pid  = tonumber(line:match("^%s*%d+%s+(%d+)"))
    if pid then
      core.confirm_and_kill(pid, cfg().default_signal or "sigterm")
      vim.defer_fn(M.refresh, 200)
    end
  end)

  M.refresh()

  local ms = tonumber(cfg().refresh_rate_ms) or 0
  if ms > 0 then
    M._timer = uv.new_timer()
    M._timer:start(ms, ms, vim.schedule_wrap(M.refresh))
  end
end

return M
