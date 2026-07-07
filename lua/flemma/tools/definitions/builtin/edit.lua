--- Edit file tool definition
--- Find-and-replace exact text in files
--- Ported from pi by Mario Zechner (https://github.com/badlogic/pi-mono)
--- Original: MIT License, Copyright (c) 2025 Mario Zechner
local messages = require("flemma.messages")
local s = require("flemma.schema")

---@class flemma.tools.definitions.builtin.Edit
---@field definitions flemma.tools.ToolDefinition[]
local M = {}

M.definitions = {
  {
    name = "edit",
    description = messages["tool.edit.description"]{},
    strict = true,
    input_schema = s.object({
      label = s.string():describe(messages["tool.edit.input.label"]),
      path = s.string():describe(messages["tool.edit.input.path"]),
      oldText = s.string():describe(messages["tool.edit.input.oldText"]),
      newText = s.string():describe(messages["tool.edit.input.newText"]),
    }):strict(),
    personalities = {
      ["coding-assistant"] = {
        snippet = "Make surgical edits to files (find exact text and replace)",
        guidelines = {
          "Use edit for precise, targeted changes — old text must match exactly",
          "Use write only for new files or complete rewrites, not for modifications",
        },
      },
    },
    async = false,
    ---@return flemma.tools.ToolPreview
    format_preview = function(input)
      return {
        label = input.label,
        detail = input.path,
      }
    end,
    execute = function(input, ctx)
      local path = input.path
      if not path or path == "" then
        return { success = false, error = messages["tool.error.no_path"]{} }
      end
      if not input.oldText or input.oldText == "" then
        return { success = false, error = messages["tool.edit.error.no_old_text"]{} }
      end
      if input.newText == nil then
        return { success = false, error = messages["tool.edit.error.no_new_text"]{} }
      end

      -- Resolve relative paths against buffer's directory, falling back to cwd
      path = ctx.path.resolve(path)

      -- Sandbox: refuse edits to files outside writable paths
      if not ctx.sandbox.is_path_writable(path) then
        return {
          success = false,
          error = messages["tool.edit.error.sandbox_denied"]{ path = input.path },
        }
      end

      -- Check file exists
      if vim.fn.filereadable(path) ~= 1 then
        return { success = false, error = messages["tool.error.file_not_found"]{ path = input.path } }
      end

      -- Read file content
      local f, err = io.open(path, "r")
      if not f then
        return { success = false, error = messages["tool.edit.error.read_failed"]{ detail = err or "unknown error" } }
      end
      local content = f:read("*a")
      f:close()

      local old_text = input.oldText
      local new_text = input.newText

      -- Count occurrences using plain string.find
      local count = 0
      local search_pos = 1
      while true do
        local found = string.find(content, old_text, search_pos, true)
        if not found then
          break
        end
        count = count + 1
        search_pos = found + 1
      end

      if count == 0 then
        return {
          success = false,
          error = messages["tool.edit.error.text_not_found"]{ path = input.path },
        }
      end

      if count > 1 then
        return {
          success = false,
          error = messages["tool.edit.error.not_unique"]{ count = count, path = input.path },
        }
      end

      -- Perform single replacement
      local pos = string.find(content, old_text, 1, true) --[[@as integer]]
      local new_content = content:sub(1, pos - 1) .. new_text .. content:sub(pos + #old_text)

      -- Verify the replacement actually changed something
      if content == new_content then
        return {
          success = false,
          error = messages["tool.edit.error.no_changes"]{ path = input.path },
        }
      end

      -- Write back
      local wf, werr = io.open(path, "w")
      if not wf then
        return { success = false, error = messages["tool.error.write_failed"]{ detail = werr or "unknown error" } }
      end
      wf:write(new_content)
      wf:close()

      return { success = true, output = messages["tool.edit.output.success"]{ path = input.path } }
    end,
  },
}

return M
