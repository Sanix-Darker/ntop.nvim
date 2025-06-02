local config = require("ntop.config")
local ok, core = pcall(require, "ntop.core")
if not ok then
  vim.notify("Failed to load ntop.core: " .. tostring(core), vim.log.levels.ERROR)
  return { setup = function() end } -- Return dummy module
end

local ok_ui, ui = pcall(require, "ntop.ui")
if not ok_ui then
  vim.notify("Failed to load ntop.ui: " .. tostring(ui), vim.log.levels.ERROR)
  return { setup = function() end } -- Return dummy module
end

local M = {
  config = vim.deepcopy(config.defaults),
  _initialized = false
}

function M.setup(opts)
  if M._initialized then return end
  M._initialized = true

  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  ui.state = ui.state or {}
  ui.state.sort_by = M.config.sort_by
  core._config = M.config

  vim.api.nvim_create_user_command("Ntop", function()
    ui.open()
  end, { desc = "Open ntop task manager" })

  vim.api.nvim_create_user_command("NtopKill", function(ctx)
    local pid = tonumber(ctx.args)
    if pid then
      core.confirm_and_kill(pid, M.config.default_signal)
    else
      vim.notify("Invalid PID: " .. ctx.args, vim.log.levels.ERROR)
    end
  end, {
    desc = "Kill process by PID",
    nargs = 1,
    complete = function()
      local pids = {}
      for _, t in ipairs(core.list_tasks()) do
        table.insert(pids, tostring(t.pid))
      end
      return pids
    end
  })

  vim.api.nvim_create_user_command("NtopSignal", function(ctx)
    local parts = vim.split(ctx.args, "%s+")
    if #parts < 2 then
      vim.notify("Usage: NtopSignal <signal> <pid>", vim.log.levels.ERROR)
      return
    end
    core.confirm_and_kill(tonumber(parts[2]), parts[1])
  end, {
    desc = "Send signal to process",
    nargs = "+",
    complete = function(_, line)
      local parts = vim.split(line, "%s+")
      if #parts == 1 then
        return { "SIGTERM", "SIGKILL", "SIGINT", "SIGSTOP", "SIGCONT" }
      end
    end
  })
end

return M
