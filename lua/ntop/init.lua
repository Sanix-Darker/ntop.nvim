local cfg = require("ntop.config").defaults
local core = require("ntop.core")
local ui = require("ntop.ui")
local M = { config = vim.deepcopy(cfg) }

---Setup ntop.nvim
---@param opts table|nil
function M.setup(opts)
	if opts then
		M.config = vim.tbl_deep_extend("force", vim.deepcopy(cfg), opts)
	end

	-- expose config to sub‑modules
	ui._config = M.config
	core._config = M.config

	-- Wrap vim.fn.jobstart so jobs created elsewhere are tracked automatically
	if not vim.fn.ntop_jobstart_wrapped then
		vim.fn.ntop_jobstart_wrapped = true
		local jobstart = vim.fn.jobstart
		vim.fn.jobstart = function(cmd, opts)
			local id = jobstart(cmd, opts)
			if id and id > 0 then
				core.track_job(id, cmd)
			end
			return id
		end
	end

	vim.api.nvim_create_user_command("Ntop", function()
		ui.open()
	end, { desc = "Open ntop.nvim task manager" })

	vim.api.nvim_create_user_command("NtopKill", function(cmd)
		local pid = tonumber(vim.trim(cmd.fargs[1] or ""))
		if not pid then
			vim.notify("[ntop] Provide a PID", vim.log.levels.WARN)
			return
		end
		core.confirm_and_kill(pid, M.config.default_signal)
	end, {
		desc = "Kill a task by PID (with confirmation)",
		nargs = "?", -- should be 1
		complete = function()
			local l = {}
			for _, t in ipairs(core.list_tasks()) do
				if t.pid then
					table.insert(l, tostring(t.pid))
				end
			end
			return l
		end,
	})

	vim.api.nvim_create_user_command("NtopSignal", function(cmd)
		local sig = cmd.fargs[1]
		local pid = tonumber(cmd.fargs[2])
		if not sig or not pid then
			vim.notify("Usage: NtopSignal <signal> <pid>", vim.log.levels.WARN)
			return
		end
		core.confirm_and_kill(pid, sig)
	end, {
		desc = "Send an arbitrary signal to PID",
		nargs = "?", -- should be 2
		complete = function(_, line)
			local parts = vim.split(line, " ")
			if #parts == 2 then
				return { "sigterm", "sigkill", "sigint", "sigstop", "sigcont" }
			else
				return {}
			end
		end,
	})
end

return M
