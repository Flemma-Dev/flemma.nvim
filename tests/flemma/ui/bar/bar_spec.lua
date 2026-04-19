describe("flemma.ui.bar", function()
  local Bar

  before_each(function()
    package.loaded["flemma.ui.bar"] = nil
    package.loaded["flemma.ui.bar.layout"] = nil
    Bar = require("flemma.ui.bar")
  end)

  describe("Bar.new", function()
    it("returns a pre-dismissed handle when bufnr is invalid", function()
      local bar = Bar.new({ bufnr = 99999, position = "top", segments = {} })
      assert.is_true(bar:is_dismissed())
    end)

    it("returns a handle with core fields populated", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local bar = Bar.new({ bufnr = bufnr, position = "top", segments = {} })
      assert.is_false(bar:is_dismissed())
      assert.equals(bufnr, bar.bufnr)
      assert.equals("top", bar.position)
      bar:dismiss()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("dismiss", function()
    it("is idempotent and fires on_dismiss exactly once", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local calls = 0
      local bar = Bar.new({
        bufnr = bufnr,
        position = "top",
        segments = {},
        on_dismiss = function()
          calls = calls + 1
        end,
      })
      bar:dismiss()
      bar:dismiss()
      assert.equals(1, calls)
      assert.is_true(bar:is_dismissed())
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("dismissed-handle no-op semantics", function()
    it("methods silently no-op after dismiss", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local bar = Bar.new({ bufnr = bufnr, position = "top", segments = {} })
      bar:dismiss()
      -- None of these should error
      bar:set_icon("x")
      bar:set_segments({})
      bar:set_highlight("Normal")
      bar:update({ icon = "y" })
      assert.is_true(bar:is_dismissed())
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("mutual exclusion", function()
    local function make_visible_buf()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "x" })
      vim.api.nvim_set_current_buf(bufnr)
      return bufnr
    end

    it("top dismisses existing top left and top right", function()
      local bufnr = make_visible_buf()
      local tl = Bar.new({ bufnr = bufnr, position = "top left", segments = {} })
      local tr = Bar.new({ bufnr = bufnr, position = "top right", segments = {} })
      local top = Bar.new({ bufnr = bufnr, position = "top", segments = {} })
      assert.is_true(tl:is_dismissed())
      assert.is_true(tr:is_dismissed())
      assert.is_false(top:is_dismissed())
      top:dismiss()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("top and bottom coexist", function()
      local bufnr = make_visible_buf()
      local t = Bar.new({ bufnr = bufnr, position = "top", segments = {} })
      local b = Bar.new({ bufnr = bufnr, position = "bottom", segments = {} })
      assert.is_false(t:is_dismissed())
      assert.is_false(b:is_dismissed())
      t:dismiss()
      b:dismiss()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("left and right corners on same side coexist", function()
      local bufnr = make_visible_buf()
      local tl = Bar.new({ bufnr = bufnr, position = "top left", segments = {} })
      local tr = Bar.new({ bufnr = bufnr, position = "top right", segments = {} })
      assert.is_false(tl:is_dismissed())
      assert.is_false(tr:is_dismissed())
      tl:dismiss()
      tr:dismiss()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
