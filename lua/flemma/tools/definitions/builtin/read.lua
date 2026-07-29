--- Read file tool definition
--- Read file contents with offset/limit and head truncation
--- Ported from pi by Mario Zechner (https://github.com/badlogic/pi-mono)
--- Original: MIT License, Copyright (c) 2025 Mario Zechner
---@class flemma.tools.definitions.builtin.Read
---@field definitions flemma.tools.ToolDefinition[]
local M = {}

-- Module-level require for description constants only (evaluated at load time).
-- Runtime code inside execute() must use ctx.truncate instead.
local messages = require("flemma.messages")
local s = require("flemma.schema")
local truncate = require("flemma.utilities.truncate")
local mime = require("flemma.mime")
local encoding = require("flemma.utilities.encoding")

M.definitions = {
  {
    name = "read",
    description = messages["tool.read.description"]{
      max_lines = truncate.MAX_LINES,
      max_bytes_kb = math.floor(truncate.MAX_BYTES / 1024),
    },
    strict = true,
    input_schema = s.object({
      label = s.string():describe(messages["tool.read.input.label"]),
      path = s.string():describe(messages["tool.read.input.path"]),
      offset = s.number():nullable():describe(messages["tool.read.input.offset"]),
      limit = s.number():nullable():describe(messages["tool.read.input.limit"]),
    }):strict(),
    personalities = {
      ["coding-assistant"] = {
        snippet = messages["tool.read.personality.snippet"]{},
        guidelines = messages["tool.read.personality.guidelines"]{},
      },
    },
    async = false,
    capabilities = { "emits_template" },
    ---@return flemma.tools.ToolPreview
    format_preview = function(input)
      local detail_parts = { input.path }
      if input.offset or input.limit then
        local offset = input.offset or 0
        local range = "+" .. offset
        if input.limit then
          range = range .. "," .. input.limit
        end
        table.insert(detail_parts, range)
      end
      return {
        label = input.label,
        detail = detail_parts,
      }
    end,
    execute = function(input, ctx)
      local path = input.path
      if not path or path == "" then
        return { success = false, error = messages["tool.error.no_path"]{} }
      end

      -- Resolve relative paths against buffer's directory, falling back to cwd
      path = ctx.path.resolve(path)

      -- Check file exists and is readable
      if vim.fn.filereadable(path) ~= 1 then
        return { success = false, error = messages["tool.error.file_not_found"]{ path = input.path } }
      end

      -- Check for binary content — emit a file reference instead of raw bytes
      local mime_type = mime.detect(path)
      if mime_type and mime.is_binary(mime_type) then
        local ref_path = input.path
        if vim.startswith(ref_path, "/") then
          -- Absolute paths use the @// convention (// signals absolute)
          ref_path = "/" .. ref_path
        elseif not vim.startswith(ref_path, "~/") and not ref_path:match("^%.%.?/") then
          -- Other relative paths get ./ prefix for the preprocessor pattern
          -- (~/ paths are emitted as-is; the preprocessor handles @~/ references)
          ref_path = "./" .. ref_path
        end
        ref_path = encoding.url_encode_subset(ref_path)
        return {
          success = true,
          output = "@" .. ref_path .. ";type=" .. mime_type,
        }
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
          error = messages["tool.read.offset_beyond_eof"]{ offset = start_line, total = total_file_lines },
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
        output_text = messages["tool.read.line_exceeds_limit"]{
          line = start_line,
          size = first_line_size,
          limit = ctx.truncate.format_size(ctx.truncate.MAX_BYTES),
          path = input.path,
          bytes = ctx.truncate.MAX_BYTES,
        }
      elseif result.truncated then
        local end_line_display = start_line + result.output_lines - 1
        local next_offset = end_line_display + 1

        output_text = result.content

        if result.truncated_by == "lines" then
          output_text = output_text
            .. "\n\n"
            .. messages["tool.read.truncated_lines"]{
              start = start_line,
              end_line = end_line_display,
              total = total_file_lines,
              next_offset = next_offset,
            }
        else
          output_text = output_text
            .. "\n\n"
            .. messages["tool.read.truncated_bytes"]{
              start = start_line,
              end_line = end_line_display,
              total = total_file_lines,
              limit = ctx.truncate.format_size(ctx.truncate.MAX_BYTES),
              next_offset = next_offset,
            }
        end
      elseif user_limited_count and (start_line + user_limited_count - 1) < total_file_lines then
        -- User specified limit, there's more content, but no truncation
        local remaining = total_file_lines - (start_line + user_limited_count - 1)
        local next_offset = start_line + user_limited_count

        output_text = result.content
        output_text = output_text
          .. "\n\n"
          .. messages["tool.read.more_lines"]{ count = remaining, next_offset = next_offset }
      else
        output_text = result.content
      end

      return { success = true, output = output_text }
    end,
  },
}

return M
