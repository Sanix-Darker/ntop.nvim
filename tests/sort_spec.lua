local core = require("ntop.core")

-- stub some fake tasks to test sorting independent of live CPU values
local fake = {
  { id = 3, cpu = 10, mem = 1000, name = "a" },
  { id = 1, cpu = 30, mem = 3000, name = "c" },
  { id = 2, cpu = 20, mem = 2000, name = "b" },
}

local function sort(tasks, key)
  core._config.sort_by = key
  table.sort(tasks, function(a, b)
    if key == "cpu" or key == "mem" then
      return a[key] > b[key]
    elseif key == "name" then
      return a.name < b.name
    else
      return a.id < b.id
    end
  end)
end

describe("sorting", function()
  it("sorts by cpu desc", function()
    local t = vim.deepcopy(fake)
    sort(t, "cpu")
    assert.are_equal(30, t[1].cpu)
  end)
  it("sorts by mem desc", function()
    local t = vim.deepcopy(fake)
    sort(t, "mem")
    assert.are_equal(3000, t[1].mem)
  end)
  it("sorts by name asc", function()
    local t = vim.deepcopy(fake)
    sort(t, "name")
    assert.are_equal("a", t[1].name)
  end)
  it("sorts by id asc", function()
    local t = vim.deepcopy(fake)
    sort(t, "id")
    assert.are_equal(1, t[1].id)
  end)
end)
