--- Safe environment and execution for Lua code in Flemma, where safe is a loose term.
---
--- User-visible environment fields (string keys, accessible to sandbox code):
---   __filename  - Current file path for error reporting and path resolution
---   __dirname   - Directory containing the current file
---
--- Internal environment fields (symbol keys, invisible to sandbox code):
---   symbols.FRONTMATTER_OPTS  - Per-buffer frontmatter options
---   symbols.BUFFER_NUMBER     - Buffer number for context-aware operations
---
--- User-defined variables from frontmatter are stored as top-level keys in the environment.

---@class flemma.templating.Eval
local M = {}

local compiler = require("flemma.templating.compiler")
local emittable = require("flemma.emittable")
local log = require("flemma.logging")
local mime_util = require("flemma.mime")
local parser = require("flemma.parser")
local personality_builder = require("flemma.personalities.builder")
local personality_registry = require("flemma.personalities")
local state = require("flemma.state")
local str = require("flemma.utilities.string")
local symbols = require("flemma.symbols")

local PERSONALITY_URN_PREFIX = "urn:flemma:personality:"

--- Check for file content drift and push a diagnostic if the file changed since
--- the last evaluation. Stores the current hash for future comparisons.
---@param env flemma.templating.eval.Environment Eval environment with symbol-keyed fields
---@param target_path string Resolved absolute file path
---@param content string Current file content (text or binary)
local function check_file_drift(env, target_path, content)
  local bufnr = env[symbols.BUFFER_NUMBER]
  local collector = env[symbols.DIAGNOSTICS]
  if not bufnr or not collector then
    return
  end

  local hash = vim.fn.sha256(content)
  local buffer_state = state.get_buffer_state(bufnr)
  if not buffer_state.file_reference_hashes then
    buffer_state.file_reference_hashes = {}
  end

  local previous_hash = buffer_state.file_reference_hashes[target_path]
  if previous_hash and previous_hash ~= hash then
    table.insert(collector, {
      type = "custom:file_drift",
      severity = "warning",
      label = "File drift detected (content changed since last request)",
      error = string.format("File changed since last request: %s", target_path),
      filename = target_path,
    })
  end
  buffer_state.file_reference_hashes[target_path] = hash
end

---@alias flemma.templating.eval.Environment table<string, any>

--- MIME detection: override or auto-detect via `file` command + extension fallback.
---@param path string
---@param override string|nil
---@return string|nil
local function detect_mime(path, override)
  if override and #override > 0 then
    return override
  end
  local ok, mt, _ = pcall(mime_util.get_mime_type, path)
  if ok and mt then
    return mt
  end
  return mime_util.get_mime_by_extension(path)
end

--- Read file content (binary or text mode).
---@param path string
---@param opts? { binary?: boolean }
---@return string data
---@return nil
---@overload fun(path: string, opts?: { binary?: boolean }): nil, string
local function read_file(path, opts)
  local mode = (opts and opts.binary) and "rb" or "r"
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

--- Propagate an error from pcall: re-throw structured error tables as-is, wrap others with context.
---
--- Structured errors (tables with a `type` field) come from include() and other subsystems
--- that produce typed diagnostics. Re-throwing preserves the diagnostic type so the
--- processor can format them properly (e.g., "file" errors vs "expression" errors).
---@param err any Error value from pcall
---@param format string Format string for wrapping non-structured errors
---@param ... any Additional format arguments
local function propagate_error(err, format, ...)
  if type(err) == "table" and err.type then
    error(err)
  end
  error(string.format(format, ...))
end

