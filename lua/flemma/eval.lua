--- Safe environment and execution for Lua code in Flemma, where safe is a loose term.
---
--- Reserved environment fields:
---   __filename  - Current file path for error reporting and path resolution
---   __dirname   - Directory containing the current file
---
--- User-defined variables from frontmatter are stored as top-level keys in the environment.

---@class flemma.Eval
local M = {}

---@alias flemma.eval.Environment table<string, any>

--- MIME detection: override or auto-detect via `file` command + extension fallback.
---@param path string
---@param override string|nil
---@return string|nil
local function detect_mime(path, override)
  if override and #override > 0 then
    return override
  end
  local mime_util = require("flemma.mime")
  local ok, mt, _ = pcall(mime_util.get_mime_type, path)
  if ok and mt then
    return mt
  end
  return mime_util.get_mime_by_extension(path)
end

--- Read file content (binary or text mode).
---@param path string
---@param binary boolean
---@return string data
---@return nil
---@overload fun(path: string, binary: boolean): nil, string
local function read_file(path, binary)
  local mode = binary and "rb" or "r"
  local f, err = io.open(path, mode)
  if not f then
    return nil, ("Failed to open file: " .. (err or "unknown"))
  end
  local data = f:read("*a")
  f:close()
  if not data then
    return nil, "Failed to read content"
  end
  return data, nil
end

