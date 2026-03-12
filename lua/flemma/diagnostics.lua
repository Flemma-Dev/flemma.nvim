--- Diagnostics mode for debugging prompt caching issues
--- Compares consecutive API requests per buffer and reports prefix divergences
---@class flemma.Diagnostics
local M = {}

local json = require("flemma.utilities.json")
local state = require("flemma.state")

local INDENT = "  "

---Pretty-print a raw JSON string preserving original key ordering.
---Walks the string character by character, tracking string state and escapes.
---@param raw_json string The raw JSON string to format
---@return string formatted The pretty-printed JSON
function M.pretty_print_raw(raw_json)
  if raw_json == "" then
    return ""
  end

  local result = {}
  local depth = 0
  local in_string = false
  local i = 1
  local len = #raw_json

  while i <= len do
    local char = raw_json:sub(i, i)

    if in_string then
      table.insert(result, char)
      if char == "\\" then
        -- Skip the next character (escaped)
        i = i + 1
        if i <= len then
          table.insert(result, raw_json:sub(i, i))
        end
      elseif char == '"' then
        in_string = false
      end
    else
      if char == '"' then
        in_string = true
        table.insert(result, char)
      elseif char == "{" or char == "[" then
        -- Look ahead to check for empty container
        local next_char = nil
        local j = i + 1
        while j <= len do
          local c = raw_json:sub(j, j)
          if c ~= " " and c ~= "\t" and c ~= "\n" and c ~= "\r" then
            next_char = c
            break
          end
          j = j + 1
        end
        local close = char == "{" and "}" or "]"
        if next_char == close then
          -- Empty container — emit on one line
          table.insert(result, char)
          table.insert(result, close)
          i = j -- skip to the closing char (loop increment will advance past it)
        else
          table.insert(result, char)
          depth = depth + 1
          table.insert(result, "\n")
          table.insert(result, INDENT:rep(depth))
        end
      elseif char == "}" or char == "]" then
        depth = depth - 1
        table.insert(result, "\n")
        table.insert(result, INDENT:rep(depth))
        table.insert(result, char)
      elseif char == "," then
        table.insert(result, ",")
        table.insert(result, "\n")
        table.insert(result, INDENT:rep(depth))
      elseif char == ":" then
        table.insert(result, ": ")
      elseif char ~= " " and char ~= "\t" and char ~= "\n" and char ~= "\r" then
        -- Literal characters (digits, letters for true/false/null, minus, dot)
        table.insert(result, char)
      end
    end

    i = i + 1
  end

  return table.concat(result)
end

---Recursively encode a Lua value to pretty-printed JSON with sorted keys.
---@param value any The Lua value to encode
---@param depth integer Current indentation depth
---@return string
local function encode_sorted(value, depth)
  local value_type = type(value)

  if value_type == "string" then
    return vim.json.encode(value)
  elseif value_type == "number" then
    -- Use vim.json.encode for consistent number formatting
    return vim.json.encode(value)
  elseif value_type == "boolean" then
    return value and "true" or "false"
  elseif value_type == "nil" then
    return "null"
  elseif value_type == "table" then
    -- Check if this is an array (sequential integer keys starting at 1)
    local is_array = vim.islist(value)

    if is_array then
      if #value == 0 then
        return "[]"
      end
      local items = {}
      for _, item in ipairs(value) do
        table.insert(items, INDENT:rep(depth + 1) .. encode_sorted(item, depth + 1))
      end
      return "[\n" .. table.concat(items, ",\n") .. "\n" .. INDENT:rep(depth) .. "]"
    else
      -- Object — sort keys
      local keys = {}
      for k in pairs(value) do
        table.insert(keys, k)
      end
      if #keys == 0 then
        return "{}"
      end
      table.sort(keys)
      local items = {}
      for _, k in ipairs(keys) do
        local encoded_key = vim.json.encode(k)
        local encoded_value = encode_sorted(value[k], depth + 1)
        table.insert(items, INDENT:rep(depth + 1) .. encoded_key .. ": " .. encoded_value)
      end
      return "{\n" .. table.concat(items, ",\n") .. "\n" .. INDENT:rep(depth) .. "}"
    end
  end

  -- Fallback for unexpected types
  return tostring(value)
