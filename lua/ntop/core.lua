local uv = vim.uv or vim.loop
local M = { _jobs = {}, _config = {}, _samples = {} }

-- Ensure we have a pagesize value available
local PAGE_SIZE = (function()
  if uv.getpagesize then return uv.getpagesize() end
  if os.getenv then
    local pagesize = tonumber(os.getenv("PAGESIZE")) or tonumber(os.getenv("PAGE_SIZE"))
    if pagesize then return pagesize end
  end
  return 4096 -- Common default page size
end)()

-- INTERNAL HELPERS ---------------------------------------------------
local function safe_lsp_get_clients()
  if not vim.lsp or not vim.lsp.get_clients then return {} end
  return vim.lsp.get_clients({}) or {}
end

local function build_process_tree(tasks)
  local tree = {}
  local children = {}

  -- First pass: organize parent-child relationships
  for _, task in ipairs(tasks) do
    if not children[task.pid] then
      children[task.pid] = {}
    end
    if task.ppid then
      children[task.ppid] = children[task.ppid] or {}
      table.insert(children[task.ppid], task)
    else
      table.insert(tree, task)
    end
  end

  -- Second pass: build hierarchical display
  local function add_children(parent, depth, result)
    for _, child in ipairs(children[parent.pid] or {}) do
      child._display_name = string.rep("  ", depth) .. "├─ " .. child.name
      table.insert(result, child)
      add_children(child, depth + 1, result)
    end
  end

  local result = {}
  for _, root in ipairs(tree) do
    root._display_name = root.name
    table.insert(result, root)
    add_children(root, 1, result)
  end

  return result
end

local function get_process_info(pid)
  if uv.os_uname().sysname == "Linux" then
    local stat = io.open("/proc/"..pid.."/stat")
    if not stat then return nil end

    local data = stat:read("*a")
    stat:close()

    local parts = {}
    for part in data:gmatch("%S+") do
      table.insert(parts, part)
    end

    if #parts < 24 then return nil end

    return {
      name = parts[2]:gsub("[%(%)]", ""),
      ppid = tonumber(parts[4]),
      state = parts[3],
      utime = tonumber(parts[14]),
      stime = tonumber(parts[15]),
      rss = tonumber(parts[24]) * 4096 -- pages to bytes
    }
  else
    local cmd = string.format("ps -o comm=,rss= -p %d", pid)
    local handle = io.popen(cmd)
    if not handle then return nil end

    local data = handle:read("*a")
    handle:close()

    local name, rss = data:match("(%S+)%s+(%d+)")
    if not name then return nil end

    return {
      name = name,
      rss = tonumber(rss) * 1024 -- KB to bytes
    }
  end
end

local function snapshot(pid)
  local info = get_process_info(pid)
  if not info then return 0, 0 end

  local now_ns = uv.hrtime()
  local cpu_time = (info.utime or 0) + (info.stime or 0)
  local rss_bytes = info.rss or 0

  local prev = M._samples[pid]
  local cpu_pct = 0

  if prev then
    local dt = (now_ns - prev.t) / 1e9
    -- Use system page size or fallback to 4096 (common page size)
    local page_size = uv.getpagesize and uv.getpagesize() or 4096
    local dcu = (cpu_time - prev.cpu) / page_size
    if dt > 0 then
      cpu_pct = (dcu / dt) * 100
    end
  end

  M._samples[pid] = { cpu = cpu_time, t = now_ns }
  return cpu_pct, rss_bytes
end

local function get_lsp_processes()
  local processes = {}

  for _, cli in pairs(safe_lsp_get_clients()) do
    local pid = cli.rpc and cli.rpc.pid
    if pid then
      local cpu, rss = snapshot(pid)
      table.insert(processes, {
        id = cli.id,
        type = "lsp",
        name = cli.name,
        pid = pid,
        root_dir = cli.config and cli.config.root_dir,
        cpu = cpu,
        mem = rss,
        created = uv.now()
      })
    end
  end

  if vim.fn and vim.fn.stdpath then
    local mason_packages = vim.fn.glob(vim.fn.stdpath("data").."/mason/packages/*", 0, 1)
    for _, pkg in ipairs(mason_packages or {}) do
      local pkg_name = vim.fn.fnamemodify(pkg, ":t")
      local cmd = string.format("pgrep -f %s", pkg_name)
      local handle = io.popen(cmd)
      if handle then
        for pid in handle:lines() do
          pid = tonumber(pid)
          if pid then
            local cpu, rss = snapshot(pid)
            table.insert(processes, {
              id = pid,
              type = "mason",
              name = pkg_name,
              pid = pid,
              cpu = cpu,
              mem = rss,
              created = uv.now()
            })
          end
        end
        handle:close()
      end
    end
  end

  return processes
