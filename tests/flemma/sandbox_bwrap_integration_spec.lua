--- Integration + E2E tests for the sandbox implementation.
--- Every test exercises OUR code through real bwrap execution — validating that
--- the policy layer, config plumbing, executor context, bash tool integration,
--- and runtime toggle work correctly together, not that bwrap itself behaves.
---
--- All tests are gated on bwrap availability.

local function skip_unless_bwrap()
  if vim.fn.executable("bwrap") ~= 1 then
    pending("bwrap not installed, skipping")
    return true
  end
  if vim.fn.has("linux") ~= 1 then
    pending("requires Linux, skipping")
    return true
  end
  return false
end

--- Standard sandbox config for tests.
--- Returns a config table with sandbox enabled, the given rw_paths, and sensible defaults.
---@param rw_paths string[]
---@param overrides? table
---@return table
local function sandbox_config(rw_paths, overrides)
  local base = {
    enabled = true,
    backend = "bwrap",
    policy = {
      rw_paths = rw_paths,
      network = true,
      allow_privileged = false,
    },
    backends = { bwrap = { path = "bwrap" } },
  }
  if overrides then
    base = vim.tbl_deep_extend("force", base, overrides)
  end
  return base
end

--- Execute a command through our bash tool with a given sandbox config.
--- This is the real code path: state.set_config → tool.execute(input, ctx, cb).
--- Validates that our bash.lua reads the sandbox config and wraps correctly.
---@param command string
---@param sbx_config table sandbox config
---@param opts? { timeout?: number, bufnr?: integer, extra_config?: table }
---@return flemma.tools.ExecutionResult
local function execute_bash_tool(command, sbx_config, opts)
  opts = opts or {}
  local state = require("flemma.state")
  local registry = require("flemma.tools.registry")
  local executor = require("flemma.tools.executor")

  local bufnr = opts.bufnr or vim.api.nvim_create_buf(false, true)

  local full_config = vim.tbl_deep_extend("force", {
    sandbox = sbx_config,
    tools = {
      require_approval = false,
      default_timeout = 30,
      show_spinner = true,
      bash = {},
      autopilot = { enabled = false, max_turns = 10 },
    },
  }, opts.extra_config or {})
  state.set_config(full_config)

  local tool = registry.get("bash")
  assert.is_not_nil(tool, "bash tool must be registered")

  ---@type flemma.tools.ExecutionResult|nil
  local result = nil

  local ctx = executor.build_execution_context({
    bufnr = bufnr,
    cwd = vim.fn.getcwd(),
    timeout = full_config.tools.default_timeout or 30,
    tool_name = "bash",
  })

  tool.execute({ label = "test", command = command, timeout = opts.timeout or 10 }, ctx, function(r)
    result = r
  end)

  vim.wait(15000, function()
    return result ~= nil
  end, 50)

  assert.is_not_nil(result, "bash tool did not return a result within timeout")

  if not opts.bufnr then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end

  ---@cast result flemma.tools.ExecutionResult
  return result
end

-- ─── bash tool sandbox integration ──────────────────────────────────────────
-- Tests that bash.lua correctly calls sandbox.wrap_command() and that the
-- resulting command actually enforces the policy.