--- Build the include() closure for a given environment.
--- The include_stack is threaded through closures — not stored on the env.
---@param env flemma.eval.Environment The environment where include() will be installed
---@param include_stack string[] Captured include stack (immutable from this scope)
---@param eval_expr_fn fun(expr: string, env: flemma.eval.Environment): any
---@param create_env_fn fun(): flemma.eval.Environment
local function install_include(env, include_stack, eval_expr_fn, create_env_fn)
  local emittable = require("flemma.emittable")

  ---@param relative_path string
  ---@param opts? { binary?: boolean, mime?: string }
  ---@return table emittable An IncludePart with an emit() method
  env.include = function(relative_path, opts)
    opts = opts or {}
    local dirname = env.__dirname

    -- Resolve path: use __dirname if set, otherwise use relative path as-is
    local target_path
    if dirname then
      target_path = vim.fs.normalize(dirname .. "/" .. relative_path)
    else
      target_path = relative_path
    end

    -- Check file exists
    if vim.fn.filereadable(target_path) ~= 1 then
      error({
        type = "file",
        filename = target_path,
        raw = relative_path,
        error = "File not found: " .. target_path,
      })
    end

    -- Binary mode: read raw bytes, detect MIME, return binary IncludePart
    -- No circular detection needed — binary reads don't recurse into content
    if opts.binary then
      local mime = detect_mime(target_path, opts.mime)
      if not mime then
        error({
          type = "file",
          filename = target_path,
          raw = relative_path,
          error = "Could not determine MIME type for: " .. target_path,
        })
      end

      local data, read_err = read_file(target_path, true)
      if not data then
        error({
          type = "file",
          filename = target_path,
          raw = relative_path,
          error = read_err or "read error",
        })
      end

      return emittable.binary_include_part(target_path, mime, data)
    end

    -- Text mode: circular detection applies (text includes recurse)
    for _, path_in_stack in ipairs(include_stack) do
      if path_in_stack == target_path then
        error(
          string.format(
            "Circular include for '%s' (requested by '%s'). Include stack: %s",
            target_path,
            env.__filename or "N/A",
            table.concat(include_stack, " -> ")
          )
        )
      end
    end

    -- Text mode: read, parse, evaluate, return composite IncludePart
    local content, read_err = read_file(target_path, false)
    if not content then
      error({
        type = "file",
        filename = target_path,
        raw = relative_path,
        error = read_err or "Failed to read file",
      })
    end

    -- Parse content for {{ }} expressions and @./ file references
    local parser = require("flemma.parser")
    local segments = parser.parse_inline_content(content)

    -- Create isolated child environment (does NOT inherit user variables)
    local child_env = create_env_fn()
    child_env.__filename = target_path
    child_env.__dirname = vim.fn.fnamemodify(target_path, ":h")

    -- Create extended include stack for the child
    local child_stack = {}
    for _, p in ipairs(include_stack) do
      child_stack[#child_stack + 1] = p
    end
    child_stack[#child_stack + 1] = target_path

    -- Install include() on child env with extended stack
    install_include(child_env, child_stack, eval_expr_fn, create_env_fn)

    -- Process segments into children for the composite part
    local children = {}
    for _, seg in ipairs(segments) do
      if seg.kind == "text" then
        children[#children + 1] = seg.value
      elseif seg.kind == "expression" then
        local ok, result = pcall(eval_expr_fn, seg.code, child_env)
        if not ok then
          error(result)
        end
        -- If result is emittable, keep it as a child; otherwise stringify
        if emittable.is_emittable(result) then
          children[#children + 1] = result
        else
          children[#children + 1] = result == nil and "" or tostring(result)
        end
      end
    end

    return emittable.composite_include_part(children)
  end
end

---@param env flemma.eval.Environment
---@param eval_expr_fn fun(expr: string, env: flemma.eval.Environment): any
---@param create_env_fn fun(): flemma.eval.Environment
local function ensure_env_capabilities(env, eval_expr_fn, create_env_fn)
  if env.include == nil then
    -- Build the initial include stack from __filename
    local initial_stack = {}
    if env.__filename then
      initial_stack[1] = env.__filename
    end
    install_include(env, initial_stack, eval_expr_fn, create_env_fn)
  end
end

--- Create a safe environment for executing Lua code
---
--- User-defined variables from frontmatter are merged as top-level keys by context.to_eval_env().
--- The 'include' function is added by ensure_env_capabilities to capture the correct environment.
--- Reserved internal fields (__filename, __dirname) are set by context.to_eval_env().
---@return flemma.eval.Environment
function M.create_safe_env()
  return {
    -- String manipulation
    string = {
      byte = string.byte,
      char = string.char,
      find = string.find,
      format = string.format,
      gmatch = string.gmatch,
      gsub = string.gsub,
      len = string.len,
      lower = string.lower,
      match = string.match,
      rep = string.rep,
      reverse = string.reverse,
      sub = string.sub,
      upper = string.upper,
    },

    -- Table operations for data structuring
    table = {
      concat = table.concat,
      insert = table.insert,
      remove = table.remove,
      sort = table.sort,
      unpack = table.unpack,
    },

    -- Math for calculations in templates
    math = {
      abs = math.abs,
      ceil = math.ceil,
      floor = math.floor,
      max = math.max,
      min = math.min,
      random = math.random,
      randomseed = math.randomseed,
      round = math.floor, -- common alias
      pi = math.pi,
    },

    -- UTF-8 support for unicode string handling (available in Lua 5.3+, nil in LuaJIT)
    utf8 = utf8, ---@diagnostic disable-line: undefined-global

    -- Neovim API functions required by include()
    vim = {
      fn = {
        fnamemodify = vim.fn.fnamemodify,
        getcwd = vim.fn.getcwd,
        filereadable = vim.fn.filereadable,
        simplify = vim.fn.simplify,
      },
      fs = {
        normalize = vim.fs.normalize,
        abspath = vim.fs.abspath,
      },
    },

    -- Essential functions for template operation
    assert = assert,
    error = error,
    ipairs = ipairs,
    pairs = pairs,
    select = select,
    tonumber = tonumber,
    tostring = tostring,
    type = type,
    print = print,

    -- Useful constants
    _VERSION = _VERSION,
  }
end

--- Execute code in a safe environment
---@param code string
---@param env_param flemma.eval.Environment|nil
---@return table<string, any> globals New variables defined during execution
function M.execute_safe(code, env_param)
  -- Create environment and store initial keys
  local env = env_param or M.create_safe_env() -- Use provided env or create a new one

  -- Ensure 'include' is available and correctly contextualized for this environment.
  -- M.eval_expression and M.create_safe_env are used for recursive calls from 'include'.
  ensure_env_capabilities(env, M.eval_expression, M.create_safe_env)

  local initial_keys = {}
  for k in pairs(env) do
    initial_keys[k] = true
  end

  local chunk, load_err = load(code, "safe_env", "t", env)
  if not chunk then
    error(string.format("Load error in frontmatter of '%s': %s", (env.__filename or "N/A"), load_err))
  end

  local ok, exec_err = pcall(chunk)
  if not ok then
    error(string.format(
      "Execution error in frontmatter of '%s': %s",
      (env.__filename or "N/A"),
      exec_err -- This could be an error from include, already contextualized
    ))
  end

  -- Collect only new keys that weren't in initial environment
  local globals = {}
  for k, v in pairs(env) do
    if not initial_keys[k] then
      globals[k] = v
    end
  end

  return globals
end

--- Evaluate an expression in a given environment
---@param expr string
---@param env flemma.eval.Environment
---@return any result
function M.eval_expression(expr, env)
  -- Ensure 'env' is not nil, though callers should guarantee this.
  if not env then
    error("eval.eval_expression called with a nil environment.")
  end

  -- Ensure 'include' is available and correctly contextualized for this environment.
  ensure_env_capabilities(env, M.eval_expression, M.create_safe_env)

  -- Wrap expression in return statement if it's not already a statement
  if not expr:match("^%s*return%s+") then
    expr = "return " .. expr
  end

  local chunk, parse_err = load(expr, "expression", "t", env)
  if not chunk then
    error(string.format("Parse error in '%s' for expression '{{%s}}': %s", (env.__filename or "N/A"), expr, parse_err))
  end

  local ok, eval_result = pcall(chunk)
  if not ok then
    -- Preserve structured error tables (e.g. from include()) so the processor
    -- can produce properly typed diagnostics (type="file" vs type="expression").
    if type(eval_result) == "table" and eval_result.type then
      error(eval_result)
    end
    error(
      string.format(
        "Evaluation error in '%s' for expression '{{%s}}': %s",
        (env.__filename or "N/A"),
        expr,
        eval_result
      )
    )
  end

  return eval_result
end

return M
