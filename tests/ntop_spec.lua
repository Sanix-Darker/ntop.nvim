local core = require("ntop.core")

describe("ntop metrics", function()
  it("collects cpu/mem fields", function()
    local tasks = core.list_tasks()
    for _, t in ipairs(tasks) do
      assert.is_not_nil(t.cpu)
      assert.is_not_nil(t.mem)
    end
  end)
end)