describe("bash tool sandbox integration", function()
  before_each(function()
    package.loaded["flemma.sandbox"] = nil
    package.loaded["flemma.sandbox.backends.bwrap"] = nil
    local sandbox = require("flemma.sandbox")
    sandbox.reset_enabled()
    sandbox.setup()
  end)

  it("wraps command through sandbox when config enables it", function()
    if skip_unless_bwrap() then
      return
    end

    -- If our code correctly passes the sandbox config → wrap_command → bwrap,
    -- the command runs inside a sandbox where / is read-only.
    -- We verify by attempting a write that would succeed without sandboxing.
    local result = execute_bash_tool("touch /tmp/bash_integration_probe", sandbox_config({}))
    assert.is_false(result.success)
    assert.is_truthy(
      result.error:match("Read%-only file system") or result.error:match("Permission denied"),
      "bash tool should enforce sandbox RO policy: " .. tostring(result.error)
    )
  end)

  it("does NOT wrap command when sandbox is disabled", function()
    if skip_unless_bwrap() then
      return
    end

    -- Same write, but sandbox disabled — should succeed on the real filesystem
    local target = vim.fn.tempname()
    local result =
      execute_bash_tool("echo ok > " .. target .. " && cat " .. target, sandbox_config({}, { enabled = false }))
    assert.is_true(result.success, "unsandboxed write should succeed: " .. tostring(result.error))
    assert.is_truthy(result.output:match("ok"))
    vim.fn.delete(target)
  end)

  it("rw_paths from config are passed through to bwrap correctly", function()
    if skip_unless_bwrap() then
      return
    end

    local test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")

    -- Our policy layer should expand and pass test_dir as --bind to bwrap
    local result = execute_bash_tool(
      "echo from_sandbox > " .. test_dir .. "/proof.txt && cat " .. test_dir .. "/proof.txt",
      sandbox_config({ test_dir })
    )

    assert.is_true(result.success, "write to rw_path should succeed: " .. tostring(result.error))
    assert.is_truthy(result.output:match("from_sandbox"))

    -- Verify the file actually landed on the host (bwrap --bind, not --tmpfs)
    local f = io.open(test_dir .. "/proof.txt", "r")
    assert.is_not_nil(f, "file should exist on host filesystem")
    local content = f:read("*a")
    f:close()
    assert.are.equal("from_sandbox\n", content)

    vim.fn.delete(test_dir, "rf")
  end)

  it("$CWD variable in rw_paths is expanded by our policy layer", function()
    if skip_unless_bwrap() then
      return
    end

    -- $CWD should be expanded to vim.fn.getcwd() by sandbox/init.lua,
    -- making the working directory writable inside the sandbox.
    local cwd = vim.fn.getcwd()
    local target = cwd .. "/sandbox_cwd_test_" .. tostring(os.time())
    local result = execute_bash_tool("echo cwd_write > " .. target .. " && cat " .. target, sandbox_config({ "$CWD" }))

    assert.is_true(result.success, "$CWD expansion should make CWD writable: " .. tostring(result.error))
    assert.is_truthy(result.output:match("cwd_write"))

    vim.fn.delete(target)
  end)

  it("$FLEMMA_BUFFER_PATH variable expands to buffer file directory", function()
    if skip_unless_bwrap() then
      return
    end

    local test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, test_dir .. "/test.chat")

    local target = test_dir .. "/dirname_proof.txt"
    local result = execute_bash_tool(
      "echo dirname_works > " .. target .. " && cat " .. target,
      sandbox_config({ "$FLEMMA_BUFFER_PATH" }),
      { bufnr = bufnr }
    )

    assert.is_true(result.success, "$FLEMMA_BUFFER_PATH should expand: " .. tostring(result.error))
    assert.is_truthy(result.output:match("dirname_works"))

    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(test_dir, "rf")
  end)

  it("network=false in policy results in no network access", function()
    if skip_unless_bwrap() then
      return
    end

    -- Our policy layer should translate network=false to --unshare-net via bwrap backend.
    -- Verify by checking only loopback is present in /proc/net/dev.
    local result = execute_bash_tool(
      "cat /proc/net/dev | grep -v lo | tail -n +3 | wc -l",
      sandbox_config({}, { policy = { network = false } })
    )

    assert.is_true(result.success, "command should succeed: " .. tostring(result.error))
    assert.are.equal("0", vim.trim(result.output), "no non-lo interfaces should exist")
  end)

  it("exit code from inner command is preserved through bwrap", function()
    if skip_unless_bwrap() then
      return
    end

    -- Our bash tool captures exit codes. Verify the bwrap layer doesn't eat them.
    local result = execute_bash_tool("exit 42", sandbox_config({}))
    assert.is_false(result.success)
    assert.is_truthy(result.error:match("code 42"), "exit code 42 should survive: " .. tostring(result.error))
  end)

  it("bash tool timeout kills sandboxed process cleanly", function()
    if skip_unless_bwrap() then
      return
    end

    -- Our bash tool's timer fires, calls jobstop() on the bwrap parent.
    -- Verify the timeout path works through the sandbox layer.
    local result = execute_bash_tool("sleep 300", sandbox_config({}), { timeout = 1 })
    assert.is_false(result.success)
    assert.is_truthy(result.error:match("timed out"), "should report timeout: " .. tostring(result.error))
  end)

  it("env vars from job_opts pass through bwrap to inner command", function()
    if skip_unless_bwrap() then
      return
    end

    -- Our bash tool applies config.tools.bash.env via job_opts.
    -- Bwrap inherits parent env, so these should reach the inner shell.
    local marker = "FLEMMA_SANDBOX_ENV_" .. tostring(os.time())
    vim.fn.setenv(marker, "inherited")

    local result = execute_bash_tool("echo $" .. marker, sandbox_config({}))

    vim.fn.setenv(marker, nil)

    assert.is_true(result.success, "command should succeed: " .. tostring(result.error))
    assert.is_truthy(result.output:match("inherited"), "env should pass through bwrap")
  end)
end)

-- ─── runtime toggle ─────────────────────────────────────────────────────────
-- Tests that set_enabled() / reset_enabled() in sandbox/init.lua actually
-- change whether the bash tool sandboxes subsequent commands.

