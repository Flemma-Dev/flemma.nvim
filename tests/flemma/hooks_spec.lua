package.loaded["flemma.hooks"] = nil

local hooks

describe("flemma.hooks", function()
  ---@type integer[]
  local autocmd_ids = {}

  before_each(function()
    package.loaded["flemma.hooks"] = nil
    hooks = require("flemma.hooks")
    autocmd_ids = {}
  end)

  after_each(function()
    for _, id in ipairs(autocmd_ids) do
      pcall(vim.api.nvim_del_autocmd, id)
    end
  end)

  ---Register an autocmd and track it for cleanup
  ---@param pattern string
  ---@param callback function
  ---@return integer autocmd_id
  local function track_autocmd(pattern, callback)
    local id = vim.api.nvim_create_autocmd("User", {
      pattern = pattern,
      callback = callback,
    })
    autocmd_ids[#autocmd_ids + 1] = id
    return id
  end

  describe("name_to_pattern()", function()
    -- Access private function via the test helper exposed on M
    it("transforms single-word domain and action", function()
      assert.equals("FlemmaRequestSending", hooks._name_to_pattern("request:sending"))
    end)

    it("transforms hyphenated words", function()
      assert.equals("FlemmaRequestCancellingAll", hooks._name_to_pattern("request:cancelling-all"))
    end)

    it("transforms multi-segment names", function()
      assert.equals("FlemmaBootComplete", hooks._name_to_pattern("boot:complete"))
      assert.equals("FlemmaSinkCreated", hooks._name_to_pattern("sink:created"))
      assert.equals("FlemmaToolFinished", hooks._name_to_pattern("tool:finished"))
    end)
  end)

  describe("dispatch()", function()
    it("fires User autocmd with correct pattern and data", function()
      local received = nil
      track_autocmd("FlemmaRequestSending", function(ev)
        received = ev
      end)

      hooks.dispatch("request:sending", { bufnr = 42 })

      assert.is_not_nil(received)
      assert.equals(42, received.data.bufnr)
    end)

    it("passes empty table when data is nil", function()
      local received = nil
      track_autocmd("FlemmaBootComplete", function(ev)
        received = ev
      end)

      hooks.dispatch("boot:complete")

      assert.is_not_nil(received)
      assert.are.same({}, received.data)
    end)

    it("does not propagate errors from handlers", function()
      track_autocmd("FlemmaSinkCreated", function()
        error("handler exploded")
      end)

      -- Should not throw
      assert.has_no.errors(function()
        hooks.dispatch("sink:created", { bufnr = 1, name = "test" })
      end)
    end)

    it("continues to fire autocmds after a handler error", function()
      local error_id = track_autocmd("FlemmaToolExecuting", function()
        error("boom")
      end)

      -- First dispatch triggers error (silently)
      hooks.dispatch("tool:executing", { bufnr = 1, tool_name = "read", tool_id = "t1" })

      vim.api.nvim_del_autocmd(error_id)

      -- Second dispatch should work fine
      local received = nil
      track_autocmd("FlemmaToolExecuting", function(ev)
        received = ev
      end)

      hooks.dispatch("tool:executing", { bufnr = 2, tool_name = "write", tool_id = "t2" })
      assert.is_not_nil(received)
      assert.equals(2, received.data.bufnr)
    end)
  end)
end)
