describe("tools.store", function()
  local store

  before_each(function()
    package.loaded["flemma.tools.store"] = nil
    store = require("flemma.tools.store")
  end)

  describe("escape_id", function()
    it("passes through alphanumeric IDs", function()
      assert.equals("bash_1", store.escape_id("bash_1"))
    end)

    it("escapes colon to double dash", function()
      assert.equals("bash--8", store.escape_id("bash:8"))
    end)

    it("preserves dots, dashes, underscores", function()
      assert.equals("my_tool.v2-beta", store.escape_id("my_tool.v2-beta"))
    end)

    it("preserves double underscore from wire encoding", function()
      assert.equals("flemma__jobs__status--20", store.escape_id("flemma__jobs__status:20"))
    end)

    it("escapes multiple hostile characters", function()
      assert.equals("tool--a--b", store.escape_id("tool:a:b"))
    end)

    it("escapes spaces", function()
      assert.equals("has--space", store.escape_id("has space"))
    end)

    it("escapes slashes", function()
      assert.equals("path--to--thing", store.escape_id("path/to/thing"))
    end)
  end)

  describe("collapse_namespace", function()
    it("collapses .flemma/flemma/ to .flemma/", function()
      assert.equals("/home/user/.flemma/store/x", store.collapse_namespace("/home/user/.flemma/flemma/store/x"))
    end)

    it("collapses flemma/flemma/ to flemma/", function()
      assert.equals("/opt/flemma/store/x", store.collapse_namespace("/opt/flemma/flemma/store/x"))
    end)

    it("collapses repeated flemma segments to fixed point", function()
      assert.equals("/opt/flemma/x", store.collapse_namespace("/opt/flemma/flemma/flemma/x"))
    end)

    it("does not collapse myflemma/flemma/", function()
      assert.equals("/opt/myflemma/flemma/x", store.collapse_namespace("/opt/myflemma/flemma/x"))
    end)

    it("does not collapse flemma/flemma-lab/", function()
      assert.equals("/opt/flemma/flemma-lab/x", store.collapse_namespace("/opt/flemma/flemma-lab/x"))
    end)

    it("handles paths without flemma segments", function()
      assert.equals("/home/user/docs/file.txt", store.collapse_namespace("/home/user/docs/file.txt"))
    end)

    it("handles .flemma/flemma/flemma/ triple", function()
      assert.equals("/home/.flemma/x", store.collapse_namespace("/home/.flemma/flemma/flemma/x"))
    end)
  end)
end)
