--- Edit file tool definition
--- Find-and-replace exact text in files
--- Ported from pi by Mario Zechner (https://github.com/badlogic/pi-mono)
--- Original: MIT License, Copyright (c) 2025 Mario Zechner
---@class flemma.tools.definitions.Edit
---@field definitions flemma.tools.ToolDefinition[]
local M = {}

M.definitions = {
  {
    name = "edit",
    description = "Edit a file by replacing exact text. "
      .. "The oldText must match exactly (including whitespace). "
      .. "Use this for precise, surgical edits.",
    strict = true,
    input_schema = {
      type = "object",
      properties = {
        label = {
          type = "string",
          description = "A short human-readable label for this operation (e.g., 'fixing typo in config.lua')",
        },
        path = {
          type = "string",
          description = "Path to the file to edit (relative or absolute)",
        },
        oldText = {
          type = "string",
          description = "Exact text to find and replace (must match exactly)",
        },
        newText = {
          type = "string",
          description = "New text to replace the old text with",
        },
      },
      required = { "label", "path", "oldText", "newText" },
      additionalProperties = false,
    },
    async = false,
    execute = function(input)
      local path = input.path
      if not path or path == "" then
        return { success = false, error = "No path provided" }
      end
      if not input.oldText or input.oldText == "" then
        return { success = false, error = "No oldText provided" }
      end
      if input.newText == nil then
        return { success = false, error = "No newText provided" }
      end

      -- Resolve relative paths against cwd
      if not vim.startswith(path, "/") then
        path = vim.fn.getcwd() .. "/" .. path
      end

      -- Check file exists
      if vim.fn.filereadable(path) ~= 1 then
        return { success = false, error = "File not found: " .. input.path }
      end

      -- Read file content
      local f, err = io.open(path, "r")
      if not f then
        return { success = false, error = "Cannot read file: " .. (err or "unknown error") }
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
          error = "Could not find the exact text in "
            .. input.path
            .. ". The old text must match exactly including all whitespace and newlines.",
        }
      end

      if count > 1 then
        return {
          success = false,
          error = string.format(
            "Found %d occurrences of the text in %s. The text must be unique. "
              .. "Please provide more context to make it unique.",
            count,
            input.path
          ),
        }
      end

      -- Perform single replacement
      local pos = string.find(content, old_text, 1, true) --[[@as integer]]
      local new_content = content:sub(1, pos - 1) .. new_text .. content:sub(pos + #old_text)

      -- Verify the replacement actually changed something
      if content == new_content then
        return {
          success = false,
          error = "No changes made to " .. input.path .. ". The replacement produced identical content.",
        }
      end

      -- Write back
      local wf, werr = io.open(path, "w")
      if not wf then
        return { success = false, error = "Cannot write file: " .. (werr or "unknown error") }
      end
      wf:write(new_content)
      wf:close()

      return { success = true, output = "Successfully replaced text in " .. input.path .. "." }
    end,
  },
}

return M