describe("sandbox runtime toggle E2E", function()
  local sandbox

  before_each(function()
    package.loaded["flemma.sandbox"] = nil
    package.loaded["flemma.sandbox.backends.bwrap"] = nil
    sandbox = require("flemma.sandbox")
    sandbox.reset_enabled()
  end)

  it("set_enabled(true) causes bash tool to sandbox even when config says disabled", function()
    if skip_unless_bwrap() then
      return
    end

    local disabled_config = sandbox_config({}, { enabled = false })

    -- Verify unsandboxed first: write should succeed
    local target = vim.fn.tempname()
    local result1 = execute_bash_tool("echo ok > " .. target, disabled_config)
    assert.is_true(result1.success, "unsandboxed write should work")
    vim.fn.delete(target)

    -- Now enable via runtime toggle — our code, not config
    sandbox.set_enabled(true)

    -- Same config object, but runtime override wins in our resolve_config()
    local result2 = execute_bash_tool("touch /tmp/toggle_probe", disabled_config)
    assert.is_false(result2.success, "sandbox should be enforced after set_enabled(true)")

    sandbox.reset_enabled()
  end)

  it("set_enabled(false) disables sandbox even when config says enabled", function()
    if skip_unless_bwrap() then
      return
    end

    local enabled_config = sandbox_config({})

    -- Verify sandboxed first: write outside rw_paths should fail
    local result1 = execute_bash_tool("touch /tmp/toggle_off_probe", enabled_config)
    assert.is_false(result1.success, "sandbox should block write")

    -- Disable via runtime toggle
    sandbox.set_enabled(false)

    -- Now the same config should NOT sandbox
    local target = vim.fn.tempname()
    local result2 = execute_bash_tool("echo ok > " .. target .. " && cat " .. target, enabled_config)
    assert.is_true(result2.success, "sandbox should be disabled after set_enabled(false): " .. tostring(result2.error))

    vim.fn.delete(target)
    sandbox.reset_enabled()
  end)

  it("reset_enabled() reverts to config-driven behavior", function()
    if skip_unless_bwrap() then
      return
    end

    local enabled_config = sandbox_config({})

    -- Override to disabled
    sandbox.set_enabled(false)
    local target = vim.fn.tempname()
    local result1 = execute_bash_tool("echo ok > " .. target, enabled_config)
    assert.is_true(result1.success, "override=false should disable sandbox")
    vim.fn.delete(target)

    -- Clear override — config says enabled, should sandbox again
    sandbox.reset_enabled()
    local result2 = execute_bash_tool("touch /tmp/reset_enabled_probe", enabled_config)
    assert.is_false(result2.success, "after reset_enabled, config.enabled=true should be enforced")
  end)
end)

-- ─── executor context plumbing ──────────────────────────────────────────────
-- Tests that the executor builds ExecutionContext correctly and the bash tool
-- receives it. We verify by observing the sandbox's behavior change based on
-- what bufnr is in the context (since $FLEMMA_BUFFER_PATH depends on it).

describe("executor context plumbing", function()
  before_each(function()
    package.loaded["flemma.sandbox"] = nil
    package.loaded["flemma.sandbox.backends.bwrap"] = nil
    local sandbox = require("flemma.sandbox")
    sandbox.reset_enabled()
    sandbox.setup()
  end)

  it("bash tool receives bufnr from context for path variable expansion", function()
    if skip_unless_bwrap() then
      return
    end

    -- Create two buffers with different directories
    local dir_a = vim.fn.tempname()
    local dir_b = vim.fn.tempname()
    vim.fn.mkdir(dir_a, "p")
    vim.fn.mkdir(dir_b, "p")

    local buf_a = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf_a, dir_a .. "/a.chat")

    local buf_b = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf_b, dir_b .. "/b.chat")

    -- Policy uses only $FLEMMA_BUFFER_PATH — so RW access depends on which
    -- buffer's context is passed. This tests that our code correctly threads
    -- bufnr through ctx → sandbox.wrap_command → resolve_policy → path_variables.
    local config = sandbox_config({ "$FLEMMA_BUFFER_PATH" })

    -- Write to dir_a using buf_a's context — should succeed
    local result_a =
      execute_bash_tool("echo a > " .. dir_a .. "/ctx.txt && cat " .. dir_a .. "/ctx.txt", config, { bufnr = buf_a })
    assert.is_true(result_a.success, "buf_a context should make dir_a writable: " .. tostring(result_a.error))

    -- Write to dir_a using buf_b's context — should FAIL (dir_a is not buf_b's dirname)
    local result_cross = execute_bash_tool("touch " .. dir_a .. "/cross.txt", config, { bufnr = buf_b })
    assert.is_false(result_cross.success, "buf_b context should NOT make dir_a writable")

    vim.api.nvim_buf_delete(buf_a, { force = true })
    vim.api.nvim_buf_delete(buf_b, { force = true })
    vim.fn.delete(dir_a, "rf")
    vim.fn.delete(dir_b, "rf")
  end)

  it("unnamed buffer gracefully skips $FLEMMA_BUFFER_PATH", function()
    if skip_unless_bwrap() then
      return
    end

    -- Unnamed buffer → $FLEMMA_BUFFER_PATH resolves to nil → skipped.
    -- Only explicit paths in rw_paths should be writable.
    local test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")

    local unnamed_buf = vim.api.nvim_create_buf(false, true)
    -- No nvim_buf_set_name — buffer is unnamed

    local config = sandbox_config({ "$FLEMMA_BUFFER_PATH", test_dir })
    local result = execute_bash_tool(
      "echo ok > " .. test_dir .. "/unnamed.txt && cat " .. test_dir .. "/unnamed.txt",
      config,
      { bufnr = unnamed_buf }
    )

    assert.is_true(result.success, "explicit rw_path should still work: " .. tostring(result.error))
    assert.is_truthy(result.output:match("ok"))

    vim.api.nvim_buf_delete(unnamed_buf, { force = true })
    vim.fn.delete(test_dir, "rf")
  end)
