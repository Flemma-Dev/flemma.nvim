--- Tests for tool use preview virtual lines in empty flemma:tool blocks
--- Covers: format_tool_preview formatting and add_tool_previews extmark placement

-- Clear module caches for clean state
package.loaded["flemma.ui"] = nil
package.loaded["flemma.ui.preview"] = nil

local ui_preview = require("flemma.ui.preview")

describe("Tool Preview", function()
  describe("format_tool_preview", function()
    it("formats single-key input as tool_name: key=value", function()
      local result = ui_preview.format_tool_preview("run_cmd", { command = "ls -la /tmp" })
      assert.are.equal('run_cmd: command="ls -la /tmp"', result)
    end)

    it("formats multi-key input with sorted keys", function()
      local result = ui_preview.format_tool_preview("search", { query = "foo", path = "./src" })
      -- Keys are sorted alphabetically for determinism
      assert.are.equal('search: path="./src", query="foo"', result)
    end)

    it("truncates long values to max_length", function()
      local long_command = string.rep("a", 200)
      local result = ui_preview.format_tool_preview("bash", { command = long_command }, 60)
      assert.is_truthy(#result <= 60, "Result should be at most 60 chars, got " .. #result)
      assert.is_truthy(result:match("…$"), "Should end with truncation marker")
    end)

    it("uses default max_length when not specified", function()
      local long_command = string.rep("a", 200)
      local result = ui_preview.format_tool_preview("bash", { command = long_command })
      assert.is_truthy(#result <= 80, "Result should be at most 80 chars (default), got " .. #result)
      assert.is_truthy(result:match("…$"), "Should end with truncation marker")
    end)

    it("handles empty input table", function()
      local result = ui_preview.format_tool_preview("noop", {})
      assert.are.equal("noop", result)
    end)

    it("formats non-string values with tostring", function()
      local result = ui_preview.format_tool_preview("math_eval", { expression = "1+1", precision = 2 })
      -- Keys sorted: expression, precision
      assert.are.equal('math_eval: expression="1+1", precision=2', result)
    end)

    it("formats boolean values without quotes", function()
      local result = ui_preview.format_tool_preview("toggle", { enabled = true })
      assert.are.equal("toggle: enabled=true", result)
    end)

    it("formats array values as [N items]", function()
      local result = ui_preview.format_tool_preview("tool", { items = { "a", "b", "c" } })
      assert.are.equal("tool: items=[3 items]", result)
    end)

    it("formats single-element array as [1 item]", function()
      local result = ui_preview.format_tool_preview("tool", { items = { "only" } })
      assert.are.equal("tool: items=[1 item]", result)
    end)

    it("formats object values with key preview", function()
      local result = ui_preview.format_tool_preview("tool", { config = { host = "localhost", port = 8080 } })
      assert.are.equal("tool: config={host, port}", result)
    end)

    it("formats object values with +N more for >2 keys", function()
      local result = ui_preview.format_tool_preview("tool", { config = { a = 1, b = 2, c = 3, d = 4 } })
      assert.are.equal("tool: config={a, b, +2 more}", result)
    end)

    it("formats empty table values as {}", function()
      local result = ui_preview.format_tool_preview("tool", { opts = {} })
      assert.are.equal("tool: opts={}", result)
    end)

    it("lists scalar keys before table keys", function()
      local result = ui_preview.format_tool_preview("tool", { x = 10, y = { 1, 2, 3 }, z = "hi" })
      assert.are.equal('tool: x=10, z="hi", y=[3 items]', result)
    end)

    it("escapes quotes in string values", function()
      local result = ui_preview.format_tool_preview("run_cmd", { command = 'echo "hello"' })
      assert.are.equal('run_cmd: command="echo \\"hello\\""', result)
    end)

    it("collapses newlines in string values", function()
      local result = ui_preview.format_tool_preview("run_cmd", { command = "echo hello\necho world" })
      assert.are.equal('run_cmd: command="echo hello⤶echo world"', result)
    end)

    it("uses custom format_preview from tool registry", function()
      package.loaded["flemma.tools.registry"] = nil
      local registry = require("flemma.tools.registry")
      registry.define("custom_tool", {
        name = "custom_tool",
        description = "test tool",
        input_schema = { type = "object", properties = {} },
        format_preview = function(input)
          return "custom: " .. input.key
        end,
      })

      local result = ui_preview.format_tool_preview("custom_tool", { key = "value" })
      assert.are.equal("custom_tool: custom: value", result)

      -- Clean up
      registry.define("custom_tool", nil)
    end)

    it("falls back to generic formatting when no format_preview", function()
      local result = ui_preview.format_tool_preview("unknown_tool", { key = "value" })
      assert.are.equal('unknown_tool: key="value"', result)
    end)

    it("collapses newlines in custom format_preview output", function()
      package.loaded["flemma.tools.registry"] = nil
      local registry = require("flemma.tools.registry")
      registry.define("newline_tool", {
        name = "newline_tool",
        description = "test tool",
        input_schema = { type = "object", properties = {} },
        format_preview = function(_input)
          return "line1\nline2"
        end,
      })

      local result = ui_preview.format_tool_preview("newline_tool", {})
      assert.are.equal("newline_tool: line1⤶line2", result)

      registry.define("newline_tool", nil)
    end)

    it("truncates custom format_preview output to max_length", function()
      package.loaded["flemma.tools.registry"] = nil
      local registry = require("flemma.tools.registry")
      registry.define("long_tool", {
        name = "long_tool",
        description = "test tool",
        input_schema = { type = "object", properties = {} },
        format_preview = function(_input)
          return string.rep("x", 200)
        end,
      })

      local result = ui_preview.format_tool_preview("long_tool", {}, 40)
      assert.is_truthy(#result <= 40, "Should truncate to max_length, got " .. #result)
      assert.is_truthy(result:match("^long_tool: "), "Should start with tool name prefix")
      assert.is_truthy(result:match("…$"), "Should end with truncation marker")

      registry.define("long_tool", nil)
    end)

    it("passes available width (after name prefix) to format_preview", function()
      package.loaded["flemma.tools.registry"] = nil
      local registry = require("flemma.tools.registry")
      local received_max_length

      registry.define("width_tool", {
        name = "width_tool",
        description = "test tool",
        input_schema = { type = "object", properties = {} },
        format_preview = function(_input, max_length)
          received_max_length = max_length
          return "body"
        end,
      })

      ui_preview.format_tool_preview("width_tool", {}, 50)
      -- "width_tool: " is 12 chars, so available should be 50 - 12 = 38
      assert.are.equal(38, received_max_length)

      registry.define("width_tool", nil)
    end)
  end)

  describe("add_tool_previews", function()
    -- Access the preview namespace
    local tool_preview_ns = vim.api.nvim_create_namespace("flemma_tool_preview")

    --- Helper: create a scratch buffer with given lines
    ---@param lines string[]
    ---@return integer bufnr
    local function create_buffer(lines)
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      return bufnr
    end

    --- Helper: get all virt_lines extmarks in the preview namespace
    ---@param bufnr integer
    ---@return table<integer, string[]> line_idx -> array of virt_line text strings
    local function get_preview_extmarks(bufnr)
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, tool_preview_ns, 0, -1, { details = true })
      local result = {}
      for _, mark in ipairs(marks) do
        local line_idx = mark[2]
        local details = mark[4]
        if details.virt_lines then
          local texts = {}
          for _, virt_line in ipairs(details.virt_lines) do
            for _, chunk in ipairs(virt_line) do
              table.insert(texts, chunk[1])
            end
          end
          result[line_idx] = texts
        end
      end
      return result
    end

    ---@type flemma.UI
    local ui

    before_each(function()
      package.loaded["flemma.ui"] = nil
      package.loaded["flemma.ui.preview"] = nil
      package.loaded["flemma.parser"] = nil
      ui = require("flemma.ui")
    end)

    after_each(function()
      vim.cmd("silent! %bdelete!")
    end)

    it("places virtual line inside empty pending tool block", function()
      local bufnr = create_buffer({
        "@Assistant: I'll run a command.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls -la" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01`",
        "",
        "```flemma:tool status=pending",
        "```",
      })

      local parser = require("flemma.parser")
      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)

      local marks = get_preview_extmarks(bufnr)
      -- Opening fence is line 12 (1-based) = 0-based 11
      assert.is_not_nil(marks[11], "Should have preview extmark on opening fence line")
      local text = table.concat(marks[11], "")
      assert.is_truthy(text:match("bash"), "Preview should contain tool name")
      assert.is_truthy(text:match("ls %-la"), "Preview should contain command value")
    end)

    it("does NOT place virtual line when tool block has content", function()
      local bufnr = create_buffer({
        "@Assistant: I'll run a command.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls -la" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01`",
        "",
        "```flemma:tool status=pending",
        "some user content here",
        "```",
      })

      local parser = require("flemma.parser")
      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)

      local all_marks = vim.api.nvim_buf_get_extmarks(bufnr, tool_preview_ns, 0, -1, {})
      assert.are.equal(0, #all_marks, "Should NOT place preview when block has content")
    end)

    it("places previews for multiple tool blocks", function()
      local bufnr = create_buffer({
        "@Assistant: Running two tools.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "**Tool Use:** `read_file` (`toolu_02`)",
        "```json",
        '{ "path": "./main.lua" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01`",
        "",
        "```flemma:tool status=pending",
        "```",
        "",
        "**Tool Result:** `toolu_02`",
        "",
        "```flemma:tool status=approved",
        "```",
      })

      local parser = require("flemma.parser")
      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)

      local all_marks = vim.api.nvim_buf_get_extmarks(bufnr, tool_preview_ns, 0, -1, {})
      assert.are.equal(2, #all_marks, "Should have previews for both tool blocks")
    end)

    it("clears previews on re-run (idempotent)", function()
      local bufnr = create_buffer({
        "@Assistant: Tool call.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01`",
        "",
        "```flemma:tool status=pending",
        "```",
      })

      local parser = require("flemma.parser")
      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)
      ui.add_tool_previews(bufnr, doc) -- run twice

      local all_marks = vim.api.nvim_buf_get_extmarks(bufnr, tool_preview_ns, 0, -1, {})
      assert.are.equal(1, #all_marks, "Should not duplicate extmarks on re-run")
    end)

    it("skips tool_result without status (resolved results)", function()
      local bufnr = create_buffer({
        "@Assistant: Tool call.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "file1.txt",
        "file2.txt",
        "```",
      })

      local parser = require("flemma.parser")
      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)

      local all_marks = vim.api.nvim_buf_get_extmarks(bufnr, tool_preview_ns, 0, -1, {})
      assert.are.equal(0, #all_marks, "Should NOT place preview for resolved tool results")
    end)
  end)

  describe("built-in tool format_preview", function()
    before_each(function()
      package.loaded["flemma"] = nil
      package.loaded["flemma.ui.preview"] = nil
      package.loaded["flemma.tools.registry"] = nil
      package.loaded["flemma.tools"] = nil
      package.loaded["flemma.tools.definitions.calculator"] = nil
      package.loaded["flemma.tools.definitions.bash"] = nil
      package.loaded["flemma.tools.definitions.read"] = nil
      package.loaded["flemma.tools.definitions.edit"] = nil
      package.loaded["flemma.tools.definitions.write"] = nil

      require("flemma").setup({})
      ui_preview = require("flemma.ui.preview")
    end)

    it("calculator shows expression", function()
      local result = ui_preview.format_tool_preview("calculator", { expression = "2 + 2 * 3" })
      assert.are.equal("calculator: 2 + 2 * 3", result)
    end)

    it("calculator_async shows expression and delay", function()
      local result = ui_preview.format_tool_preview("calculator_async", { expression = "sqrt(16)", delay = 500 })
      assert.are.equal("calculator_async: sqrt(16)  # 500ms", result)
    end)

    it("calculator_async omits delay when nil", function()
      local result = ui_preview.format_tool_preview("calculator_async", { expression = "1+1" })
      assert.are.equal("calculator_async: 1+1", result)
    end)

    it("bash shows $ command with label comment", function()
      local result = ui_preview.format_tool_preview("bash", { command = "ls -la /tmp", label = "list files" })
      assert.are.equal("bash: $ ls -la /tmp  # list files", result)
    end)

    it("bash omits label when not provided", function()
      local result = ui_preview.format_tool_preview("bash", { command = "echo hello" })
      assert.are.equal("bash: $ echo hello", result)
    end)

    it("read shows path with offset and limit", function()
      local result = ui_preview.format_tool_preview(
        "read",
        { path = "./src/main.lua", offset = 10, limit = 50, label = "read config" }
      )
      assert.are.equal("read: ./src/main.lua  +10,50  # read config", result)
    end)

    it("read shows path with offset only", function()
      local result = ui_preview.format_tool_preview("read", { path = "./src/main.lua", offset = 10 })
      assert.are.equal("read: ./src/main.lua  +10", result)
    end)

    it("read shows path with limit only", function()
      local result = ui_preview.format_tool_preview("read", { path = "./src/main.lua", limit = 50 })
      assert.are.equal("read: ./src/main.lua  +,50", result)
    end)

    it("read shows plain path without offset or limit", function()
      local result = ui_preview.format_tool_preview("read", { path = "./src/main.lua", label = "check file" })
      assert.are.equal("read: ./src/main.lua  # check file", result)
    end)

    it("edit shows path with label", function()
      local result = ui_preview.format_tool_preview(
        "edit",
        { path = "./src/main.lua", oldText = "foo", newText = "bar", label = "fix typo" }
      )
      assert.are.equal("edit: ./src/main.lua  # fix typo", result)
    end)

    it("edit shows plain path without label", function()
      local result =
        ui_preview.format_tool_preview("edit", { path = "./src/main.lua", oldText = "foo", newText = "bar" })
      assert.are.equal("edit: ./src/main.lua", result)
    end)

    it("write shows path with byte size and label", function()
      local content = string.rep("x", 1536)
      local result =
        ui_preview.format_tool_preview("write", { path = "./src/main.lua", content = content, label = "create module" })
      assert.are.equal("write: ./src/main.lua  (1.5 KB)  # create module", result)
    end)

    it("write shows bytes for small content", function()
      local result = ui_preview.format_tool_preview("write", { path = "./readme.txt", content = "hello" })
      assert.are.equal("write: ./readme.txt  (5 B)", result)
    end)

    it("write shows label without content size when content is empty", function()
      local result =
        ui_preview.format_tool_preview("write", { path = "./empty.txt", content = "", label = "create empty" })
      assert.are.equal("write: ./empty.txt  (0 B)  # create empty", result)
    end)
  end)
end)
