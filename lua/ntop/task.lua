local M = {}

function M.matches(task, query)
  query = query:lower()
  local fields = {
    tostring(task.pid),
    task.name,
    task.type,
    task.root_dir
  }

  for _, field in ipairs(fields) do
    if field and field:lower():find(query, 1, true) then
      return true
    end
  end
  return false
end

return M
