--- Tool execution indicators (pending, spinner, complete/error).
--- Each tool call gets an EOL extmark on its result header line that
--- animates during execution and settles to a final state on completion.
---@class flemma.ui.Indicators
local M = {}

local ast = require("flemma.ast")
local parser = require("flemma.parser")
local state = require("flemma.state")
local spinners = require("flemma.ui.spinners")

local PRIORITY_TOOL_EXECUTION = 250

local tool_exec_ns = vim.api.nvim_create_namespace("flemma_tool_execution")

---@class flemma.ui.ToolIndicator
---@field extmark_id integer
---@field timer integer|nil

---Get or initialize the tool indicators table for a buffer
---@param bufnr integer
---@return table<string, flemma.ui.ToolIndicator>
local function indicators_for(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  if not buffer_state.tool_indicators then
    buffer_state.tool_indicators = {}
  end
  return buffer_state.tool_indicators
end

--- Get the current line of a tool execution extmark (auto-adjusted by Neovim)
---@param bufnr integer
---@param extmark_id integer
---@return integer|nil 0-based line index, or nil if extmark not found
local function get_extmark_line(bufnr, extmark_id)
  local ok, pos = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, tool_exec_ns, extmark_id, {})
  if ok and pos and #pos >= 1 then
    return pos[1]
  end
  return nil
end

---Check whether a tool_id has an active indicator. Used by tool previews
---to decide visibility when the header status suffix has been cleared.
---@param bufnr integer
---@param tool_id string
---@return boolean
function M.has_indicator(bufnr, tool_id)
  return indicators_for(bufnr)[tool_id] ~= nil
end

