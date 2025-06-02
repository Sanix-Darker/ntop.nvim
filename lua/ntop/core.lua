local uv = vim.uv or vim.loop
local M = { _jobs = {}, _config = {}, _samples = {} }

-- INTERNAL HELPERS ---------------------------------------------------
local HAVE_PROC_INFO = type(uv.proc_info) == "function"

---@return number cpu_percent, integer rss_bytes
local function snapshot(pid)
	if not HAVE_PROC_INFO then
		return 0, 0
	end
	local info = uv.proc_info(pid)
	if not info then
		return 0, 0
	end

	-- libuv returns micro-seconds for user+system time
	local cpu_time = (info.user or 0) + (info.system or 0) -- µs
	local rss_bytes = info.rss or 0

	local now_ns = uv.hrtime() -- ns
	local prev = M._samples[pid]

	local cpu_pct = 0
	if prev then
		local dt = (now_ns - prev.t) / 1e9 -- to seconds
		local dcu = (cpu_time - prev.cpu) / 1e6 -- to seconds
		if dt > 0 then
			cpu_pct = (dcu / dt) * 100
		end -- percentage
	end

	M._samples[pid] = { cpu = cpu_time, t = now_ns }
	return cpu_pct, rss_bytes
end

-- PUBLIC API ---------------------------------------------------------

function M.spawn(cmd, args, on_exit)
	if uv.spawn then
		local handle, pid = uv.spawn(cmd, { args = args, stdio = { nil, nil, nil } }, function(c, s)
			if on_exit then
				pcall(on_exit, c, s)
			end
			M._jobs[pid], M._samples[pid] = nil, nil
		end)
		assert(handle, "[ntop] Failed to spawn " .. cmd)
		M._jobs[pid] = {
			handle = handle,
			cmd = type(cmd) == "table" and table.concat(cmd, " ") or cmd,
		}
		return pid
	else
		local id = vim.fn.jobstart(type(cmd) == "table" and cmd or { cmd }, {
			on_exit = function(_, c, s)
				if on_exit then
					pcall(on_exit, c, s)
				end
				M._jobs[id], M._samples[id] = nil, nil
			end,
		})
		assert(id > 0, "[ntop] jobstart failed for " .. cmd)
		M._jobs[id] = { cmd = type(cmd) == "table" and table.concat(cmd, " ") or cmd }
		return id
	end
end

function M.track_job(pid, cmd)
	if pid then
		M._jobs[pid] = { cmd = type(cmd) == "table" and table.concat(cmd, " ") or tostring(cmd) }
	end
end

function M.list_tasks(filter)
	local tasks = {}

	-- LSP clients
	for _, cli in pairs(vim.lsp.get_clients({})) do
		local pid = cli.rpc and cli.rpc.pid
		local cpu, rss = pid and snapshot(pid) or 0, pid and snapshot(pid) or 0
		table.insert(tasks, {
			id = cli.id,
			type = "lsp",
			name = cli.name,
			pid = pid,
			root_dir = cli.config.root_dir,
			cpu = cpu,
			mem = rss,
		})
	end

	-- Tracked jobs
	for pid, job in pairs(M._jobs) do
		local cpu, rss = snapshot(pid)
		table.insert(tasks, {
			id = pid,
			type = "job",
			name = job.cmd,
			pid = pid,
			cpu = cpu,
			mem = rss,
		})
	end

	-- Filter
	if filter and #filter > 0 then
		local match = require("ntop.task").matches
		local out = {}
		for _, t in ipairs(tasks) do
			if match(t, filter) then
				out[#out + 1] = t
			end
		end
		tasks = out
	end

	-- Sort
	local key = M._config.sort_by or "cpu"
	table.sort(tasks, function(a, b)
		if key == "cpu" or key == "mem" then
			return (a[key] or 0) > (b[key] or 0)
		elseif key == "name" then
			return (a.name or "") < (b.name or "")
		else
			return (a.id or 0) < (b.id or 0)
		end
	end)
	return tasks
end

function M.kill(pid, sig)
	sig = sig or "sigterm"
	local ok = (uv.kill and uv.kill(pid, sig) == 0) or vim.fn.jobstop(pid) == 1
	if ok then
		M._jobs[pid], M._samples[pid] = nil, nil
	end
	return ok
end

function M.confirm_and_kill(pid, sig)
	if vim.fn.confirm("Send " .. sig .. " to PID " .. pid .. "?", "&Yes\n&No", 2) == 1 then
		return M.kill(pid, sig)
	end
end

return M
