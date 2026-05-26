--- Tests for tool execution indicator (extmark) placement
--- Covers: extmark positioning after buffer modifications during concurrent tool execution

-- Clear module caches for clean state
package.loaded["flemma.tools"] = nil
package.loaded["flemma.tools.approval"] = nil
package.loaded["flemma.tools.registry"] = nil
package.loaded["flemma.tools.executor"] = nil
package.loaded["flemma.tools.injector"] = nil
package.loaded["flemma.tools.context"] = nil
package.loaded["flemma.ui.indicators"] = nil
package.loaded["flemma.ui"] = nil

local tools = require("flemma.tools")
local registry = require("flemma.tools.registry")
local injector = require("flemma.tools.injector")
local indicators = require("flemma.ui.indicators")

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
--- Returns a map of 0-based line -> concatenated extmark virtual text content
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
    if result[line_idx] then
      result[line_idx] = result[line_idx] .. text
    else
      result[line_idx] = text
    end
  end
  return result
end

--- Helper: get extmarks on a line split by position type (inline vs eol)
--- @param bufnr integer
--- @param line_idx integer 0-based
--- @return { prefix?: string, prefix_hl?: string, eol?: string, eol_hl?: string }
local function get_extmark_parts(bufnr, line_idx)
  local marks = vim.api.nvim_buf_get_extmarks(
    bufnr,
    tool_exec_ns,
    { line_idx, 0 },
    { line_idx, -1 },
    { details = true }
  )
  local parts = {}
  for _, mark in ipairs(marks) do
    local details = mark[4]
    local text = ""
    local hl = nil
    if details.virt_text then
      for _, chunk in ipairs(details.virt_text) do
        text = text .. chunk[1]
        hl = hl or chunk[2]
      end
    end
    if details.virt_text_pos == "inline" then
      parts.prefix = text
      parts.prefix_hl = hl
    elseif details.virt_text_pos == "eol" then
      parts.eol = text
      parts.eol_hl = hl
    end
  end
  return parts
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
        "@Assistant:",
        "Running tool:",
        "",
        "**Tool Use:** `calculator` (`toolu_01`)",
        "```json",
        '{ "expression": "1+1" }',
        "```",
        "",
        "@You:",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "```",
      })

      -- header_line is 1-based (line 8 = "@You:", "**Tool Result:** `toolu_01`")
      indicators.show_tool_indicator(bufnr, "toolu_01", 8)

      local marks = get_tool_extmarks(bufnr)
      -- Extmark should be on 0-based line 7
      assert.is_not_nil(marks[7], "Extmark should be on the result header line (0-based 7)")
      assert.is_truthy(marks[7]:match("Executing"), "Should show executing indicator")

      indicators.clear_all_tool_indicators(bufnr)
    end)

    it("places two extmarks on separate lines for two tools", function()
      local bufnr = create_buffer({
        "@Assistant:",
        "Running tools:",
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
        "@You:",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "```",
        "",
        "**Tool Result:** `toolu_02`",
        "",
        "```",
        "```",
      })

      indicators.show_tool_indicator(bufnr, "toolu_01", 13) -- 0-based 12
      indicators.show_tool_indicator(bufnr, "toolu_02", 18) -- 0-based 17

      local marks = get_tool_extmarks(bufnr)
      assert.is_not_nil(marks[12], "Tool 1 extmark should be on line 12")
      assert.is_not_nil(marks[17], "Tool 2 extmark should be on line 17")

      indicators.clear_all_tool_indicators(bufnr)
    end)
  end)

  describe("extmark follows buffer modifications", function()
    it("extmark shifts down when lines are inserted above it", function()
      local bufnr = create_buffer({
        "@Assistant:",
        "Running tools:",
        "",
        "**Tool Use:** `calculator` (`toolu_01`)",
        "```json",
        '{ "expression": "1+1" }',
        "```",
        "",
        "@You:",
        "**Tool Result:** `toolu_01`", -- line 8, 0-based 7
        "",
        "```",
        "```",
      })

      indicators.show_tool_indicator(bufnr, "toolu_01", 8)

      -- Verify initial position
      local marks_before = get_tool_extmarks(bufnr)
      assert.is_not_nil(marks_before[7], "Extmark should start at line 7")

      -- Insert 3 lines above the extmark (simulating another tool result being injected)
      vim.api.nvim_buf_set_lines(bufnr, 7, 7, false, { "inserted line 1", "inserted line 2", "inserted line 3" })

      -- Neovim auto-adjusts extmarks — verify it shifted
      local marks_after = get_tool_extmarks(bufnr)
      assert.is_nil(marks_after[7], "Extmark should no longer be at original line 7")
      assert.is_not_nil(marks_after[10], "Extmark should have shifted to line 10 (7 + 3)")

      indicators.clear_all_tool_indicators(bufnr)
    end)

    it("update_tool_indicator uses current extmark position, not stale", function()
      local bufnr = create_buffer({
        "@Assistant:",
        "Running tools:",
        "",
        "**Tool Use:** `calculator` (`toolu_01`)",
        "```json",
        '{ "expression": "1+1" }',
        "```",
        "",
        "@You:",
        "**Tool Result:** `toolu_01`", -- line 8, 0-based 7
        "",
        "```",
        "```",
      })

      indicators.show_tool_indicator(bufnr, "toolu_01", 8)

      -- Insert lines above to shift the extmark
      vim.api.nvim_buf_set_lines(bufnr, 7, 7, false, { "extra1", "extra2", "extra3" })

      -- Now update the indicator (as completion would) — should use current position (10)
      indicators.update_tool_indicator(bufnr, "toolu_01", true)

      local marks = get_tool_extmarks(bufnr)
      -- Should be at shifted position (10), not original (7)
      assert.is_nil(marks[7], "Extmark should NOT be at original position")
      assert.is_not_nil(marks[10], "Extmark should be at shifted position 10")
      assert.is_truthy(marks[10]:match("Complete"), "Should show completion indicator")

      indicators.clear_all_tool_indicators(bufnr)
    end)
  end)

  describe("reposition_tool_indicators", function()
    it("corrects displaced extmark after line replacement", function()
      local bufnr = create_buffer({
        "@Assistant:",
        "Running tools:",
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
      indicators.show_tool_indicator(bufnr, "toolu_02", h2)

      -- Inject tool 1 placeholder (inserted before tool 2's, displaces extmark)
      local h1, e1 = injector.inject_placeholder(bufnr, "toolu_01")
      assert.is_not_nil(h1, "tool 1 placeholder: " .. tostring(e1))
      indicators.show_tool_indicator(bufnr, "toolu_01", h1)

      -- At this point, tool 2's extmark is displaced (Neovim pushed it during
      -- the set_lines replacement). The header is at line 17 but extmark is at 18.

      -- relocate should fix tool 2's extmark
      indicators.reposition_tool_indicators(bufnr)

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

      indicators.clear_all_tool_indicators(bufnr)
    end)

    it("corrects displaced extmark after result injection shifts lines", function()
      local bufnr = create_buffer({
        "@Assistant:",
        "Running tools:",
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
      indicators.show_tool_indicator(bufnr, "toolu_01", h1)
      indicators.reposition_tool_indicators(bufnr)

      local h2 = injector.inject_placeholder(bufnr, "toolu_02")
      indicators.show_tool_indicator(bufnr, "toolu_02", h2)
      indicators.reposition_tool_indicators(bufnr)

      -- Inject result for tool 1 (replaces placeholder, may shift tool 2)
      injector.inject_result(bufnr, "toolu_01", { success = true, output = "10000" })
      indicators.reposition_tool_indicators(bufnr)

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

      indicators.clear_all_tool_indicators(bufnr)
    end)

    it("corrects displaced EOL extmark when prefix is already on the header", function()
      local bufnr = create_buffer({
        "@Assistant:",
        "Running tool:",
        "",
        "**Tool Use:** `calculator` (`toolu_01`)",
        "```json",
        '{ "expression": "1+1" }',
        "```",
        "",
        "@You:",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "```",
        "spare line",
      })

      indicators.show_tool_indicator(bufnr, "toolu_01", 10)
      indicators.update_tool_indicator(bufnr, "toolu_01", true)

      local eol_extmark_id ---@type integer|nil
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, tool_exec_ns, { 9, 0 }, { 9, -1 }, { details = true })
      for _, mark in ipairs(marks) do
        local details = mark[4]
        if details.virt_text_pos == "eol" then
          eol_extmark_id = mark[1]
          pcall(vim.api.nvim_buf_set_extmark, bufnr, tool_exec_ns, 10, 0, {
            id = eol_extmark_id,
            virt_text = details.virt_text,
            virt_text_pos = "eol",
            hl_mode = "combine",
          })
        end
      end

      assert.is_not_nil(eol_extmark_id, "EOL extmark should exist")

      indicators.reposition_tool_indicators(bufnr)

      local header_parts = get_extmark_parts(bufnr, 9)
      local drift_parts = get_extmark_parts(bufnr, 10)
      assert.is_not_nil(header_parts.prefix, "Prefix should remain on the header")
      assert.is_not_nil(header_parts.eol, "EOL extmark should be restored to the header")
      assert.is_nil(drift_parts.eol, "EOL extmark should no longer be on the drifted line")

      indicators.clear_all_tool_indicators(bufnr)
    end)

    it("repositions executing spinner without corrupting EOL to inline", function()
      local bufnr = create_buffer({
        "@Assistant:",
        "Running tool:",
        "",
        "**Tool Use:** `calculator` (`toolu_01`)",
        "```json",
        '{ "expression": "1+1" }',
        "```",
        "",
        "@You:",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "```",
        "spare line",
      })

      indicators.show_tool_indicator(bufnr, "toolu_01", 10)

      pcall(vim.api.nvim_buf_set_extmark, bufnr, tool_exec_ns, 12, 0, {
        id = vim.api.nvim_buf_get_extmarks(bufnr, tool_exec_ns, 0, -1, {})[1][1],
        virt_text = { { " ⠋ Executing…", "FlemmaToolExecuting" } },
        virt_text_pos = "eol",
        hl_mode = "combine",
      })

      indicators.reposition_tool_indicators(bufnr)

      local header_parts = get_extmark_parts(bufnr, 9)
      assert.is_not_nil(header_parts.eol, "EOL spinner should be restored to header line")
      assert.is_nil(header_parts.prefix, "Should NOT have inline prefix during execution")

      indicators.clear_all_tool_indicators(bufnr)
    end)
  end)

  describe("two-extmark indicator model", function()
    it("show_pending creates inline prefix and EOL extmarks", function()
      local bufnr = create_buffer({
        "@You:",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "```",
      })

      indicators.show_pending_tool_indicator(bufnr, "toolu_01", 2)

      local parts = get_extmark_parts(bufnr, 1)
      assert.is_not_nil(parts.prefix, "Should have inline prefix extmark")
      assert.is_truthy(parts.prefix:match("⬢"), "Prefix should be ⬢ dot")
      assert.are.equal("FlemmaToolIconPending", parts.prefix_hl)
      assert.is_not_nil(parts.eol, "Should have EOL status extmark")
      assert.is_truthy(parts.eol:match("⏸"), "EOL should contain ⏸")
      assert.is_truthy(parts.eol:match("Pending"), "EOL should contain Pending")
      assert.are.equal("FlemmaToolPending", parts.eol_hl)

      indicators.clear_all_tool_indicators(bufnr)
    end)

    it("show_tool_indicator creates EOL spinner only (no prefix)", function()
      local bufnr = create_buffer({
        "@You:",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "```",
      })

      indicators.show_tool_indicator(bufnr, "toolu_01", 2)

      local parts = get_extmark_parts(bufnr, 1)
      assert.is_nil(parts.prefix, "Should NOT have inline prefix during execution")
      assert.is_not_nil(parts.eol, "Should have EOL status extmark")
      assert.is_truthy(parts.eol:match("Executing"), "EOL should contain Executing")
      assert.are.equal("FlemmaToolExecuting", parts.eol_hl)

      indicators.clear_all_tool_indicators(bufnr)
    end)

    it("update_tool_indicator transitions to success state", function()
      local bufnr = create_buffer({
        "@You:",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "```",
      })

      indicators.show_tool_indicator(bufnr, "toolu_01", 2)
      indicators.update_tool_indicator(bufnr, "toolu_01", true)

      local parts = get_extmark_parts(bufnr, 1)
      assert.is_not_nil(parts.prefix, "Should have inline prefix")
      assert.is_truthy(parts.prefix:match("⬢"), "Prefix should be ⬢ dot")
      assert.are.equal("FlemmaToolIconSuccess", parts.prefix_hl)
      assert.is_not_nil(parts.eol, "Should have EOL status")
      assert.is_truthy(parts.eol:match("✔"), "EOL should contain ✔")
      assert.is_truthy(parts.eol:match("Complete"), "EOL should contain Complete")
      assert.are.equal("FlemmaToolSuccess", parts.eol_hl)

      indicators.clear_all_tool_indicators(bufnr)
    end)

    it("update_tool_indicator transitions to error state", function()
      local bufnr = create_buffer({
        "@You:",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "```",
      })

      indicators.show_tool_indicator(bufnr, "toolu_01", 2)
      indicators.update_tool_indicator(bufnr, "toolu_01", false)

      local parts = get_extmark_parts(bufnr, 1)
      assert.is_not_nil(parts.prefix, "Should have inline prefix")
      assert.is_truthy(parts.prefix:match("⬢"), "Prefix should be ⬢ dot")
      assert.are.equal("FlemmaToolIconError", parts.prefix_hl)
      assert.is_not_nil(parts.eol, "Should have EOL status")
      assert.is_truthy(parts.eol:match("⚠"), "EOL should contain ⚠")
      assert.is_truthy(parts.eol:match("Failed"), "EOL should contain Failed")
      assert.are.equal("FlemmaToolError", parts.eol_hl)

      indicators.clear_all_tool_indicators(bufnr)
    end)

    it("clear_tool_indicator removes both extmarks", function()
      local bufnr = create_buffer({
        "@You:",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "```",
      })

      indicators.show_tool_indicator(bufnr, "toolu_01", 2)
      indicators.clear_tool_indicator(bufnr, "toolu_01")

      local marks = vim.api.nvim_buf_get_extmarks(bufnr, tool_exec_ns, 0, -1, {})
      assert.are.equal(0, #marks, "All extmarks should be removed")
    end)

    it("has_indicator returns true after completion (prefix persists)", function()
      local bufnr = create_buffer({
        "@You:",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "```",
      })

      indicators.show_tool_indicator(bufnr, "toolu_01", 2)
      indicators.update_tool_indicator(bufnr, "toolu_01", true)

      assert.is_true(indicators.has_indicator(bufnr, "toolu_01"))
    end)

    it("has_indicator returns false after scheduled status clear fires", function()
      local bufnr = create_buffer({
        "@You:",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "```",
      })

      indicators.show_tool_indicator(bufnr, "toolu_01", 2)
      indicators.update_tool_indicator(bufnr, "toolu_01", true)
      indicators.schedule_tool_indicator_clear(bufnr, "toolu_01", 50)

      vim.wait(200, function()
        return not indicators.has_indicator(bufnr, "toolu_01")
      end, 10)

      assert.is_false(indicators.has_indicator(bufnr, "toolu_01"))

      local marks = vim.api.nvim_buf_get_extmarks(bufnr, tool_exec_ns, 0, -1, {})
      assert.are.equal(0, #marks, "scheduled clear must remove both extmarks to avoid ghost dots")

      indicators.clear_all_tool_indicators(bufnr)
    end)
  end)

  describe("job result indicators", function()
    it("show_job_result_indicator creates success extmarks", function()
      local bufnr = create_buffer({
        "@You:",
        "**Job Result:** `job_abc12`",
        "",
        "```",
        "result content",
        "```",
      })

      indicators.show_job_result_indicator(bufnr, "job_abc12", 2, true)

      local parts = get_extmark_parts(bufnr, 1)
      assert.is_not_nil(parts.prefix, "Should have inline prefix extmark")
      assert.is_truthy(parts.prefix:match("⬢"), "Prefix should be ⬢ dot")
      assert.are.equal("FlemmaToolIconSuccess", parts.prefix_hl)
      assert.is_not_nil(parts.eol, "Should have EOL status extmark")
      assert.is_truthy(parts.eol:match("✔"), "EOL should contain ✔")
      assert.is_truthy(parts.eol:match("Complete"), "EOL should contain Complete")
      assert.are.equal("FlemmaToolSuccess", parts.eol_hl)

      indicators.clear_all_tool_indicators(bufnr)
    end)

    it("show_job_result_indicator creates error extmarks", function()
      local bufnr = create_buffer({
        "@You:",
        "**Job Result:** `job_abc12`",
        "",
        "```",
        "result content",
        "```",
      })

      indicators.show_job_result_indicator(bufnr, "job_abc12", 2, false)

      local parts = get_extmark_parts(bufnr, 1)
      assert.is_not_nil(parts.prefix, "Should have inline prefix extmark")
      assert.is_truthy(parts.prefix:match("⬢"), "Prefix should be ⬢ dot")
      assert.are.equal("FlemmaToolIconError", parts.prefix_hl)
      assert.is_not_nil(parts.eol, "Should have EOL status extmark")
      assert.is_truthy(parts.eol:match("⚠"), "EOL should contain ⚠")
      assert.is_truthy(parts.eol:match("Failed"), "EOL should contain Failed")
      assert.are.equal("FlemmaToolError", parts.eol_hl)

      indicators.clear_all_tool_indicators(bufnr)
    end)

    it("has_indicator returns true for job_result indicator", function()
      local bufnr = create_buffer({
        "@You:",
        "**Job Result:** `job_abc12`",
        "",
        "```",
        "result content",
        "```",
      })

      indicators.show_job_result_indicator(bufnr, "job_abc12", 2, true)

      assert.is_true(indicators.has_indicator(bufnr, "job_abc12"))

      indicators.clear_all_tool_indicators(bufnr)
    end)

    it("clear_tool_indicator removes job_result extmarks", function()
      local bufnr = create_buffer({
        "@You:",
        "**Job Result:** `job_abc12`",
        "",
        "```",
        "result content",
        "```",
      })

      indicators.show_job_result_indicator(bufnr, "job_abc12", 2, true)
      indicators.clear_tool_indicator(bufnr, "job_abc12")

      local marks = vim.api.nvim_buf_get_extmarks(bufnr, tool_exec_ns, 0, -1, {})
      assert.are.equal(0, #marks, "All extmarks should be removed")
    end)

    it("schedule_tool_indicator_clear removes job_result indicator after delay", function()
      local bufnr = create_buffer({
        "@You:",
        "**Job Result:** `job_abc12`",
        "",
        "```",
        "result content",
        "```",
      })

      indicators.show_job_result_indicator(bufnr, "job_abc12", 2, true)
      indicators.schedule_tool_indicator_clear(bufnr, "job_abc12", 50)

      vim.wait(200, function()
        return not indicators.has_indicator(bufnr, "job_abc12")
      end, 10)

      assert.is_false(indicators.has_indicator(bufnr, "job_abc12"))

      local marks = vim.api.nvim_buf_get_extmarks(bufnr, tool_exec_ns, 0, -1, {})
      assert.are.equal(0, #marks, "scheduled clear must remove both extmarks")

      indicators.clear_all_tool_indicators(bufnr)
    end)
  end)
end)
