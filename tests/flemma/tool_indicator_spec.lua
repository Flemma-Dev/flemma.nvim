--- Tests for tool execution indicator (extmark) placement
--- Covers: extmark positioning after buffer modifications during concurrent tool execution

-- Clear module caches for clean state
package.loaded["flemma.tools"] = nil
package.loaded["flemma.tools.registry"] = nil
package.loaded["flemma.tools.executor"] = nil
package.loaded["flemma.tools.injector"] = nil
package.loaded["flemma.tools.context"] = nil
package.loaded["flemma.ui"] = nil

local tools = require("flemma.tools")
local registry = require("flemma.tools.registry")
local injector = require("flemma.tools.injector")
local ui = require("flemma.ui")

-- Access the tool_exec namespace (nvim_create_namespace returns same ID if already created)
local tool_exec_ns = vim.api.nvim_create_namespace("flemma_tool_execution")

--- Helper: create a scratch buffer with given lines
--- @param lines string[]
--- @return integer bufnr
local function create_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

--- Helper: get all extmarks in the tool_exec namespace for a buffer
--- Returns a map of 0-based line -> extmark virtual text content
--- @param bufnr integer
--- @return table<integer, string> line_idx -> virt_text string
local function get_tool_extmarks(bufnr)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, tool_exec_ns, 0, -1, { details = true })
  local result = {}
  for _, mark in ipairs(marks) do
    local line_idx = mark[2]
    local details = mark[4]
    local text = ""
    if details.virt_text then
      for _, chunk in ipairs(details.virt_text) do
        text = text .. chunk[1]
      end
    end
    result[line_idx] = text
  end
  return result
end

-- ============================================================================
-- Indicator Placement Tests (unit-level, using ui functions directly)
-- ============================================================================