--- Build the include() closure for a given environment.
--- The include_stack is threaded through closures — not stored on the env.
---@param env flemma.templating.eval.Environment The environment where include() will be installed
---@param include_stack string[] Captured include stack (immutable from this scope)
---@param eval_expr_fn fun(expr: string, env: flemma.templating.eval.Environment): any
---@param create_env_fn fun(): flemma.templating.eval.Environment
local function install_include(env, include_stack, eval_expr_fn, create_env_fn)
  ---@param relative_path string
  ---@param opts? table Template variables (string keys) merged into child env. Symbol keys [BINARY] and [MIME] control include mode.
  ---@return table emittable An IncludePart with an emit() method
  env.include = function(relative_path, opts)
    if type(relative_path) ~= "string" then
      error({
        type = "expression",
        error = string.format("include() expects a string path, got %s", type(relative_path)),
      })
    end

    opts = opts or {}

    -- URN dispatch: personality system
    if relative_path:sub(1, #PERSONALITY_URN_PREFIX) == PERSONALITY_URN_PREFIX then
      local personality_name = relative_path:sub(#PERSONALITY_URN_PREFIX + 1)
      local personality = personality_registry.get(personality_name)
      if not personality then
        local msg = string.format("Unknown personality: '%s'", personality_name)
        local all_personalities = personality_registry.get_all()
        local suggestion = str.closest_match(personality_name, all_personalities)
        if suggestion then
          msg = msg .. string.format(". Did you mean '%s'?", suggestion)
        end
        error({ type = "expression", error = msg })
      end
      local render_opts = personality_builder.build(
        personality_name,
        env[symbols.FRONTMATTER_OPTS],
        env.__dirname or vim.fn.getcwd(),
        env[symbols.BUFFER_NUMBER]
      )
      local rendered = personality.render(render_opts)
      return emittable.composite_include_part({ rendered })
    end

    local dirname = env.__dirname

    -- Resolve path: absolute paths used as-is, relative paths joined with __dirname
    local target_path
    if relative_path:sub(1, 1) == "/" then
      target_path = vim.fs.normalize(relative_path)
    elseif dirname then
      target_path = vim.fs.normalize(dirname .. "/" .. relative_path)
    else
      target_path = relative_path
    end

    -- Check file exists
    if vim.fn.filereadable(target_path) ~= 1 then
      log.debug("eval: include() file not found: " .. target_path)
      error({
        type = "file",
        filename = target_path,
        raw = relative_path,
        error = "File not found: " .. target_path,
        include_stack = { unpack(include_stack) },
      })
    end

    -- Binary mode: read raw bytes, detect MIME, return binary IncludePart
    -- No circular detection needed — binary reads don't recurse into content
    if opts[symbols.INCLUDE_BINARY] then
      log.debug("eval: include() binary mode for " .. target_path)
      local mime = detect_mime(target_path, opts[symbols.INCLUDE_MIME])
      if not mime then
        error({
          type = "file",
          filename = target_path,
          raw = relative_path,
          error = "Could not determine MIME type for: " .. target_path,
          include_stack = { unpack(include_stack) },
        })
      end

      local data, read_err = read_file(target_path, { binary = true })
      if not data then
        error({
          type = "file",
          filename = target_path,
          raw = relative_path,
          error = read_err or "read error",
          include_stack = { unpack(include_stack) },
        })
      end

      check_file_drift(env, target_path, data)
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

    -- Text mode: read, parse, compile, execute, return composite IncludePart
    log.trace("eval: include() text mode for " .. target_path)
    local content, read_err = read_file(target_path)
    if not content then
      error({
        type = "file",
        filename = target_path,
        raw = relative_path,
        error = read_err or "Failed to read file",
        include_stack = { unpack(include_stack) },
      })
    end

    check_file_drift(env, target_path, content)

    -- Parse content for {{ }} expressions and @./ file references
    local segments = parser.parse_inline_content(content)

    -- Create isolated child environment (does NOT inherit user variables)
    local child_env = create_env_fn()
    child_env.__filename = target_path
    child_env.__dirname = vim.fn.fnamemodify(target_path, ":h")

    -- Inject caller-provided arguments: only string keys are template variables.
    -- Symbol keys (BINARY, MIME) are include() control flags, not variables.
    for key, value in pairs(opts) do
      if type(key) == "string" then
        child_env[key] = value
      end
    end

    -- Create extended include stack for the child
    local child_stack = {}
    for _, p in ipairs(include_stack) do
      child_stack[#child_stack + 1] = p
    end
    child_stack[#child_stack + 1] = target_path

    -- Install include() on child env with extended stack
    install_include(child_env, child_stack, eval_expr_fn, create_env_fn)

    -- Override pcall in child env so the compiler's expression wrappers re-throw
    -- errors instead of degrading gracefully. Inside includes, expression errors are
    -- fatal (matching pre-compiler behavior) — the compiler's graceful degradation
    -- is only appropriate at the top-level processor where messages are evaluated.
    child_env.pcall = function(fn, ...)
      local results = { pcall(fn, ...) }
      if not results[1] then
        local err = results[2]
        -- Enrich structured errors from deeper includes with this level's stack
        if type(err) == "table" and err.type and not err.include_stack then
          err.include_stack = { unpack(child_stack) }
        end
        error(err)
      end
      return unpack(results)
    end

    -- Compile and execute via compiler
    local compile_result = compiler.compile(segments)
    if compile_result.error then
      log.debug("eval: include() compile error in " .. target_path .. ": " .. compile_result.error)
    end
    local compiled_parts, compile_diagnostics = compiler.execute(compile_result, child_env)

    -- Re-throw fatal diagnostics (severity "error") so include errors propagate
    -- to the caller. The custom pcall above ensures expression errors are promoted
    -- to chunk-level failures, which the compiler records as severity "error".
    for _, diag in ipairs(compile_diagnostics) do
      if diag.severity == "error" then
        error(diag.error or "Unknown template error")
      end
    end

    -- Propagate non-fatal diagnostics to parent
    local parent_collector = env[symbols.DIAGNOSTICS]
    if parent_collector then
      for _, diag in ipairs(compile_diagnostics) do
        table.insert(parent_collector, diag)
      end
    end

    -- Convert compiler output parts to emittable children for composite_include_part
    local children = {}
    for _, part in ipairs(compiled_parts) do
      if part.kind == "text" then
        children[#children + 1] = part.text
      elseif part.kind == "file" then
        children[#children + 1] = emittable.binary_include_part(part.filename, part.mime_type, part.data)
      else
        -- Structural parts (tool_use, tool_result, thinking, aborted): wrap as emittable
        children[#children + 1] = {
          _part = part,
          ---@param self table
          ---@param ctx flemma.emittable.EmitContext
          emit = function(self, ctx)
            table.insert(ctx.parts, self._part)
          end,
        }
      end
    end

    return emittable.composite_include_part(children, { source_path = target_path })
  end
end

---@param env flemma.templating.eval.Environment
---@param eval_expr_fn fun(expr: string, env: flemma.templating.eval.Environment): any
---@param create_env_fn fun(): flemma.templating.eval.Environment
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

--- Ensure an eval environment has all capabilities installed (include, etc.).
--- Call this before passing the env to the compiler for template execution.
---@param env flemma.templating.eval.Environment
function M.ensure_env(env)
  ensure_env_capabilities(env, M.eval_expression, M.create_safe_env)
end

--- Create a safe environment for executing Lua code
---
--- User-defined variables from frontmatter are merged as top-level keys by context.to_eval_env().
--- The 'include' function is added by ensure_env_capabilities to capture the correct environment.
--- User-visible fields (__filename, __dirname) and internal symbol-keyed fields are set by context.to_eval_env().
---@return flemma.templating.eval.Environment
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

    -- Symbols table: opaque table keys for include() mode flags.
    -- Mirrors flemma.symbols — user code writes { [symbols.BINARY] = true }.
    -- "symbols" is a reserved key and must not be overwritten by frontmatter variables.
    symbols = {
      BINARY = symbols.INCLUDE_BINARY,
      MIME = symbols.INCLUDE_MIME,
    },
  }
end

--- Execute code in a safe environment
---@param code string
---@param env_param flemma.templating.eval.Environment|nil
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
    propagate_error(exec_err, "Execution error in frontmatter of '%s': %s", (env.__filename or "N/A"), exec_err)
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
---@param env flemma.templating.eval.Environment
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
    propagate_error(
      eval_result,
      "Evaluation error in '%s' for expression '{{%s}}': %s",
      (env.__filename or "N/A"),
      expr,
      eval_result
    )
  end

  return eval_result
end

return M
