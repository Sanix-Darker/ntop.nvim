local core = require("ntop.core")

describe("metrics", function()
  it("attach cpu/mem fields to each task", function()
    for _, t in ipairs(core.list_tasks()) do
      assert.is_not_nil(t.cpu)
      assert.is_not_nil(t.mem)
    end
  end)
end)
