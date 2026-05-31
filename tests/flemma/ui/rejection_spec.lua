--- Tests for flemma.ui.rejection and related scratch buffer changes

-- Clear module caches for clean state
package.loaded["flemma.utilities.buffer"] = nil
package.loaded["flemma.ui.rejection"] = nil
package.loaded["flemma.tools.context"] = nil
package.loaded["flemma.tools.executor"] = nil
package.loaded["flemma.tools.injector"] = nil
package.loaded["flemma.navigation"] = nil
package.loaded["flemma.state"] = nil
package.loaded["flemma.config"] = nil
package.loaded["flemma.config.store"] = nil
package.loaded["flemma.config.proxy"] = nil
package.loaded["flemma.config.schema"] = nil

local buffer_utils = require("flemma.utilities.buffer")
local config_facade = require("flemma.config")
local schema = require("flemma.config.schema")

---@param lines string[]
---@return integer
local function create_chat_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(bufnr)
  return bufnr
end

local TOOL_RESULT_BUFFER = {
  "@Assistant:",
  "Running tool",
  "",
  "**Tool Use:** `calculator` (`toolu_01`)",
  "```json",
  '{ "expression": "2+2" }',
  "```",
  "",
  "@You:",
  "**Tool Result:** `toolu_01` (pending)",
  "",
  "```",
  "```",
}

local MULTI_LINE_TOOL_RESULT = {
  "@Assistant:",
  "Running tool",
  "",
  "**Tool Use:** `calculator` (`toolu_01`)",
  "```json",
  '{ "expression": "2+2" }',
  "```",
  "",
  "@You:",
  "**Tool Result:** `toolu_01` (pending)",
  "",
  "```",
  "line one",
  "line two",
  "line three",
  "```",
}

---@param opts? table
local function init_config(opts)
  config_facade.init(schema)
  if opts and next(opts) then
    config_facade.apply(config_facade.LAYERS.SETUP, opts)
  end
  config_facade.finalize(config_facade.LAYERS.SETUP)
end

-- ---------------------------------------------------------------------------
-- create_scratch_buffer undolevels sentinel
-- ---------------------------------------------------------------------------