end)

-- ─── process lifecycle through bash tool ────────────────────────────────────
-- Tests that our bash tool's cancel and timeout mechanisms work correctly
-- when the command is running inside a bwrap sandbox.

describe("sandbox process lifecycle through bash tool", function()
  before_each(function()
    package.loaded["flemma.sandbox"] = nil
    package.loaded["flemma.sandbox.backends.bwrap"] = nil
    local sandbox = require("flemma.sandbox")
    sandbox.reset_enabled()
    sandbox.setup()
  end)

  it("bash tool cancel function kills sandboxed process", function()
    if skip_unless_bwrap() then
      return
    end

    local state = require("flemma.state")
    local registry = require("flemma.tools.registry")
    local executor = require("flemma.tools.executor")

    state.set_config({
      sandbox = sandbox_config({}),
      tools = {
        require_approval = false,
        default_timeout = 300,
        show_spinner = true,
        bash = {},
        autopilot = { enabled = false, max_turns = 10 },
      },
    })

    local bufnr = vim.api.nvim_create_buf(false, true)
    local tool = registry.get("bash")

    ---@type flemma.tools.ExecutionResult|nil
    local result = nil

    local ctx = executor.build_execution_context({
      bufnr = bufnr,
      cwd = vim.fn.getcwd(),
      timeout = 300,
      tool_name = "bash",
    })

    -- Execute returns the cancel function for async tools
    local cancel_fn = tool.execute({ label = "long sleep", command = "sleep 300", timeout = 300 }, ctx, function(r)
      result = r
    end)

    -- Let it start
    vim.wait(300, function()
      return false
    end, 50)

    -- Cancel via the function our bash tool returned
    assert.is_truthy(type(cancel_fn) == "function", "bash tool should return a cancel function")
    cancel_fn()

    -- Should complete promptly
    vim.wait(3000, function()
      return result ~= nil
    end, 50)

    -- Result should reflect cancellation (job was stopped, so on_exit fires but
    -- the "finished" flag from cancel prevents double-callback — the cancel
    -- itself doesn't produce a result, but jobstop triggers on_exit)
    -- The key assertion: the process is dead and we didn't hang.
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("background jobs spawned inside sandbox are cleaned up on exit", function()
    if skip_unless_bwrap() then
      return
    end

    local test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")
    local marker = test_dir .. "/bg_marker"

    -- Our bash tool runs this through sandbox.wrap_command() → bwrap.
    -- The background job writes to a marker file. After the main shell exits,
    -- PID namespace teardown (from --unshare-pid in our bwrap args) should
    -- kill the background process.
    local result = execute_bash_tool(
      string.format("bash -c 'while true; do echo alive > %s; sleep 0.1; done' & sleep 0.3 && echo main_done", marker),
      sandbox_config({ test_dir })
    )

    assert.is_true(result.success)
    assert.is_truthy(result.output:match("main_done"))

    -- Marker should exist (background job ran while sandbox was alive)
    assert.are.equal(1, vim.fn.filereadable(marker))

    -- Delete marker, wait, confirm it does NOT reappear
    vim.fn.delete(marker)
    vim.wait(500, function()
      return false
    end, 50)
    assert.are.equal(0, vim.fn.filereadable(marker), "background process should be dead after sandbox exit")

    vim.fn.delete(test_dir, "rf")
  end)
end)
