describe("sandbox policy layer", function()
  local sandbox
  local bwrap
  local config_facade
  local schema

  ---Apply sandbox config to the SETUP layer.
  ---@param sandbox_opts table
  local function apply_sandbox(sandbox_opts)
    config_facade.apply(config_facade.LAYERS.SETUP, { sandbox = sandbox_opts })
  end

  before_each(function()
    package.loaded["flemma.sandbox"] = nil
    package.loaded["flemma.sandbox.backends.bwrap"] = nil
    package.loaded["flemma.tools.approval"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.schema"] = nil
    sandbox = require("flemma.sandbox")
    bwrap = require("flemma.sandbox.backends.bwrap")
    config_facade = require("flemma.config")
    schema = require("flemma.config.schema")

    -- Initialize config facade with schema defaults
    config_facade.init(schema)

    -- Reset runtime override and registry
    sandbox.reset_enabled()
    sandbox.clear()

    -- Register bwrap backend (mirrors what sandbox.setup() does)
    sandbox.register("bwrap", {
      available = bwrap.available,
      wrap = bwrap.wrap,
      priority = 100,
      description = "Bubblewrap (Linux)",
    })

    -- Set a config with sandbox disabled by default
    -- Note: backends sub-tree is omitted because DISCOVER requires backends
    -- to have config_schema registered. bwrap's default config comes from its
    -- schema materialization when registered with config_schema in sandbox.setup().
    apply_sandbox({
      enabled = false,
      backend = "bwrap",
      policy = {
        rw_paths = { "urn:flemma:cwd", "urn:flemma:buffer:path", "/tmp" },
        network = true,
        allow_privileged = false,
      },
    })
  end)

  describe("resolve_config", function()
    it("merges global and per-buffer config", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local w = config_facade.writer(bufnr, config_facade.LAYERS.FRONTMATTER)
      w.sandbox.enabled = true
      w.sandbox.policy.network = false
      local cfg = sandbox.resolve_config(bufnr)
      assert.is_true(cfg.enabled)
      assert.is_false(cfg.policy.network)
      -- Other defaults preserved from SETUP layer
      assert.are.same({ "urn:flemma:cwd", "urn:flemma:buffer:path", "/tmp" }, cfg.policy.rw_paths)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("uses global config when no buffer", function()
      local cfg = sandbox.resolve_config()
      assert.is_false(cfg.enabled)
      assert.are.equal("bwrap", cfg.backend)
    end)
  end)

  describe("is_enabled", function()
    it("returns false when sandbox.enabled = false", function()
      assert.is_false(sandbox.is_enabled())
    end)

    it("returns true with per-buffer override", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local w = config_facade.writer(bufnr, config_facade.LAYERS.FRONTMATTER)
      w.sandbox.enabled = true
      assert.is_true(sandbox.is_enabled(bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("get_policy", function()
    it("expands urn:flemma:cwd to global working directory", function()
      apply_sandbox({
        enabled = true,
        policy = { rw_paths = { "urn:flemma:cwd" } },
      })
      local bufnr = vim.api.nvim_create_buf(false, true)
      local policy = sandbox.get_policy(bufnr)
      local cwd = vim.fn.resolve(vim.fn.fnamemodify(vim.fn.getcwd(), ":p"))
      assert.are.same({ cwd }, policy.rw_paths)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("expands urn:flemma:buffer:path to buffer file directory", function()
      apply_sandbox({
        enabled = true,
        policy = { rw_paths = { "urn:flemma:buffer:path" } },
      })
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, "/tmp/test_chat.chat")
      local policy = sandbox.get_policy(bufnr)
      local expected = vim.fn.resolve(vim.fn.fnamemodify("/tmp/test_chat.chat", ":p:h"))
      assert.are.same({ expected }, policy.rw_paths)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("skips urn:flemma:buffer:path for unnamed buffers", function()
      apply_sandbox({
        enabled = true,
        policy = { rw_paths = { "urn:flemma:buffer:path" } },
      })
      local bufnr = vim.api.nvim_create_buf(false, true)
      local policy = sandbox.get_policy(bufnr)
      assert.are.same({}, policy.rw_paths)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("skips unset $VAR without default", function()
      apply_sandbox({
        enabled = true,
        policy = { rw_paths = { "$FLEMMA_TEST_NONEXISTENT_VAR_12345", "/tmp" } },
      })
      local bufnr = vim.api.nvim_create_buf(false, true)
      local policy = sandbox.get_policy(bufnr)
      local expected_tmp = vim.fn.resolve(vim.fn.fnamemodify("/tmp", ":p"))
      assert.are.same({ expected_tmp }, policy.rw_paths)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("expands $HOME from environment", function()
      apply_sandbox({
        enabled = true,
        policy = { rw_paths = { "$HOME" } },
      })
      local bufnr = vim.api.nvim_create_buf(false, true)
      local policy = sandbox.get_policy(bufnr)
      local expected = vim.fn.resolve(vim.fn.fnamemodify(os.getenv("HOME"), ":p"))
      assert.are.same({ expected }, policy.rw_paths)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("expands ${VAR:-default} with fallback", function()
      apply_sandbox({
        enabled = true,
        policy = { rw_paths = { "${FLEMMA_TEST_NONEXISTENT:-/fallback}" } },
      })
      local bufnr = vim.api.nvim_create_buf(false, true)
      local policy = sandbox.get_policy(bufnr)
      local expected = vim.fn.resolve(vim.fn.fnamemodify("/fallback", ":p"))
      assert.are.same({ expected }, policy.rw_paths)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("deduplicates paths where parent subsumes child", function()
      apply_sandbox({
        enabled = true,
        policy = { rw_paths = { "/tmp", "/tmp/foo" } },
      })
      local bufnr = vim.api.nvim_create_buf(false, true)
      local policy = sandbox.get_policy(bufnr)
      assert.are.equal(1, #policy.rw_paths)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("deduplicates paths after expansion", function()
      apply_sandbox({
        enabled = true,
        policy = { rw_paths = { "/tmp", "/tmp" } },
      })
      local bufnr = vim.api.nvim_create_buf(false, true)
      local policy = sandbox.get_policy(bufnr)
      assert.are.equal(1, #policy.rw_paths)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("normalizes relative paths to absolute", function()
      apply_sandbox({
        enabled = true,
        policy = { rw_paths = { "." } },
      })
      local bufnr = vim.api.nvim_create_buf(false, true)
      local policy = sandbox.get_policy(bufnr)
      -- Should be an absolute path (starts with /)
      assert.is_truthy(policy.rw_paths[1]:match("^/"))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("is_path_writable", function()
    it("returns true for paths in resolved rw_paths", function()
      apply_sandbox({
        enabled = true,
        policy = { rw_paths = { "/tmp" } },
      })
      local bufnr = vim.api.nvim_create_buf(false, true)
      assert.is_true(sandbox.is_path_writable("/tmp/test.txt", bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("returns false for paths outside rw_paths", function()
      apply_sandbox({
        enabled = true,
        policy = { rw_paths = { "/tmp" } },
      })
      local bufnr = vim.api.nvim_create_buf(false, true)
      assert.is_false(sandbox.is_path_writable("/home/user/.bashrc", bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("returns true when sandbox disabled", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      assert.is_true(sandbox.is_path_writable("/etc/passwd", bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("wrap_command", function()
    it("returns inner_cmd unchanged when disabled", function()
      local inner = { "bash", "-c", "echo hello" }
      local bufnr = vim.api.nvim_create_buf(false, true)
      local result, err = sandbox.wrap_command(inner, bufnr)
      assert.is_nil(err)
      assert.are.same(inner, result)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("returns error for unknown backend", function()
      apply_sandbox({
        enabled = true,
        backend = "nonexistent",
        policy = { rw_paths = {} },
      })
      local inner = { "bash", "-c", "echo hello" }
      local bufnr = vim.api.nvim_create_buf(false, true)
      local result, err = sandbox.wrap_command(inner, bufnr)
      assert.is_nil(result)
      assert.is_truthy(err:match("Unknown sandbox backend"))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("validate_backend", function()
    it("returns true when disabled", function()
      local ok, err = sandbox.validate_backend()
      assert.is_true(ok)
      assert.is_nil(err)
    end)
  end)

  describe("runtime override", function()
    it("set_enabled(true) overrides config enabled = false", function()
      assert.is_false(sandbox.is_enabled())
      sandbox.set_enabled(true)
      assert.is_true(sandbox.is_enabled())
    end)

    it("set_enabled(false) overrides config enabled = true", function()
      apply_sandbox({
        enabled = true,
        backend = "bwrap",
        policy = { rw_paths = {} },
      })
      assert.is_true(sandbox.is_enabled())
      sandbox.set_enabled(false)
      assert.is_false(sandbox.is_enabled())
    end)

    it("reset_enabled() reverts to config-driven behavior", function()
      sandbox.set_enabled(true)
      assert.is_true(sandbox.is_enabled())
      sandbox.reset_enabled()
      assert.is_false(sandbox.is_enabled())
    end)

    it("runtime override takes precedence over per-buffer frontmatter", function()
      sandbox.set_enabled(false)
      local bufnr = vim.api.nvim_create_buf(false, true)
      local w = config_facade.writer(bufnr, config_facade.LAYERS.FRONTMATTER)
      w.sandbox.enabled = true
      assert.is_false(sandbox.is_enabled(bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("get_override returns nil by default", function()
      assert.is_nil(sandbox.get_override())
    end)

    it("get_override returns the set value", function()
      sandbox.set_enabled(true)
      assert.is_true(sandbox.get_override())
      sandbox.set_enabled(false)
      assert.is_false(sandbox.get_override())
    end)
  end)

  describe("backend registry", function()
    it("register and get a backend", function()
      sandbox.clear()
      sandbox.register("test_backend", {
        available = function()
          return true, nil
        end,
        wrap = function(_, _, inner)
          return inner, nil
        end,
        priority = 50,
        description = "Test backend",
      })
      local entry = sandbox.get("test_backend")
      assert.is_not_nil(entry)
      assert.are.equal("test_backend", entry.name)
      assert.are.equal(50, entry.priority)
    end)

    it("replaces existing backend on re-register", function()
      sandbox.clear()
      sandbox.register("dup", {
        available = function()
          return false, "old"
        end,
        wrap = function()
          return nil, "old"
        end,
        priority = 10,
      })
      sandbox.register("dup", {
        available = function()
          return true, nil
        end,
        wrap = function(_, _, inner)
          return inner, nil
        end,
        priority = 90,
      })
      assert.are.equal(1, sandbox.count())
      local entry = sandbox.get("dup")
      assert.are.equal(90, entry.priority)
    end)

    it("unregister removes a backend", function()
      sandbox.clear()
      sandbox.register("removable", {
        available = function()
          return true, nil
        end,
        wrap = function(_, _, inner)
          return inner, nil
        end,
      })
      assert.is_true(sandbox.unregister("removable"))
      assert.is_nil(sandbox.get("removable"))
      assert.are.equal(0, sandbox.count())
    end)

    it("unregister returns false for unknown name", function()
      assert.is_false(sandbox.unregister("no_such_backend"))
    end)

    it("get_all returns backends sorted by priority descending", function()
      sandbox.clear()
      sandbox.register("low", {
        available = function()
          return true, nil
        end,
        wrap = function(_, _, inner)
          return inner, nil
        end,
        priority = 10,
      })
      sandbox.register("high", {
        available = function()
          return true, nil
        end,
        wrap = function(_, _, inner)
          return inner, nil
        end,
        priority = 90,
      })
      local all = sandbox.get_all()
      assert.are.equal("high", all[1].name)
      assert.are.equal("low", all[2].name)
    end)

    it("clear removes all backends", function()
      sandbox.register("a", {
        available = function()
          return true, nil
        end,
        wrap = function(_, _, inner)
          return inner, nil
        end,
      })
      sandbox.clear()
      assert.are.equal(0, sandbox.count())
    end)

    it("setup registers the bwrap backend", function()
      sandbox.clear()
      sandbox.setup()
      local entry = sandbox.get("bwrap")
      assert.is_not_nil(entry)
      assert.are.equal(100, entry.priority)
    end)

    it("setup does not overwrite an existing registration", function()
      sandbox.clear()
      sandbox.register("bwrap", {
        available = function()
          return true, nil
        end,
        wrap = function(_, _, inner)
          return inner, nil
        end,
        priority = 42,
        description = "Custom bwrap",
      })
      sandbox.setup()
      local entry = sandbox.get("bwrap")
      assert.are.equal(42, entry.priority)
    end)

    it("has() returns true for a registered backend", function()
      sandbox.clear()
      sandbox.register("test_has", {
        available = function()
          return true, nil
        end,
        wrap = function(_, _, inner)
          return inner, nil
        end,
      })
      assert.is_true(sandbox.has("test_has"))
    end)

    it("has() returns false for an unknown backend", function()
      assert.is_false(sandbox.has("nonexistent_backend"))
    end)
  end)

  describe("auto-detection", function()
    it("detect_available_backend picks highest-priority available backend", function()
      sandbox.clear()
      sandbox.register("low_available", {
        available = function()
          return true, nil
        end,
        wrap = function(_, _, inner)
          return inner, nil
        end,
        priority = 10,
      })
      sandbox.register("high_unavailable", {
        available = function()
          return false, "not here"
        end,
        wrap = function()
          return nil, "nope"
        end,
        priority = 90,
      })
      sandbox.register("mid_available", {
        available = function()
          return true, nil
        end,
        wrap = function(_, _, inner)
          return inner, nil
        end,
        priority = 50,
      })
      apply_sandbox({ enabled = true, backend = "auto", policy = { rw_paths = {} } })
      local detected, _ = sandbox.detect_available_backend()
      assert.are.equal("mid_available", detected)
    end)

    it("returns nil with diagnostic when no backend is available", function()
      sandbox.clear()
      sandbox.register("broken", {
        available = function()
          return false, "broken"
        end,
        wrap = function()
          return nil, "broken"
        end,
        priority = 50,
      })
      apply_sandbox({ enabled = true, backend = "auto", policy = { rw_paths = {} } })
      local detected, diagnostic = sandbox.detect_available_backend()
      assert.is_nil(detected)
      assert.is_truthy(diagnostic:match("No sandbox backend available"))
      assert.is_truthy(diagnostic:match("broken"))
    end)

    it("validate_backend auto-detects when backend is 'auto'", function()
      sandbox.clear()
      sandbox.register("mock", {
        available = function()
          return true, nil
        end,
        wrap = function(_, _, inner)
          return inner, nil
        end,
        priority = 50,
      })
      apply_sandbox({ enabled = true, backend = "auto", policy = { rw_paths = {} } })
      local ok, err = sandbox.validate_backend()
      assert.is_true(ok)
      assert.is_nil(err)
    end)

    it("validate_backend returns false when auto-detect finds nothing", function()
      sandbox.clear()
      apply_sandbox({ enabled = true, backend = "auto", policy = { rw_paths = {} } })
      local ok, err = sandbox.validate_backend()
      assert.is_false(ok)
      assert.is_truthy(err:match("No sandbox backend available"))
    end)

    it("wrap_command uses auto-detected backend", function()
      sandbox.clear()
      sandbox.register("passthrough", {
        available = function()
          return true, nil
        end,
        wrap = function(_, _, inner)
          return vim.list_extend({ "wrapped" }, inner), nil
        end,
        priority = 50,
      })
      apply_sandbox({ enabled = true, backend = "auto", policy = { rw_paths = {} } })
      local bufnr = vim.api.nvim_create_buf(false, true)
      local result, err = sandbox.wrap_command({ "echo", "hi" }, bufnr)
      assert.is_nil(err)
      assert.are.same({ "wrapped", "echo", "hi" }, result)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("explicit backend skips auto-detection", function()
      sandbox.clear()
      sandbox.register("explicit_one", {
        available = function()
          return true, nil
        end,
        wrap = function(_, _, inner)
          return vim.list_extend({ "explicit" }, inner), nil
        end,
        priority = 10,
      })
      sandbox.register("higher_one", {
        available = function()
          return true, nil
        end,
        wrap = function(_, _, inner)
          return vim.list_extend({ "higher" }, inner), nil
        end,
        priority = 90,
      })
      apply_sandbox({ enabled = true, backend = "explicit_one", policy = { rw_paths = {} } })
      local bufnr = vim.api.nvim_create_buf(false, true)
      local result, _ = sandbox.wrap_command({ "test" }, bufnr)
      assert.are.same({ "explicit", "test" }, result)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("detection cache", function()
    it("caches auto-detection result across calls", function()
      sandbox.clear()
      local call_count = 0
      sandbox.register("counting", {
        available = function()
          call_count = call_count + 1
          return true, nil
        end,
        wrap = function(_, _, inner)
          return inner, nil
        end,
        priority = 50,
      })
      apply_sandbox({ enabled = true, backend = "auto", policy = { rw_paths = {} } })
      local bufnr = vim.api.nvim_create_buf(false, true)

      -- First call runs detection
      sandbox.wrap_command({ "a" }, bufnr)
      local first_count = call_count

      -- Second call should use cache (available not called again)
      sandbox.wrap_command({ "b" }, bufnr)
      assert.are.equal(first_count, call_count)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("invalidates cache when registry changes", function()
      sandbox.clear()
      local call_count = 0
      sandbox.register("counting", {
        available = function()
          call_count = call_count + 1
          return true, nil
        end,
        wrap = function(_, _, inner)
          return inner, nil
        end,
        priority = 50,
      })
      apply_sandbox({ enabled = true, backend = "auto", policy = { rw_paths = {} } })
      local bufnr = vim.api.nvim_create_buf(false, true)

      -- Prime the cache
      sandbox.wrap_command({ "a" }, bufnr)
      local after_first = call_count

      -- Register a new backend (bumps generation)
      sandbox.register("other", {
        available = function()
          return false, "nope"
        end,
        wrap = function()
          return nil, "nope"
        end,
        priority = 10,
      })

      -- Next call must re-detect
      sandbox.wrap_command({ "b" }, bufnr)
      assert.is_true(call_count > after_first)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("invalidates cache when backends config changes", function()
      local s = require("flemma.schema")
      sandbox.clear()
      local call_count = 0
      sandbox.register("counting", {
        available = function()
          call_count = call_count + 1
          return true, nil
        end,
        wrap = function(_, _, inner)
          return inner, nil
        end,
        priority = 50,
        config_schema = s.object({ path = s.optional(s.string()) }),
      })
      apply_sandbox({
        enabled = true,
        backend = "auto",
        policy = { rw_paths = {} },
        backends = { counting = { path = "/usr/bin/count" } },
      })
      local bufnr = vim.api.nvim_create_buf(false, true)

      -- Prime the cache
      sandbox.wrap_command({ "a" }, bufnr)
      local after_first = call_count

      -- Change backends config
      apply_sandbox({
        enabled = true,
        backend = "auto",
        policy = { rw_paths = {} },
        backends = { counting = { path = "/different/path" } },
      })

      -- Next call must re-detect (backends config changed)
      sandbox.wrap_command({ "b" }, bufnr)
      assert.is_true(call_count > after_first)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("graceful degradation", function()
    it("wrap_command runs unsandboxed in auto mode when no backend available", function()
      sandbox.clear()
      apply_sandbox({ enabled = true, backend = "auto", policy = { rw_paths = {} } })
      local bufnr = vim.api.nvim_create_buf(false, true)
      local inner = { "echo", "hello" }
      local result, err = sandbox.wrap_command(inner, bufnr)
      -- Auto mode: graceful degradation — returns inner_cmd unchanged
      assert.is_nil(err)
      assert.are.same(inner, result)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("wrap_command runs unsandboxed in required mode when no backend available", function()
      sandbox.clear()
      apply_sandbox({ enabled = true, backend = "required", policy = { rw_paths = {} } })
      local bufnr = vim.api.nvim_create_buf(false, true)
      local inner = { "echo", "hello" }
      local result, err = sandbox.wrap_command(inner, bufnr)
      -- Required mode: same graceful degradation as auto (notification differs, not behavior)
      assert.is_nil(err)
      assert.are.same(inner, result)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("wrap_command errors for explicit backend that is not registered", function()
      sandbox.clear()
      apply_sandbox({ enabled = true, backend = "nonexistent", policy = { rw_paths = {} } })
      local bufnr = vim.api.nvim_create_buf(false, true)
      local result, err = sandbox.wrap_command({ "echo" }, bufnr)
      -- Explicit backend: user asked for it, fail if unavailable
      assert.is_nil(result)
      assert.is_truthy(err:match("Unknown sandbox backend"))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("late backend registration activates sandbox for auto mode", function()
      sandbox.clear()
      apply_sandbox({ enabled = true, backend = "auto", policy = { rw_paths = {} } })
      local bufnr = vim.api.nvim_create_buf(false, true)

      -- No backends registered — wrap_command returns inner_cmd unchanged
      local inner = { "echo", "hello" }
      local result, err = sandbox.wrap_command(inner, bufnr)
      assert.is_nil(err)
      assert.are.same(inner, result)

      -- User registers a backend after init
      sandbox.register("late_backend", {
        available = function()
          return true, nil
        end,
        wrap = function(_, _, cmd)
          return vim.list_extend({ "sandboxed" }, cmd), nil
        end,
        priority = 50,
      })

      -- Now wrap_command should detect and use the new backend
      local result2, err2 = sandbox.wrap_command(inner, bufnr)
      assert.is_nil(err2)
      assert.are.same({ "sandboxed", "echo", "hello" }, result2)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