describe("create_scratch_buffer undolevels sentinel", function()
  before_each(function()
    package.loaded["flemma.utilities.buffer"] = nil
    buffer_utils = require("flemma.utilities.buffer")
  end)

  it("sets undolevels to -1 by default", function()
    local bufnr = buffer_utils.create_scratch_buffer()
    assert.equals(-1, vim.bo[bufnr].undolevels)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("sets undolevels to a custom value when passed a number", function()
    local bufnr = buffer_utils.create_scratch_buffer({ undolevels = 500 })
    assert.equals(500, vim.bo[bufnr].undolevels)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("does not set undolevels when passed false", function()
    local reference = vim.api.nvim_create_buf(false, true)
    local expected = vim.bo[reference].undolevels
    vim.api.nvim_buf_delete(reference, { force = true })
    local bufnr = buffer_utils.create_scratch_buffer({ undolevels = false })
    assert.equals(expected, vim.bo[bufnr].undolevels)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

-- ---------------------------------------------------------------------------
-- flemma.ui.rejection
-- ---------------------------------------------------------------------------

describe("flemma.ui.rejection", function()
  local rejection

  before_each(function()
    package.loaded["flemma.ui.rejection"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil
    config_facade = require("flemma.config")
    rejection = require("flemma.ui.rejection")
    init_config()
  end)

  after_each(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) then
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].buftype == "nofile" and vim.bo[buf].bufhidden == "wipe" then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
    end
    vim.cmd("silent! %bdelete!")
  end)

  -- -------------------------------------------------------------------------
  -- is_open lifecycle
  -- -------------------------------------------------------------------------

  describe("is_open", function()
    it("returns false when no popup is active", function()
      assert.is_false(rejection.is_open())
    end)

    it("returns true after opening on a valid tool", function()
      local bufnr = create_chat_buffer(TOOL_RESULT_BUFFER)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      rejection.open(bufnr)
      assert.is_true(rejection.is_open())
    end)
  end)

  -- -------------------------------------------------------------------------
  -- open error handling
  -- -------------------------------------------------------------------------

  describe("open", function()
    it("does not open when no tool is at cursor", function()
      local bufnr = create_chat_buffer({ "no tool here" })
      rejection.open(bufnr)
      assert.is_false(rejection.is_open())
    end)

    it("opens on tool_use block and finds the sibling tool_result", function()
      local bufnr = create_chat_buffer(TOOL_RESULT_BUFFER)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      rejection.open(bufnr)
      assert.is_true(rejection.is_open())
    end)

    it("opens on tool_result block", function()
      local bufnr = create_chat_buffer(TOOL_RESULT_BUFFER)
      vim.api.nvim_win_set_cursor(0, { 10, 0 })
      rejection.open(bufnr)
      assert.is_true(rejection.is_open())
    end)
  end)

  -- -------------------------------------------------------------------------
  -- Float buffer content
  -- -------------------------------------------------------------------------

  describe("float buffer", function()
    it("is prefilled with 'User feedback: '", function()
      local bufnr = create_chat_buffer(TOOL_RESULT_BUFFER)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      rejection.open(bufnr)

      local float_wins = {}
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].bufhidden == "wipe" and vim.bo[buf].buftype == "nofile" then
          table.insert(float_wins, win)
        end
      end
      assert.equals(1, #float_wins)

      local float_buf = vim.api.nvim_win_get_buf(float_wins[1])
      local lines = vim.api.nvim_buf_get_lines(float_buf, 0, -1, false)
      assert.equals("User feedback: ", lines[1])
    end)

    it("has undo enabled (undolevels inherited, not -1)", function()
      local bufnr = create_chat_buffer(TOOL_RESULT_BUFFER)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      rejection.open(bufnr)

      local float_buf = vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())
      assert.is_not.equals(-1, vim.bo[float_buf].undolevels)
    end)
  end)

  -- -------------------------------------------------------------------------
  -- Float window properties
  -- -------------------------------------------------------------------------

  describe("float window", function()
    it("has wrap and linebreak enabled", function()
      local bufnr = create_chat_buffer(TOOL_RESULT_BUFFER)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      rejection.open(bufnr)

      local float_win = vim.api.nvim_get_current_win()
      assert.is_true(vim.wo[float_win].wrap)
      assert.is_true(vim.wo[float_win].linebreak)
    end)

    it("has number and signcolumn disabled", function()
      local bufnr = create_chat_buffer(TOOL_RESULT_BUFFER)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      rejection.open(bufnr)

      local float_win = vim.api.nvim_get_current_win()
      assert.is_false(vim.wo[float_win].number)
      assert.is_false(vim.wo[float_win].relativenumber)
      assert.equals("no", vim.wo[float_win].signcolumn)
    end)

    it("uses configured winblend", function()
      local bufnr = create_chat_buffer(TOOL_RESULT_BUFFER)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      rejection.open(bufnr)

      local float_win = vim.api.nvim_get_current_win()
      assert.equals(15, vim.wo[float_win].winblend)
    end)

    it("sets winhighlight for rejection groups", function()
      local bufnr = create_chat_buffer(TOOL_RESULT_BUFFER)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      rejection.open(bufnr)

      local float_win = vim.api.nvim_get_current_win()
      local winhl = vim.wo[float_win].winhighlight
      assert.truthy(winhl:find("FlemmaRejection"))
      assert.truthy(winhl:find("FlemmaRejectionBorder"))
    end)

    it("disables buffer-local completion by default", function()
      local bufnr = create_chat_buffer(TOOL_RESULT_BUFFER)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      rejection.open(bufnr)

      local float_buf = vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())
      assert.is_false(vim.b[float_buf].completion)
    end)

    it("has top and bottom borders only", function()
      local bufnr = create_chat_buffer(TOOL_RESULT_BUFFER)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      rejection.open(bufnr)

      local float_win = vim.api.nvim_get_current_win()
      local config = vim.api.nvim_win_get_config(float_win)
      local border = config.border
      assert.equals("", border[1])
      assert.equals("╌", border[2])
      assert.equals("", border[3])
      assert.equals("", border[4])
      assert.equals("", border[5])
      assert.equals("╌", border[6])
      assert.equals("", border[7])
      assert.equals("", border[8])
    end)
  end)

  -- -------------------------------------------------------------------------
  -- Cursorline save/restore
  -- -------------------------------------------------------------------------

  describe("cursorline", function()
    it("disables cursorline in parent window while popup is open", function()
      local bufnr = create_chat_buffer(TOOL_RESULT_BUFFER)
      local parent_win = vim.api.nvim_get_current_win()
      vim.wo[parent_win].cursorline = true
      vim.api.nvim_win_set_cursor(0, { 4, 0 })

      rejection.open(bufnr)
      assert.is_false(vim.wo[parent_win].cursorline)
    end)

    it("restores cursorline in parent window after cancel", function()
      local bufnr = create_chat_buffer(TOOL_RESULT_BUFFER)
      local parent_win = vim.api.nvim_get_current_win()
      vim.wo[parent_win].cursorline = true
      vim.api.nvim_win_set_cursor(0, { 4, 0 })

      rejection.open(bufnr)
      assert.is_true(rejection.is_open())

      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>q", true, false, true), "x", false)

      assert.is_false(rejection.is_open())
      assert.is_true(vim.wo[parent_win].cursorline)
    end)

    it("preserves cursorline=false if it was already disabled", function()
      local bufnr = create_chat_buffer(TOOL_RESULT_BUFFER)
      local parent_win = vim.api.nvim_get_current_win()
      vim.wo[parent_win].cursorline = false
      vim.api.nvim_win_set_cursor(0, { 4, 0 })

      rejection.open(bufnr)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>q", true, false, true), "x", false)

      assert.is_false(vim.wo[parent_win].cursorline)
    end)
  end)

  -- -------------------------------------------------------------------------
  -- Insert mode cleanup
  -- -------------------------------------------------------------------------

  describe("mode on close", function()
    it("returns to normal mode after cancel", function()
      local bufnr = create_chat_buffer(TOOL_RESULT_BUFFER)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })

      rejection.open(bufnr)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>q", true, false, true), "x", false)

      assert.equals("n", vim.fn.mode())
    end)
  end)

  -- -------------------------------------------------------------------------
  -- Double-open guard
  -- -------------------------------------------------------------------------

  describe("double-open", function()
    it("closes the previous popup when opening a new one", function()
      local bufnr = create_chat_buffer(TOOL_RESULT_BUFFER)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })

      rejection.open(bufnr)
      assert.is_true(rejection.is_open())

      local first_win = vim.api.nvim_get_current_win()

      vim.cmd("stopinsert")
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      rejection.open(bufnr)
      assert.is_true(rejection.is_open())

      assert.is_false(vim.api.nvim_win_is_valid(first_win))
    end)
  end)

  -- -------------------------------------------------------------------------
  -- Config: enabled = false falls back to vim.ui.input
  -- -------------------------------------------------------------------------

  describe("config gating", function()
    it("falls back to vim.ui.input when ui.rejection.enabled is false", function()
      init_config({ ui = { rejection = { enabled = false } } })

      local input_called = false
      local orig_input = vim.ui.input
      vim.ui.input = function(opts, _on_confirm)
        input_called = true
        assert.truthy(opts.prompt:find("Rejection"))
      end

      local bufnr = create_chat_buffer(TOOL_RESULT_BUFFER)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      rejection.open(bufnr)

      vim.ui.input = orig_input
      assert.is_true(input_called)
      assert.is_false(rejection.is_open())
    end)
  end)

  -- -------------------------------------------------------------------------
  -- Multi-line tool result: initial height spans between fences
  -- -------------------------------------------------------------------------

  describe("multi-line tool result", function()
    it("initial height covers content between fences", function()
      local bufnr = create_chat_buffer(MULTI_LINE_TOOL_RESULT)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      rejection.open(bufnr)

      local float_win = vim.api.nvim_get_current_win()
      local height = vim.api.nvim_win_get_height(float_win)
      assert.is_true(height >= 3, "expected height >= 3 for 3 content lines, got " .. height)
    end)
  end)
end)