end

---Pretty-print a JSON string with keys sorted alphabetically at every level.
---Decodes the JSON, then re-encodes with sorted keys for deterministic output.
---@param raw_json string The raw JSON string to normalize
---@return string formatted The normalized, pretty-printed JSON
function M.pretty_print_normalized(raw_json)
  if raw_json == "" then
    return ""
  end
  local decoded = json.decode(raw_json)
  return encode_sorted(decoded, 0)
end

---@class flemma.diagnostics.Divergence
---@field byte_offset integer 1-indexed byte position where the prefix diverges
---@field previous_char string The character in the previous request at the divergence point
---@field current_char string The character in the current request at the divergence point

---Compare two raw JSON request strings and find where the prefix diverges.
---Returns nil if the prefix is intact (current extends or equals previous).
---@param previous string|nil The previous request JSON
---@param current string The current request JSON
---@return flemma.diagnostics.Divergence|nil divergence Nil means prefix is intact
function M.find_prefix_divergence(previous, current)
  if not previous then
    return nil
  end

  local min_len = math.min(#previous, #current)

  for i = 1, min_len do
    local prev_byte = previous:byte(i)
    local curr_byte = current:byte(i)
    if prev_byte ~= curr_byte then
      return {
        byte_offset = i,
        previous_char = previous:sub(i, i),
        current_char = current:sub(i, i),
      }
    end
  end

  -- If we got through all shared bytes, check if the current is shorter
  if #current < #previous then
    return {
      byte_offset = #current + 1,
      previous_char = previous:sub(#current + 1, #current + 1),
      current_char = "",
    }
  end

  -- Prefix intact — current extends or equals previous
  return nil
end

---Compare two Lua values recursively, returning a list of human-readable change descriptions.
---@param old any
---@param new any
---@param path string Current path (e.g., "messages[2].content")
---@param changes string[] Accumulator for change descriptions
local function diff_values(old, new, path, changes)
  if type(old) ~= type(new) then
    table.insert(changes, path .. " type changed: " .. type(old) .. " → " .. type(new))
    return
  end

  if type(old) ~= "table" then
    if old ~= new then
      local old_str = tostring(old)
      local new_str = tostring(new)
      -- Truncate long values
      if #old_str > 40 then
        old_str = old_str:sub(1, 37) .. "..."
      end
      if #new_str > 40 then
        new_str = new_str:sub(1, 37) .. "..."
      end
      table.insert(changes, path .. " changed: " .. old_str .. " → " .. new_str)
    end
    return
  end

  local is_old_array = vim.islist(old)
  local is_new_array = vim.islist(new)

  if is_old_array and is_new_array then
    -- Array comparison
    local min_len = math.min(#old, #new)
    for i = 1, min_len do
      diff_values(old[i], new[i], path .. "[" .. i .. "]", changes)
    end
    if #new > #old then
      table.insert(changes, path .. ": " .. (#new - #old) .. " items appended")
    elseif #new < #old then
      table.insert(changes, path .. ": " .. (#old - #new) .. " items removed from end")
    end
  else
    -- Object comparison
    local all_keys = {}
    local seen = {}
    for k in pairs(old) do
      if not seen[k] then
        table.insert(all_keys, k)
        seen[k] = true
      end
    end
    for k in pairs(new) do
      if not seen[k] then
        table.insert(all_keys, k)
        seen[k] = true
      end
    end
    table.sort(all_keys)

    for _, k in ipairs(all_keys) do
      local child_path = path ~= "" and (path .. "." .. tostring(k)) or tostring(k)
      if old[k] == nil then
        table.insert(changes, child_path .. " added")
      elseif new[k] == nil then
        table.insert(changes, child_path .. " removed")
      else
        diff_values(old[k], new[k], child_path, changes)
      end
    end
  end
end

---Analyze structural changes between two JSON request strings.
---Returns a list of human-readable change descriptions, or nil if previous is nil.
---@param previous string|nil
---@param current string
---@return string[]|nil changes List of change descriptions, or nil for first request
function M.analyze_structural_changes(previous, current)
  if not previous then
    return nil
  end

  local old = json.decode(previous)
  local new = json.decode(current)
  local changes = {}

  diff_values(old, new, "", changes)

  return changes
end

---Map a byte offset in a raw JSON string to a best-effort structural path.
---Walks the JSON up to the target byte, tracking the current key/index context.
---@param raw_json string
---@param byte_offset integer 1-indexed byte position
---@return string path Human-readable path like "messages[2].content"
function M.map_byte_to_path(raw_json, byte_offset)
  local path_stack = {} ---@type {type: string, key: string|nil, index: integer|nil}[]
  local in_string = false
  local current_key = nil
  local expecting_key = false
  local expecting_value = false
  local key_buffer = {}
  local collecting_key = false

  local i = 1
  local limit = math.min(byte_offset, #raw_json)
  while i <= limit do
    local char = raw_json:sub(i, i)

    if in_string then
      if char == "\\" then
        if collecting_key then
          table.insert(key_buffer, char)
          if i + 1 <= #raw_json then
            table.insert(key_buffer, raw_json:sub(i + 1, i + 1))
          end
        end
        -- Skip the escaped character
        i = i + 1
      elseif char == '"' then
        in_string = false
        if collecting_key then
          current_key = table.concat(key_buffer)
          key_buffer = {}
          collecting_key = false
        end
      else
        if collecting_key then
          table.insert(key_buffer, char)
        end
      end
    else
      if char == '"' then
        in_string = true
        if expecting_key or (#path_stack > 0 and path_stack[#path_stack].type == "object" and not expecting_value) then
          collecting_key = true
          key_buffer = {}
        end
        expecting_key = false
      elseif char == "{" then
        table.insert(path_stack, { type = "object", key = current_key })
        current_key = nil
        expecting_key = true
        expecting_value = false
      elseif char == "[" then
        table.insert(path_stack, { type = "array", key = current_key, index = 1 })
        current_key = nil
        expecting_value = false
      elseif char == "}" or char == "]" then
        table.remove(path_stack)
        expecting_value = false
      elseif char == ":" then
        expecting_value = true
      elseif char == "," then
        expecting_value = false
        if #path_stack > 0 then
          local top = path_stack[#path_stack]
          if top.type == "array" then
            top.index = (top.index or 1) + 1
          elseif top.type == "object" then
            expecting_key = true
          end
        end
      end
    end

    i = i + 1
  end

  -- Build path from stack
  if #path_stack == 0 then
    return "$"
  end

  local parts = {}
  for _, frame in ipairs(path_stack) do
    if frame.key then
      table.insert(parts, frame.key)
    end
    if frame.type == "array" and frame.index then
      parts[#parts] = (parts[#parts] or "$") .. "[" .. frame.index .. "]"
    end
  end
  if current_key then
    table.insert(parts, current_key)
  end

  if #parts == 0 then
    return "$"
  end

  return table.concat(parts, ".")
end

---Open a side-by-side diff view of the last two requests for a buffer.
---@param bufnr integer The source buffer number
---@param normalized boolean Whether to use sorted-key normalization
function M.open_diff(bufnr, normalized)
  local buffer_state = state.get_buffer_state(bufnr)
  local previous = buffer_state.diagnostics_previous_request
  local current = buffer_state.diagnostics_current_request

  if not current then
    vim.notify(
      "Flemma: No request data available. Send at least one request with diagnostics enabled.",
      vim.log.levels.WARN
    )
    return
  end

  if not previous then
    vim.notify("Flemma: Only one request recorded. Send another request to compare.", vim.log.levels.WARN)
    return
  end

  local format_fn = normalized and M.pretty_print_normalized or M.pretty_print_raw
  local previous_formatted = format_fn(previous)
  local current_formatted = format_fn(current)

  local prev_lines = vim.split(previous_formatted, "\n", { plain = true })
  local curr_lines = vim.split(current_formatted, "\n", { plain = true })

  -- Create scratch buffers
  local buf_prev = vim.api.nvim_create_buf(false, true)
  local buf_curr = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_lines(buf_prev, 0, -1, false, prev_lines)
  vim.api.nvim_buf_set_lines(buf_curr, 0, -1, false, curr_lines)

  -- Configure buffers
  for _, buf in ipairs({ buf_prev, buf_curr }) do
    vim.bo[buf].filetype = "json"
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].modifiable = false
  end

  local mode_label = normalized and "normalized" or "raw"
  vim.api.nvim_buf_set_name(buf_prev, "Flemma: Previous Request (" .. mode_label .. ")")
  vim.api.nvim_buf_set_name(buf_curr, "Flemma: Current Request (" .. mode_label .. ")")

  -- Open in a new tab with diff mode
  vim.cmd("tabnew")
  vim.api.nvim_set_current_buf(buf_prev)
  vim.cmd("diffthis")
  vim.cmd("vsplit")
  vim.api.nvim_set_current_buf(buf_curr)
  vim.cmd("diffthis")
end

---Record a request and run comparison against the previous one.
---Called after each response completes when diagnostics is enabled.
---@param bufnr integer
---@param raw_json string The raw JSON request body
function M.record_and_compare(bufnr, raw_json)
  local buffer_state = state.get_buffer_state(bufnr)

  -- Rotate: current becomes previous
  buffer_state.diagnostics_previous_request = buffer_state.diagnostics_current_request
  buffer_state.diagnostics_current_request = raw_json

  local previous = buffer_state.diagnostics_previous_request
  if not previous then
    return -- First request, nothing to compare
  end

  -- Byte-level check
  local divergence = M.find_prefix_divergence(previous, raw_json)
  if not divergence then
    -- Prefix intact — good for caching
    return
  end

  -- Something changed in the prefix — build notification
  local path = M.map_byte_to_path(raw_json, divergence.byte_offset)

  -- Structural analysis for more context
  local structural_changes = M.analyze_structural_changes(previous, raw_json)
  if structural_changes and #structural_changes > 0 then
    -- Filter out append-only changes (those are expected in multi-turn conversations)
    local breaking_changes = {}
    for _, change in ipairs(structural_changes) do
      if not change:match("appended$") then
        table.insert(breaking_changes, change)
      end
    end

    if #breaking_changes == 0 then
      -- Only appends — but only safe if the divergence is at the very tail of
      -- the previous request (only closing brackets/braces remain after it).
      -- This ensures appends to mid-document keys like "tools" still warn,
      -- since substantive content (messages) follows the divergence point.
      local previous_tail = previous:sub(divergence.byte_offset)
      if previous_tail:match("^[%]%}%s]*$") then
        return
      end
    end

    -- Build notification with all changes (including appends when they're not tail-safe)
    local change_descriptions = #breaking_changes > 0 and breaking_changes or structural_changes
    vim.notify(
      "Flemma [diagnostics]: Cache break detected"
        .. "\nPrefix diverged at byte "
        .. divergence.byte_offset
        .. " (in "
        .. path
        .. ")"
        .. "\nChanges:\n  • "
        .. table.concat(change_descriptions, "\n  • ")
        .. "\n\nRun :Flemma diagnostics:diff for full diff",
      vim.log.levels.WARN
    )
  else
    -- No structural changes at all but bytes diverged — serialization non-determinism
    vim.notify(
      "Flemma [diagnostics]: Cache break detected"
        .. "\nPrefix diverged at byte "
        .. divergence.byte_offset
        .. " (in "
        .. path
        .. ")"
        .. "\nLikely cause: JSON serialization non-determinism (key ordering)"
        .. "\n\nRun :Flemma diagnostics:diff for full diff",
      vim.log.levels.WARN
    )
  end
end

return M
