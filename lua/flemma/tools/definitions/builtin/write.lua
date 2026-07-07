--- Write file tool definition
--- Write/create files with automatic parent directory creation
--- Ported from pi by Mario Zechner (https://github.com/badlogic/pi-mono)
--- Original: MIT License, Copyright (c) 2025 Mario Zechner
local messages = require("flemma.messages")
local path_util = require("flemma.utilities.path")
local s = require("flemma.schema")
local str = require("flemma.utilities.string")

---@class flemma.tools.definitions.builtin.Write
---@field definitions flemma.tools.ToolDefinition[]
local M = {}

M.definitions = {
  {
    name = "write",
    description = messages["tool.write.description"]{},
    strict = true,
    input_schema = s.object({
      label = s.string():describe(messages["tool.write.input.label"]),
      path = s.string():describe(messages["tool.write.input.path"]),
      content = s.string():describe(messages["tool.write.input.content"]),
    }):strict(),
    personalities = {
      ["coding-assistant"] = {
        snippet = messages["tool.write.personality.snippet"]{},
        guidelines = messages["tool.write.personality.guidelines"]{},
      },
    },
    async = false,
    ---@return flemma.tools.ToolPreview
    format_preview = function(input)
      return {
        label = input.label,
        detail = { input.path, "(" .. str.format_size(#input.content) .. ")" },
      }
    end,
    execute = function(input, ctx)
      local path = input.path
      if not path or path == "" then
        return { success = false, error = messages["tool.error.no_path"]{} }
      end
      if input.content == nil then
        return { success = false, error = messages["tool.write.error.no_content"]{} }
      end

      -- Resolve relative paths against buffer's directory, falling back to cwd
      path = ctx.path.resolve(path)

      -- Sandbox: refuse writes outside writable paths
      if not ctx.sandbox.is_path_writable(path) then
        return {
          success = false,
          error = messages["tool.write.error.sandbox_denied"]{ path = input.path },
        }
      end

      -- Create parent directories
      local parent = path_util.dirname(path)
      vim.fn.mkdir(parent, "p")

      -- Write the file
      local f, err = io.open(path, "w")
      if not f then
        return { success = false, error = messages["tool.error.write_failed"]{ detail = err or "unknown error" } }
      end
      f:write(input.content)
      f:close()

      return {
        success = true,
        output = messages["tool.write.success"]{ count = #input.content, path = input.path },
      }
    end,
  },
}

return M