describe("Tool Indicator Extmark Placement", function()
  before_each(function()
    registry.clear()
    tools.setup()
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  describe("initial placement", function()
    it("places extmark on the tool result header line", function()
      local bufnr = create_buffer({
        "@Assistant: Running tool:",
        "",
        "**Tool Use:** `calculator` (`toolu_01`)",
        "```json",
        '{ "expression": "1+1" }',
        "```",
        "",
        "@You: **Tool Result:** `toolu_01`",
        "",
        "```",
        "```",
      })

      -- header_line is 1-based (line 8 = "@You: **Tool Result:** `toolu_01`")
      ui.show_tool_indicator(bufnr, "toolu_01", 8)

      local marks = get_tool_extmarks(bufnr)
      -- Extmark should be on 0-based line 7
      assert.is_not_nil(marks[7], "Extmark should be on the result header line (0-based 7)")
      assert.is_truthy(marks[7]:match("Executing"), "Should show executing indicator")

      ui.clear_all_tool_indicators(bufnr)
    end)

    it("places two extmarks on separate lines for two tools", function()
      local bufnr = create_buffer({
        "@Assistant: Running tools:",
        "",
        "**Tool Use:** `calculator` (`toolu_01`)",
        "```json",
        '{ "expression": "1+1" }',
        "```",
        "",
        "**Tool Use:** `calculator` (`toolu_02`)",
        "```json",
        '{ "expression": "2+2" }',
        "```",
        "",
        "@You: **Tool Result:** `toolu_01`",
        "",
        "```",
        "```",
        "",
        "**Tool Result:** `toolu_02`",
        "",
        "```",
        "```",
      })

      ui.show_tool_indicator(bufnr, "toolu_01", 13) -- 0-based 12
      ui.show_tool_indicator(bufnr, "toolu_02", 18) -- 0-based 17

      local marks = get_tool_extmarks(bufnr)
      assert.is_not_nil(marks[12], "Tool 1 extmark should be on line 12")
      assert.is_not_nil(marks[17], "Tool 2 extmark should be on line 17")

      ui.clear_all_tool_indicators(bufnr)
    end)
  end)

  describe("extmark follows buffer modifications", function()
    it("extmark shifts down when lines are inserted above it", function()
      local bufnr = create_buffer({
        "@Assistant: Running tools:",
        "",
        "**Tool Use:** `calculator` (`toolu_01`)",
        "```json",
        '{ "expression": "1+1" }',
        "```",
        "",
        "@You: **Tool Result:** `toolu_01`", -- line 8, 0-based 7
        "",
        "```",
        "```",
      })

      ui.show_tool_indicator(bufnr, "toolu_01", 8)

      -- Verify initial position
      local marks_before = get_tool_extmarks(bufnr)
      assert.is_not_nil(marks_before[7], "Extmark should start at line 7")

      -- Insert 3 lines above the extmark (simulating another tool result being injected)
      vim.api.nvim_buf_set_lines(bufnr, 7, 7, false, { "inserted line 1", "inserted line 2", "inserted line 3" })

      -- Neovim auto-adjusts extmarks — verify it shifted
      local marks_after = get_tool_extmarks(bufnr)
      assert.is_nil(marks_after[7], "Extmark should no longer be at original line 7")
      assert.is_not_nil(marks_after[10], "Extmark should have shifted to line 10 (7 + 3)")

      ui.clear_all_tool_indicators(bufnr)
    end)

    it("update_tool_indicator uses current extmark position, not stale", function()
      local bufnr = create_buffer({
        "@Assistant: Running tools:",
        "",
        "**Tool Use:** `calculator` (`toolu_01`)",
        "```json",
        '{ "expression": "1+1" }',
        "```",
        "",
        "@You: **Tool Result:** `toolu_01`", -- line 8, 0-based 7
        "",
        "```",
        "```",
      })

      ui.show_tool_indicator(bufnr, "toolu_01", 8)

      -- Insert lines above to shift the extmark
      vim.api.nvim_buf_set_lines(bufnr, 7, 7, false, { "extra1", "extra2", "extra3" })

      -- Now update the indicator (as completion would) — should use current position (10)
      ui.update_tool_indicator(bufnr, "toolu_01", true)

      local marks = get_tool_extmarks(bufnr)
      -- Should be at shifted position (10), not original (7)
      assert.is_nil(marks[7], "Extmark should NOT be at original position")
      assert.is_not_nil(marks[10], "Extmark should be at shifted position 10")
      assert.is_truthy(marks[10]:match("Complete"), "Should show completion indicator")

      ui.clear_all_tool_indicators(bufnr)
    end)
  end)

  describe("reposition_tool_indicators", function()
    it("corrects displaced extmark after line replacement", function()
      local bufnr = create_buffer({
        "@Assistant: Running tools:",
        "",
        "**Tool Use:** `calculator` (`toolu_01`)",
        "```json",
        '{ "expression": "1+1" }',
        "```",
        "",
        "**Tool Use:** `calculator` (`toolu_02`)",
        "```json",
        '{ "expression": "2+2" }',
        "```",
      })

      -- Inject tool 2 placeholder first (reverse order)
      local h2, e2 = injector.inject_placeholder(bufnr, "toolu_02")
      assert.is_not_nil(h2, "tool 2 placeholder: " .. tostring(e2))
      ui.show_tool_indicator(bufnr, "toolu_02", h2)

      -- Inject tool 1 placeholder (inserted before tool 2's, displaces extmark)
      local h1, e1 = injector.inject_placeholder(bufnr, "toolu_01")
      assert.is_not_nil(h1, "tool 1 placeholder: " .. tostring(e1))
      ui.show_tool_indicator(bufnr, "toolu_01", h1)

      -- At this point, tool 2's extmark is displaced (Neovim pushed it during
      -- the set_lines replacement). The header is at line 17 but extmark is at 18.

      -- relocate should fix tool 2's extmark
      ui.reposition_tool_indicators(bufnr)

      -- Find actual header positions
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local line_01, line_02
      for i, line in ipairs(lines) do
        if line:find("Tool Result", 1, true) and line:find("toolu_01", 1, true) then
          line_01 = i - 1
        end
        if line:find("Tool Result", 1, true) and line:find("toolu_02", 1, true) then
          line_02 = i - 1
        end
      end

      assert.is_not_nil(line_01, "Tool 1 header should exist")
      assert.is_not_nil(line_02, "Tool 2 header should exist")

      local marks = get_tool_extmarks(bufnr)
      assert.is_not_nil(marks[line_01], "Tool 1 extmark should be on its header (line " .. line_01 .. ")")
      assert.is_not_nil(marks[line_02], "Tool 2 extmark should be on its header (line " .. line_02 .. ")")

      ui.clear_all_tool_indicators(bufnr)
    end)

    it("corrects displaced extmark after result injection shifts lines", function()
      local bufnr = create_buffer({
        "@Assistant: Running tools:",
        "",
        "**Tool Use:** `calculator` (`toolu_01`)",
        "```json",
        '{ "expression": "1+1" }',
        "```",
        "",
        "**Tool Use:** `calculator` (`toolu_02`)",
        "```json",
        '{ "expression": "2+2" }',
        "```",
      })

      -- Inject both placeholders in order
      local h1 = injector.inject_placeholder(bufnr, "toolu_01")
      ui.show_tool_indicator(bufnr, "toolu_01", h1)
      ui.reposition_tool_indicators(bufnr)

      local h2 = injector.inject_placeholder(bufnr, "toolu_02")
      ui.show_tool_indicator(bufnr, "toolu_02", h2)
      ui.reposition_tool_indicators(bufnr)

      -- Inject result for tool 1 (replaces placeholder, may shift tool 2)
      injector.inject_result(bufnr, "toolu_01", { success = true, output = "10000" })
      ui.reposition_tool_indicators(bufnr)

      -- Find actual header positions
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local line_01, line_02
      for i, line in ipairs(lines) do
        if line:find("Tool Result", 1, true) and line:find("toolu_01", 1, true) then
          line_01 = i - 1
        end
        if line:find("Tool Result", 1, true) and line:find("toolu_02", 1, true) then
          line_02 = i - 1
        end
      end

      local marks = get_tool_extmarks(bufnr)
      assert.is_not_nil(marks[line_01], "Tool 1 extmark on its header after result injection")
      assert.is_not_nil(marks[line_02], "Tool 2 extmark on its header after result injection")

      ui.clear_all_tool_indicators(bufnr)
    end)
  end)
end)