--- Show pending-approval indicator for a tool
--- Creates a static extmark (no spinner) at the tool result header line.
--- Automatically replaced when `show_tool_indicator` starts the execution spinner.
---@param bufnr integer
---@param tool_id string
---@param header_line integer 1-based line number of the tool result header
function M.show_pending_tool_indicator(bufnr, tool_id, header_line)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  M.clear_tool_indicator(bufnr, tool_id)

  local line_idx = header_line - 1

  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, tool_exec_ns, line_idx, 0, {
    virt_text = { { " ● Pending", "FlemmaToolPending" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
    priority = PRIORITY_TOOL_EXECUTION,
    spell = false,
  })

  indicators_for(bufnr)[tool_id] = {
    extmark_id = extmark_id,
    timer = nil,
  }
end

--- Show execution indicator for a tool
--- Creates extmark with animated spinner at the tool result header line
---@param bufnr integer
---@param tool_id string
---@param header_line integer 1-based line number of the tool result header
function M.show_tool_indicator(bufnr, tool_id, header_line)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Clean up any existing indicator for this tool
  M.clear_tool_indicator(bufnr, tool_id)

  local line_idx = header_line - 1
  local frame = 1

  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, tool_exec_ns, line_idx, 0, {
    virt_text = { { " " .. spinners.FRAMES.tool[frame] .. " Executing…", "FlemmaToolPending" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
    priority = PRIORITY_TOOL_EXECUTION,
    spell = false,
  })

  local timer ---@type integer
  timer = vim.fn.timer_start(200, function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      -- Buffer gone — stop ourselves; buffer state cleanup may have already run
      vim.fn.timer_stop(timer)
      return
    end

    local indicators = indicators_for(bufnr)
    local ind = indicators[tool_id]
    if not ind then
      return
    end

    local current_line = get_extmark_line(bufnr, ind.extmark_id)
    if not current_line then
      return
    end

    frame = (frame % #spinners.FRAMES.tool) + 1
    pcall(vim.api.nvim_buf_set_extmark, bufnr, tool_exec_ns, current_line, 0, {
      id = ind.extmark_id,
      virt_text = { { " " .. spinners.FRAMES.tool[frame] .. " Executing…", "FlemmaToolPending" } },
      virt_text_pos = "eol",
      hl_mode = "combine",
      priority = PRIORITY_TOOL_EXECUTION,
      spell = false,
    })
  end, { ["repeat"] = -1 })

  indicators_for(bufnr)[tool_id] = {
    extmark_id = extmark_id,
    timer = timer,
  }
end

--- Update indicator to show completion/error state
--- Stops animation, shows final state
---@param bufnr integer
---@param tool_id string
---@param success boolean
function M.update_tool_indicator(bufnr, tool_id, success)
  local indicators = indicators_for(bufnr)
  local ind = indicators[tool_id]
  if not ind then
    return
  end

  -- Stop animation timer
  if ind.timer then
    vim.fn.timer_stop(ind.timer)
    ind.timer = nil
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    indicators[tool_id] = nil
    return
  end

  -- Query extmark's current position (may have shifted due to buffer edits)
  local current_line = get_extmark_line(bufnr, ind.extmark_id)
  if not current_line then
    indicators[tool_id] = nil
    return
  end

  -- Show final state
  local text, hl
  if success then
    text = " ✓ Complete"
    hl = "FlemmaToolSuccess"
  else
    text = " ✗ Failed"
    hl = "FlemmaToolError"
  end

  pcall(vim.api.nvim_buf_set_extmark, bufnr, tool_exec_ns, current_line, 0, {
    id = ind.extmark_id,
    virt_text = { { text, hl } },
    virt_text_pos = "eol",
    hl_mode = "combine",
    priority = PRIORITY_TOOL_EXECUTION,
    spell = false,
  })
end

--- Clear indicator for a tool (removes extmark and stops timer)
---@param bufnr integer
---@param tool_id string
function M.clear_tool_indicator(bufnr, tool_id)
  local indicators = indicators_for(bufnr)
  local ind = indicators[tool_id]
  if not ind then
    return
  end

  if ind.timer then
    vim.fn.timer_stop(ind.timer)
  end

  if vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, tool_exec_ns, ind.extmark_id)
  end

  indicators[tool_id] = nil
end

--- Reposition all tool indicators to their correct header lines after buffer modification.
--- When inject_placeholder or inject_result replaces lines containing an extmark,
--- Neovim pushes that extmark to the start of the replacement range, which may be
--- a different tool's header. This function uses the AST to find each tool_result's
--- actual position and moves the extmark there.
---@param bufnr integer
function M.reposition_tool_indicators(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local doc = parser.get_parsed_document(bufnr)
  local siblings = ast.build_tool_sibling_table(doc)

  local indicators = indicators_for(bufnr)
  for tool_id, ind in pairs(indicators) do
    local sibling = siblings[tool_id]
    local target_line = sibling and sibling.result and (sibling.result.position.start_line - 1) or nil
    if target_line then
      local current_line = get_extmark_line(bufnr, ind.extmark_id)
      if current_line and current_line ~= target_line then
        -- Read current virtual text to preserve it during repositioning
        local ok, pos =
          pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, tool_exec_ns, ind.extmark_id, { details = true })
        if ok and pos and #pos >= 3 then
          pcall(vim.api.nvim_buf_set_extmark, bufnr, tool_exec_ns, target_line, 0, {
            id = ind.extmark_id,
            virt_text = pos[3].virt_text,
            virt_text_pos = "eol",
            hl_mode = "combine",
            priority = PRIORITY_TOOL_EXECUTION,
            spell = false,
          })
        end
      end
    end
  end
end

--- Schedule indicator clear after a delay, or immediately on user edit
--- Uses extmark_id guard to avoid clearing a newer indicator if tool is re-executed.
--- The on_lines listener only fires when the buffer is idle (not locked by tool
--- execution and no active API request), so programmatic edits from other tool
--- completions or streaming responses won't prematurely dismiss the indicator.
---@param bufnr integer
---@param tool_id string
---@param delay_ms integer Milliseconds to wait before clearing
function M.schedule_tool_indicator_clear(bufnr, tool_id, delay_ms)
  local indicators = indicators_for(bufnr)
  local ind = indicators[tool_id]
  if not ind then
    return
  end
  local expected_extmark = ind.extmark_id
  local cleared = false

  local function do_clear()
    if cleared then
      return
    end
    local current = indicators_for(bufnr)[tool_id]
    if not current or current.extmark_id ~= expected_extmark then
      cleared = true
      return -- indicator was replaced by re-execution
    end
    cleared = true
    M.clear_tool_indicator(bufnr, tool_id)
  end

  vim.defer_fn(function()
    do_clear()
  end, delay_ms)

  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_attach(bufnr, false, {
      on_lines = function()
        -- Ignore programmatic edits: tool result injection (buffer locked) and
        -- streaming responses (active API request). Only dismiss on user edits.
        local buffer_state = state.get_buffer_state(bufnr)
        if buffer_state.locked or buffer_state.current_request then
          return
        end
        vim.schedule(function()
          do_clear()
        end)
        return true -- detach after first user edit
      end,
    })
  end
end

--- Clear all tool indicators for a buffer (used on buffer cleanup)
---@param bufnr integer
function M.clear_all_tool_indicators(bufnr)
  local indicators = indicators_for(bufnr)
  local to_clear = {}
  for tool_id in pairs(indicators) do
    table.insert(to_clear, tool_id)
  end

  for _, tool_id in ipairs(to_clear) do
    M.clear_tool_indicator(bufnr, tool_id)
  end

  -- Also clear the namespace for this buffer
  if vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, tool_exec_ns, 0, -1)
  end
end

return M
