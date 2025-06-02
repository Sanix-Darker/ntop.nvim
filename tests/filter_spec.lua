local match = require("ntop.task").matches

describe("filtering", function()
  it("matches name, type, root_dir and pid", function()
    local t = { name = "pyright", type = "lsp", root_dir = "/tmp/proj", pid = 4242 }
    assert.is_true(match(t, "pyr"))
    assert.is_true(match(t, "lsp"))
    assert.is_true(match(t, "/tmp"))
    assert.is_true(match(t, "4242"))
    assert.is_false(match(t, "random"))
  end)
end)
