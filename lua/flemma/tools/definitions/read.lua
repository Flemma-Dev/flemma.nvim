--- Read file tool definition
--- Read file contents with offset/limit and head truncation
--- Ported from pi by Mario Zechner (https://github.com/badlogic/pi-mono)
--- Original: MIT License, Copyright (c) 2025 Mario Zechner
---@class flemma.tools.definitions.Read
---@field definitions flemma.tools.ToolDefinition[]
local M = {}

-- Module-level require for description constants only (evaluated at load time).
-- Runtime code inside execute() must use ctx.truncate instead.
local truncate = require("flemma.tools.truncate")

M.definitions = {
  {
    name = "read",
    description = "Read the contents of a file. Output is truncated to "
      .. truncate.MAX_LINES
      .. " lines or "
      .. math.floor(truncate.MAX_BYTES / 1024)
      .. "KB (whichever is hit first). "
      .. "Use offset/limit for large files. When you need the full file, continue with offset until complete.",
    strict = true,
    input_schema = {
      type = "object",
      properties = {
        label = {
          type = "string",
          description = "A short human-readable label for this operation (e.g., 'reading config.lua')",
        },
        path = {
          type = "string",
          description = "Path to the file to read (relative or absolute)",
        },
        offset = {
          type = { "number", "null" },
          description = "Line number to start reading from (1-indexed)",
        },
        limit = {
          type = { "number", "null" },
          description = "Maximum number of lines to read",
        },
      },
      required = { "label", "path", "offset", "limit" },
      additionalProperties = false,
    },
    async = false,
    format_preview = function(input)
      local parts = { input.path }
      if input.offset or input.limit then
        local offset = input.offset or 0
        local range = "+" .. offset
        if input.limit then
          range = range .. "," .. input.limit
        end
        table.insert(parts, range)
      end
      if input.label then
        table.insert(parts, "# " .. input.label)
      end
      return table.concat(parts, "  ")
    end,
    execute = function(input, _, ctx)
      local path = input.path
      if not path or path == "" then
        return { success = false, error = "No path provided" }
      end

      -- Resolve relative paths against buffer's directory, falling back to cwd
      path = ctx.path.resolve(path)

      -- Check file exists and is readable
      if vim.fn.filereadable(path) ~= 1 then
        return { success = false, error = "File not found: " .. input.path }
      end

      -- Read file lines
      local all_lines = vim.fn.readfile(path)
      local total_file_lines = #all_lines

      -- Apply offset (1-indexed)
      local start_line = 1
      if input.offset then
        start_line = math.max(1, math.floor(input.offset))
      end

      if start_line > total_file_lines then
        return {
          success = false,
          error = string.format("Offset %d is beyond end of file (%d lines total)", start_line, total_file_lines),
        }
      end

      -- Apply user limit if specified
      local selected_lines
      local user_limited_count
      if input.limit then
        local limit = math.max(1, math.floor(input.limit))
        local end_line = math.min(start_line + limit - 1, total_file_lines)
        selected_lines = vim.list_slice(all_lines, start_line, end_line)
        user_limited_count = end_line - start_line + 1
      else
        selected_lines = vim.list_slice(all_lines, start_line)
      end

      local selected_content = table.concat(selected_lines, "\n")

      -- Apply head truncation
      local result = ctx.truncate.truncate_head(selected_content)

      local output_text

      if result.first_line_exceeds_limit then
        -- First line at offset exceeds limit
        local first_line_size = ctx.truncate.format_size(#all_lines[start_line])
        output_text = string.format(
          "[Line %d is %s, exceeds %s limit. Use bash: sed -n '%dp' %s | head -c %d]",
          start_line,
          first_line_size,
          ctx.truncate.format_size(ctx.truncate.MAX_BYTES),
          start_line,
          input.path,
          ctx.truncate.MAX_BYTES
        )
      elseif result.truncated then
        local end_line_display = start_line + result.output_lines - 1
        local next_offset = end_line_display + 1

        output_text = result.content

        if result.truncated_by == "lines" then
          output_text = output_text
            .. string.format(
              "\n\n[Showing lines %d-%d of %d. Use offset=%d to continue.]",
              start_line,
              end_line_display,
              total_file_lines,
              next_offset
            )
        else
          output_text = output_text
            .. string.format(
              "\n\n[Showing lines %d-%d of %d (%s limit). Use offset=%d to continue.]",
              start_line,
              end_line_display,
              total_file_lines,
              ctx.truncate.format_size(ctx.truncate.MAX_BYTES),
              next_offset
            )
        end
      elseif user_limited_count and (start_line + user_limited_count - 1) < total_file_lines then
        -- User specified limit, there's more content, but no truncation
        local remaining = total_file_lines - (start_line + user_limited_count - 1)
        local next_offset = start_line + user_limited_count

        output_text = result.content
        output_text = output_text
          .. string.format("\n\n[%d more lines in file. Use offset=%d to continue.]", remaining, next_offset)
      else
        output_text = result.content
      end

      return { success = true, output = output_text }
    end,
  },
}

return M
