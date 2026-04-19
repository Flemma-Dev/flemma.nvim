-- Add the project root and the current working directory to the runtime path
-- so that 'lua/' modules are found. The CWD prepend ensures worktree lua/
-- modules shadow any stale copies in the main-repo PROJECT_ROOT.
vim.opt.rtp:prepend(vim.uv.cwd())
vim.opt.rtp:append(os.getenv("PROJECT_ROOT"))

-- Turn off swapfile during tests
vim.opt.swapfile = false

-- === Test output filtering ===
-- Each spec file runs in its own child nvim process. We buffer all stdout,
-- then after all tests complete, emit either a one-line pass summary or
-- the full failure output (minus individual Success lines).
do
  local real_stdout = io.stdout
  local buffer = {}

  -- Replace io.stdout with a proxy that captures :write() calls.
  -- Plenary's busted.lua overrides print() to use io.stdout:write(),
  -- so this captures all test output (Success/Fail lines, headers, summaries).
  io.stdout = setmetatable({
    write = function(_, str)
      buffer[#buffer + 1] = str
    end,
  }, {
    __index = function(_, key)
      -- Forward non-write methods (flush, close, etc.) to real stdout,
      -- rebinding self so the C FILE* check passes.
      local val = real_stdout[key]
      if type(val) == "function" then
        return function(_, ...)
          return val(real_stdout, ...)
        end
      end
      return val
    end,
  })

  -- Suppress vim.notify messages from production code exercised by tests.
  -- Tests that need to inspect notify calls already stub it themselves.
  local real_notify = vim.notify
  vim.notify = function(msg, ...)
    if type(msg) == "string" and msg:find("^Flemma") then
      return
    end
    return real_notify(msg, ...)
  end

  -- Hook plenary.busted via package.preload to wrap format_results.
  -- When require("plenary.busted") is called (in the -c command, after
  -- minimal_init.lua has finished), our preload fires first, loads the
  -- real module via the file-system searchers (skipping package.preload
  -- to avoid a require loop), wraps format_results, and returns the
  -- patched module.
  package.preload["plenary.busted"] = function(modname)
    -- Find the real module file using the standard Lua file searchers,
    -- skipping searcher #1 (package.preload) to avoid recursion.
    local loader, origin
    for i = 2, #package.loaders do
      local result, path = package.loaders[i](modname)
      if type(result) == "function" then
        loader = result
        origin = path
        break
      end
    end
    assert(loader, "cannot find real plenary.busted module")

    local busted = loader(modname, origin)
    -- Store in package.loaded so subsequent require() calls return it.
    package.loaded[modname] = busted

    local orig_format = busted.format_results
    busted.format_results = function(res)
      -- Restore real stdout — anything after this goes directly out.
      io.stdout = real_stdout

      if #res.fail > 0 or #res.errs > 0 then
        -- Failure: emit the buffer minus individual Success lines.
        -- Keeps: Testing header, Fail lines, failure details, separators.
        local full = table.concat(buffer)
        for line in full:gmatch("([^\r\n]*)\r?\n") do
          local clean = line:gsub("\27%[[%d;]*m", "")
          if not clean:match("^Success%s+||") then
            real_stdout:write(line)
            real_stdout:write("\n")
          end
        end
        -- Emit the pass/fail/error summary via the original formatter.
        orig_format(res)
      else
        -- All passed: one-line summary.
        local full = table.concat(buffer)
        local spec = full:match("/([^/\t]+_spec%.lua)") or "?"
        real_stdout:write(spec .. ": " .. #res.pass .. " passed\n")
      end
    end

    return busted
  end
end

-- Initialize the plugin with default settings
require("flemma").setup({})

-- Suppress flemma.notify dispatches by default. Specs that want to inspect
-- notifications override this by calling _set_impl in their before_each.
require("flemma.notify")._set_impl(function(notification)
  return notification
end)
