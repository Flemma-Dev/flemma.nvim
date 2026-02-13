--- Flemma logging functionality
--- Provides centralized logging capabilities with custom inspect
---@class flemma.Logging
local M = {}

---@class flemma.logging.Config
---@field enabled boolean Whether logging is active
---@field path string Filesystem path for the log file

---@type flemma.logging.Config
local config = {
  enabled = false,
  path = vim.fn.stdpath("cache") .. "/flemma.log",
}

---Write a log message to the log file
---@param level string Log level label (e.g. "INFO", "ERROR")
---@param msg string The message to log
local function write_log(level, msg)
  if not config.enabled then
    return
  end

  local f = io.open(config.path, "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M:%S") .. " [" .. level .. "] " .. msg .. "\n")
    f:close()
  end
end

---Compact single-line inspect for logging, truncates long strings
---@param obj any The value to inspect
---@return string
function M.inspect(obj)
  return vim.inspect(obj, {
    newline = " ", -- Use space instead of newline
    indent = "", -- No indentation
    process = function(item)
      -- Truncate long strings
      if type(item) == "string" and #item > 1000 then
        return vim.inspect(item:sub(1, 1000) .. "...")
      end
      return item
    end,
  })
end

---Log an info message
---@param msg string
function M.info(msg)
  write_log("INFO", msg)
end

---Log an error message
---@param msg string
function M.error(msg)
  write_log("ERROR", msg)
end

---Log a debug message
---@param msg string
function M.debug(msg)
  write_log("DEBUG", msg)
end

---Log a warning message
---@param msg string
function M.warn(msg)
  write_log("WARN", msg)
end

---Enable or disable logging
---@param enabled boolean
function M.set_enabled(enabled)
  config.enabled = enabled
end

---Check if logging is enabled
---@return boolean
function M.is_enabled()
  return config.enabled
end

---Get the log path
---@return string
function M.get_path()
  return config.path
end

---Configure the logging module
---@param opts? { enabled?: boolean, path?: string }
function M.configure(opts)
  if opts then
    if opts.enabled ~= nil then
      config.enabled = opts.enabled
    end
    if opts.path then
      config.path = opts.path
    end
  end
end

return M
