local M = {}

---@private
local function contains(str, query)
	if not str then
		return false
	end
	return (str:lower():find(query, 1, true)) ~= nil
end

function M.matches(task, query)
	query = query:lower()
	return contains(task.name, query)
		or contains(task.type, query)
		or contains(task.root_dir, query)
		or contains(tostring(task.pid), query)
end

return M
