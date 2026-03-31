--- Ls tool definition
--- List directory contents with configurable depth and entry limit
---@class flemma.tools.definitions.Ls
---@field definitions flemma.tools.ToolDefinition[]
local M = {}

-- Module-level require for description constants only (evaluated at load time).
-- Runtime code inside execute() must use ctx.truncate instead.
local s = require("flemma.schema")
local truncate = require("flemma.utilities.truncate")

---Maximum recursion depth allowed
local MAX_DEPTH = 10

---Default entry limit
local DEFAULT_LIMIT = 500

---Resolve a path against the working directory.
---Absolute paths pass through; relative paths are prepended with cwd.
---@param path string The input path
---@param cwd string The working directory
---@return string resolved_path
local function resolve_path(path, cwd)
  if vim.startswith(path, "/") then
    return path
  end
  return cwd .. "/" .. path
end

---Collect directory entries up to a limit, sorting directories first then files.
---Breaks out of iteration early when the limit is reached.
---@param path string Absolute directory path
---@param depth integer Maximum recursion depth
---@param limit integer Maximum number of entries to collect
---@return string[] entries Sorted list of entries (dirs suffixed with "/")
local function collect_entries(path, depth, limit)
  ---@type string[]
  local directories = {}
  ---@type string[]
  local files = {}
  local count = 0

  for name, entry_type in vim.fs.dir(path, { depth = depth }) do
    if count >= limit then
      break
    end

    local is_directory = entry_type == "directory"

    -- Symlinks: check if they point to a directory
    if entry_type == "link" then
      is_directory = vim.fn.isdirectory(path .. "/" .. name) == 1
    end

    if is_directory then
      table.insert(directories, name .. "/")
    else
      table.insert(files, name)
    end

    count = count + 1
  end

  table.sort(directories, function(a, b)
    return a:lower() < b:lower()
  end)
  table.sort(files, function(a, b)
    return a:lower() < b:lower()
  end)

  ---@type string[]
  local entries = {}
  for _, entry in ipairs(directories) do
    table.insert(entries, entry)
  end
  for _, entry in ipairs(files) do
    table.insert(entries, entry)
  end

  return entries
end

M.definitions = {
  {
    name = "ls",
    metadata = {
      config_schema = s.object({
        cwd = s.optional(s.string("urn:flemma:buffer:path")),
      }),
    },
    enabled = function(config)
      return not not (config and config.experimental and config.experimental.tools)
    end,
    description = "List directory contents. Output is truncated to "
      .. truncate.MAX_LINES
      .. " lines or "
      .. math.floor(truncate.MAX_BYTES / 1024)
      .. "KB. "
      .. "Directories appear first (suffixed with /), then files, both sorted case-insensitively. "
      .. "Use max_depth > 1 to recurse into subdirectories (max 10). "
      .. "Use limit to cap the number of entries (default "
      .. DEFAULT_LIMIT
      .. ").",
    strict = true,
    input_schema = s.object({
      label = s.string():describe("A short human-readable label for this operation (e.g., 'listing project root')"),
      path = s.string():describe("Directory path to list (relative or absolute)"),
      max_depth = s.number():nullable():describe("Maximum recursion depth (default: 1, max: 10)"),
      limit = s.number():nullable():describe("Maximum number of entries (default: 500)"),
    }):strict(),
    personalities = {
      ["coding-assistant"] = {
        snippet = "List directory contents with optional depth and entry limit",
        guidelines = {
          "Use ls to explore project structure before reading individual files",
          "Prefer max_depth=1 for broad overviews, increase depth for targeted exploration",
        },
      },
    },
    async = false,
    ---@return flemma.tools.ToolPreview
    format_preview = function(input)
      local detail_parts = { input.path }
      if input.max_depth and input.max_depth > 1 then
        table.insert(detail_parts, "depth=" .. input.max_depth)
      end
      return {
        label = input.label,
        detail = detail_parts,
      }
    end,
    ---@param input table<string, any>
    ---@param ctx flemma.tools.ExecutionContext
    ---@return flemma.tools.ExecutionResult
    execute = function(input, ctx)
      local path = input.path
      if not path or path == "" then
        return { success = false, error = "No path provided" }
      end

      -- Resolve relative paths against cwd (not __dirname)
      path = resolve_path(path, ctx.cwd)

      -- Validate directory exists
      if vim.fn.isdirectory(path) ~= 1 then
        return { success = false, error = "Directory not found: " .. input.path }
      end

      local depth = math.min(input.max_depth or 1, MAX_DEPTH)
      local limit = input.limit or DEFAULT_LIMIT

      local entries = collect_entries(path, depth, limit)
      local entry_count = #entries

      local content = table.concat(entries, "\n")

      -- Apply head truncation
      local result = ctx.truncate.truncate_head(content)

      -- Build summary footer
      local footer
      if depth > 1 then
        footer = string.format("[%d entries, depth=%d]", entry_count, depth)
      else
        footer = string.format("[%d entries]", entry_count)
      end

      local output_text
      if result.truncated then
        output_text = result.content .. "\n\n" .. footer
      else
        output_text = content .. "\n\n" .. footer
      end

      return { success = true, output = output_text }
    end,
  },
}

return M