end

function M.spawn(cmd, args, on_exit)
  local handle, pid
  local spawn_opts = {
    args = args,
    stdio = { nil, nil, nil },
    hide = true
  }

  -- Store current PID as parent if available
  local ppid = uv.getpid and uv.getpid() or nil

  -- Try new API first
  if uv.spawn then
    handle, pid = uv.spawn(cmd, spawn_opts, function(code, signal)
      if on_exit then pcall(on_exit, code, signal) end
      M._jobs[pid], M._samples[pid] = nil, nil
    end)
  end

  -- Fallback to old API if needed
  if not handle and vim.fn and vim.fn.jobstart then
    pid = vim.fn.jobstart(vim.tbl_flatten({cmd, args}), {
      on_exit = function(_, code, signal)
        if on_exit then pcall(on_exit, code, signal) end
        M._jobs[pid], M._samples[pid] = nil, nil
      end
    })
    if pid <= 0 then pid = nil end
  end

  if not pid then
    vim.notify("[ntop] Failed to spawn " .. cmd, vim.log.levels.ERROR)
    return nil
  end

  if pid then
    M._jobs[pid] = {
      handle = handle,
      cmd = table.concat(vim.tbl_flatten({cmd, args}), " "),
      created = uv.now(),
      ppid = ppid  -- Store parent PID for tree building
    }
  end

  return pid
end

function M.track_job(pid, cmd)
  if pid then
    M._jobs[pid] = {
      cmd = type(cmd) == "table" and table.concat(cmd, " ") or tostring(cmd),
      created = uv.now()
    }
  end
end

function M.list_tasks(filter_str)
  local tasks = {}

  -- 1. Collect all tasks (LSP, jobs, etc)
  vim.list_extend(tasks, get_lsp_processes())

  -- Add tracked jobs
  for pid, job in pairs(M._jobs) do
    local process_exists = false
    if job.handle and uv.process_kill then
      process_exists = uv.process_kill(job.handle, 0)
    else
      process_exists = uv.process_kill(pid, 0)
    end

    if process_exists then
      local cpu, rss = snapshot(pid)
      table.insert(tasks, {
        id = pid,
        type = "job",
        name = job.cmd,
        pid = pid,
        ppid = job.ppid, -- Make sure we store parent PID if available
        cpu = cpu,
        mem = rss,
        created = job.created
      })
    else
      M._jobs[pid] = nil
    end
  end

  -- 2. Build process tree hierarchy
  tasks = build_process_tree(tasks)

  -- 3. Apply filtering
  if filter_str and filter_str ~= "" then
    tasks = vim.tbl_filter(function(t)
      return require("ntop.task").matches(t, filter_str)
    end, tasks)
  end

  -- 4. Apply sorting
  local key = M._config.sort_by or "cpu"
  table.sort(tasks, function(a, b)
    if key == "cpu" or key == "mem" then
      return (a[key] or 0) > (b[key] or 0)
    elseif key == "name" then
      return (a._display_name or a.name or "") < (b._display_name or b.name or "")
    else
      return (a.id or 0) < (b.id or 0)
    end
  end)

  return tasks
end

function M.kill(pid, sig)
  sig = sig or "sigterm"
  local job = M._jobs[pid]

  -- Try different kill methods
  if job and job.handle and uv.process_kill then
    -- New API with process handle
    local ok, err = pcall(uv.process_kill, job.handle, sig)
    if ok then
      M._jobs[pid], M._samples[pid] = nil, nil
      return true
    end
  end

  -- Fallback methods
  if uv.process_kill then
    -- Try direct PID kill
    local ok, err = pcall(uv.process_kill, pid, sig)
    if ok then
      M._jobs[pid], M._samples[pid] = nil, nil
      return true
    end
  end

  -- Final fallback to system kill
  if os.execute("kill -"..sig.." "..pid) == 0 then
    M._jobs[pid], M._samples[pid] = nil, nil
    return true
  end

  return false
end

function M.confirm_and_kill(pid, sig)
  if vim.fn.confirm("Send " .. sig .. " to PID " .. pid .. "?", "&Yes\n&No", 2) == 1 then
    return M.kill(pid, sig)
  end
end

return M
