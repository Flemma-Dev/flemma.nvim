--- Flemma logging functionality
--- Provides centralized logging capabilities with custom inspect
---@class flemma.Logging
local M = {}

---@alias flemma.logging.Level "TRACE"|"DEBUG"|"INFO"|"WARN"|"ERROR"

---@class flemma.logging.Config
---@field enabled boolean Whether logging is active
---@field path string Filesystem path for the log file
---@field level flemma.logging.Level Minimum severity to write (default: "DEBUG")

---Numeric severity for level filtering (lower = more verbose)
---@type table<flemma.logging.Level, integer>
local LEVELS = { TRACE = 0, DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }

---@type flemma.logging.Config
local config = {
  enabled = false,
  path = vim.fn.stdpath("cache") .. "/flemma.log",
  level = "DEBUG",
}

---Write a log message to the log file
---@param level flemma.logging.Level Log level label
---@param msg string The message to log
local function write_log(level, msg)
  if not config.enabled then
    return
  end

  -- Filter by minimum level
  local min = LEVELS[config.level] or LEVELS.DEBUG
  local current = LEVELS[level]
  if current and current < min then
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

---Log a trace message (most verbose — per-delta, per-line, per-event)
---@param msg string
function M.trace(msg)
  write_log("TRACE", msg)
end

---Log a debug message (state transitions, decisions, lifecycle)
---@param msg string
function M.debug(msg)
  write_log("DEBUG", msg)
end

---Log an info message
---@param msg string
function M.info(msg)
  write_log("INFO", msg)
end

---Log a warning message
---@param msg string
function M.warn(msg)
  write_log("WARN", msg)
end

---Log an error message
---@param msg string
function M.error(msg)
  write_log("ERROR", msg)
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

---Get the current minimum log level
---@return flemma.logging.Level
function M.get_level()
  return config.level
end

---Check whether a string is a valid log level name
---@param name string
---@return boolean
function M.is_valid_level(name)
  return LEVELS[name:upper()] ~= nil
end

---Configure the logging module
---@param opts? { enabled?: boolean, path?: string, level?: flemma.logging.Level }
function M.configure(opts)
  if opts then
    if opts.enabled ~= nil then
      config.enabled = opts.enabled
    end
    if opts.path then
      config.path = opts.path
    end
    if opts.level then
      config.level = opts.level
    end
  end
end

return M
