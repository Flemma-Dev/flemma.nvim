--- MIME type detection utility
local log = require("flemma.logging")
local M = {}

-- Cache for file command availability check
local file_command_available = nil

-- MIME types by extension tailored for AI chat interface (fallback when 'file' command is unavailable)
local MIME_BY_EXTENSION = {
  -- Documentation & markup
  txt = "text/plain",
  md = "text/markdown",
  markdown = "text/markdown",
  rst = "text/x-rst",
  org = "text/org",
  -- Config & data
  json = "application/json",
  yaml = "application/yaml",
  yml = "application/yaml",
  toml = "application/toml",
  xml = "application/xml",
  csv = "text/csv",
  sql = "application/sql",
  -- Web frontend
  html = "text/html",
  htm = "text/html",
  css = "text/css",
  scss = "text/x-scss",
  sass = "text/x-sass",
  js = "application/javascript",
  mjs = "application/javascript",
  cjs = "application/javascript",
  jsx = "text/jsx",
  ts = "application/typescript",
  tsx = "text/tsx",
  vue = "text/x-vue",
  svelte = "text/x-svelte",
  -- Programming languages
  py = "text/x-python",
  rb = "text/x-ruby",
  go = "text/x-go",
  rs = "text/x-rust",
  c = "text/x-c",
  cpp = "text/x-c++",
  cc = "text/x-c++",
  cxx = "text/x-c++",
  h = "text/x-c",
  hpp = "text/x-c++",
  java = "text/x-java",
  kt = "text/x-kotlin",
  swift = "text/x-swift",
  php = "text/x-php",
  sh = "text/x-shellscript",
  bash = "text/x-shellscript",
  zsh = "text/x-shellscript",
  fish = "text/x-shellscript",
  lua = "text/x-lua",
  vim = "text/x-vim",
  el = "text/x-emacs-lisp",
  clj = "text/x-clojure",
  -- Images (for vision capabilities)
  png = "image/png",
  jpg = "image/jpeg",
  jpeg = "image/jpeg",
  gif = "image/gif",
  svg = "image/svg+xml",
  webp = "image/webp",
  bmp = "image/bmp",
  -- Documents
  pdf = "application/pdf",
}

--- Fallback MIME detection based on file extension
--- @param filepath string The path to the file.
--- @return string|nil The detected MIME type, or nil if unknown.
local function get_mime_by_extension(filepath)
  local ext = filepath:match("%.([^%.]+)$")
  if ext then
    ext = ext:lower()
    return MIME_BY_EXTENSION[ext]
  end
  return nil
end

--- Gets the MIME type of a file using the 'file' command.
--- @param filepath string The path to the file.
--- @return string|nil The detected MIME type, or nil if an error occurred.
--- @return string|nil An error message if an error occurred, otherwise nil.
function M.get_mime_type(filepath)
  -- Check cache first
  if file_command_available == false then
    error("The 'file' command is required to determine file MIME types but was not found.", 0)
  end

  -- Check if file command exists if not cached yet
  if file_command_available == nil then
    local check_cmd = "command -v file >/dev/null 2>&1"
    local check_result = os.execute(check_cmd)
    if check_result == 0 then
      file_command_available = true
      log.debug("get_mime_type(): 'file' command found.")
    else
      file_command_available = false
      log.error("get_mime_type(): 'file' command not found.")
      error("The 'file' command is required to determine file MIME types but was not found.", 0)
    end
  end

  -- Execute file command to get MIME type
  -- Use -b for brief output and --mime-type for the type itself
  -- Escape filename for shell safety
  local escaped_filepath = vim.fn.shellescape(filepath)
  local cmd = string.format("file -b --mime-type %s", escaped_filepath)
  local handle = io.popen(cmd, "r") -- Read mode

  if not handle then
    log.error("get_mime_type(): Failed to execute 'file' command for: \"" .. filepath .. '"')
    return nil, "Failed to execute 'file' command"
  end

  local output = handle:read("*a")
  local success, _, code = handle:close()

  if success and output and #output > 0 then
    -- Trim whitespace from the output
    local mime_type = output:match("^%s*(.-)%s*$")
    if mime_type and #mime_type > 0 then
      log.debug('get_mime_type(): Detected MIME type for "' .. filepath .. '": ' .. mime_type)
      return mime_type, nil
    else
      log.error(
        "get_mime_type(): 'file' command returned empty or invalid output for \"" .. filepath .. '": ' .. output
      )
      return nil, "Failed to determine MIME type (empty output)"
    end
  else
    local err_msg = 'Failed to get MIME type for "' .. filepath .. '"'
    if code then
      err_msg = err_msg .. " (exit code: " .. tostring(code) .. ")"
    end
    if output and #output > 0 then
      err_msg = err_msg .. "\nOutput: " .. output
    end
    log.error("get_mime_type(): " .. err_msg)
    return nil, err_msg
  end
end

--- Publicly expose the extension-based fallback
M.get_mime_by_extension = get_mime_by_extension

return M
