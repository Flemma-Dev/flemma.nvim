--- Write file tool definition
--- Write/create files with automatic parent directory creation
--- Ported from pi by Mario Zechner (https://github.com/badlogic/pi-mono)
--- Original: MIT License, Copyright (c) 2025 Mario Zechner
---@class flemma.tools.definitions.Write
---@field definitions flemma.tools.ToolDefinition[]
local M = {}

M.definitions = {
  {
    name = "write",
    description = "Write content to a file. "
      .. "Creates the file if it doesn't exist, overwrites if it does. "
      .. "Automatically creates parent directories.",
    strict = true,
    input_schema = {
      type = "object",
      properties = {
        label = {
          type = "string",
          description = "A short human-readable label for this operation (e.g., 'creating config.lua')",
        },
        path = {
          type = "string",
          description = "Path to the file to write (relative or absolute)",
        },
        content = {
          type = "string",
          description = "Content to write to the file",
        },
      },
      required = { "label", "path", "content" },
      additionalProperties = false,
    },
    async = false,
    format_preview = function(input)
      local size = #input.content
      local display
      if size < 1024 then
        display = size .. " B"
      else
        display = string.format("%.1f KB", size / 1024)
      end
      local parts = { input.path, "(" .. display .. ")" }
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
      if input.content == nil then
        return { success = false, error = "No content provided" }
      end

      -- Resolve relative paths against buffer's directory, falling back to cwd
      path = ctx.path.resolve(path)

      -- Sandbox: refuse writes outside writable paths
      if not ctx.sandbox.is_path_writable(path) then
        return {
          success = false,
          error = "Sandbox: write denied – path is outside writable directories: " .. input.path,
        }
      end

      -- Create parent directories
      local parent = vim.fn.fnamemodify(path, ":h")
      vim.fn.mkdir(parent, "p")

      -- Write the file
      local f, err = io.open(path, "w")
      if not f then
        return { success = false, error = "Cannot write file: " .. (err or "unknown error") }
      end
      f:write(input.content)
      f:close()

      return {
        success = true,
        output = string.format("Successfully wrote %d bytes to %s", #input.content, input.path),
      }
    end,
  },
}

return M
