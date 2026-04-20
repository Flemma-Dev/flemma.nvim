package.loaded["flemma.notify"] = nil

describe("flemma.notify", function()
  local notify
  local captured

  local function flush_schedule()
    -- Wait 10ms so the scheduled callback runs before the test inspects captured.
    vim.wait(10, function()
      return false
    end)
  end

  before_each(function()
    package.loaded["flemma.notify"] = nil
    package.loaded["flemma.integrations.nvim_notify"] = nil
    package.loaded["notify"] = nil
    -- Block real nvim-notify from loading so detect logic defaults to default_impl.
    -- Individual backend-selection tests override this with their own preload.
    package.preload["notify"] = function()
      error("notify not available in this test")
    end
    notify = require("flemma.notify")
    captured = {}
    notify._set_impl(function(notification)
      table.insert(captured, notification)
      return notification
    end)
  end)

  after_each(function()
    notify._reset_impl()
    package.preload["notify"] = nil
    package.loaded["notify"] = nil
    package.loaded["flemma.integrations.nvim_notify"] = nil
  end)

  describe("level methods", function()
    it("notify.warn dispatches with WARN level and Flemma title", function()
      notify.warn("hello")
      flush_schedule()
      assert.are.equal(1, #captured)
      assert.are.equal(vim.log.levels.WARN, captured[1].level)
      assert.are.equal("hello", captured[1].message)
      assert.are.equal("Flemma", captured[1].opts.title)
    end)

    it("notify.error dispatches with ERROR level", function()
      notify.error("boom")
      flush_schedule()
      assert.are.equal(vim.log.levels.ERROR, captured[1].level)
    end)

    it("notify.info dispatches with INFO level", function()
      notify.info("fyi")
      flush_schedule()
      assert.are.equal(vim.log.levels.INFO, captured[1].level)
    end)

    it("notify.debug dispatches with DEBUG level", function()
      notify.debug("d")
      flush_schedule()
      assert.are.equal(vim.log.levels.DEBUG, captured[1].level)
    end)

    it("notify.trace dispatches with TRACE level", function()
      notify.trace("t")
      flush_schedule()
      assert.are.equal(vim.log.levels.TRACE, captured[1].level)
    end)

    it("notify.notify(msg, level, opts) dispatches at the given level", function()
      notify.notify("x", vim.log.levels.INFO)
      flush_schedule()
      assert.are.equal(vim.log.levels.INFO, captured[1].level)
      assert.are.equal("x", captured[1].message)
    end)

    it("uses provided opts.title when set", function()
      notify.warn("hello", { title = "Custom" })
      flush_schedule()
      assert.are.equal("Custom", captured[1].opts.title)
    end)

    it("returns a Notification record synchronously", function()
      local notification = notify.warn("hello")
      assert.are.equal(vim.log.levels.WARN, notification.level)
      assert.are.equal("hello", notification.message)
      assert.are.equal("Flemma", notification.opts.title)
      assert.is_nil(notification._native) -- impl hasn't run yet
    end)
  end)

  describe("once dedup", function()
    it("suppresses duplicate (level, message) pairs when once = true", function()
      notify.warn("hello", { once = true })
      notify.warn("hello", { once = true })
      flush_schedule()
      assert.are.equal(1, #captured)
    end)

    it("level disambiguates: warn 'X' and error 'X' are NOT deduped", function()
      notify.warn("X", { once = true })
      notify.error("X", { once = true })
      flush_schedule()
      assert.are.equal(2, #captured)
    end)

    it("returns the cached Notification on dedup hit", function()
      local first = notify.warn("hello", { once = true })
      local second = notify.warn("hello", { once = true })
      assert.are.equal(first, second)
    end)

    it("does not enqueue duplicates (synchronous dedup)", function()
      notify.warn("dup", { once = true })
      notify.warn("dup", { once = true })
      notify.warn("dup", { once = true })
      flush_schedule()
      assert.are.equal(1, #captured)
    end)

    it("without once = true, identical messages enqueue every time", function()
      notify.warn("repeat")
      notify.warn("repeat")
      flush_schedule()
      assert.are.equal(2, #captured)
    end)
  end)

  describe("test affordances", function()
    it("_set_impl overrides the dispatch implementation", function()
      local seen_in_custom = {}
      notify._set_impl(function(notification)
        table.insert(seen_in_custom, notification)
        return notification
      end)
      notify.warn("via custom")
      flush_schedule()
      assert.are.equal(1, #seen_in_custom)
      assert.are.equal(0, #captured) -- the before_each capture impl was overridden
    end)

    it("_reset_impl restores the auto-detected default", function()
      notify._set_impl(function(_) end) -- swap in a no-op
      notify._reset_impl()
      -- After reset, dispatch should call the (default) impl which uses vim.notify.
      -- Stub vim.notify to confirm.
      local original = vim.notify
      local seen_messages = {}
      vim.notify = function(msg, level) ---@diagnostic disable-line: duplicate-set-field
        table.insert(seen_messages, { msg = msg, level = level })
      end
      notify.warn("from reset")
      flush_schedule()
      vim.notify = original
      assert.are.equal(1, #seen_messages)
      assert.are.equal("Flemma: from reset", seen_messages[1].msg)
      assert.are.equal(vim.log.levels.WARN, seen_messages[1].level)
    end)

    it("_reset_impl works before any dispatch has happened", function()
      package.loaded["flemma.notify"] = nil
      local fresh = require("flemma.notify")
      -- No dispatch yet — call _reset_impl directly.
      fresh._reset_impl()
      -- Then dispatch and confirm it doesn't crash AND that the default impl actually ran.
      local original = vim.notify
      local seen_messages = {}
      vim.notify = function(msg, level) ---@diagnostic disable-line: duplicate-set-field
        table.insert(seen_messages, { msg = msg, level = level })
      end
      fresh.warn("after reset before dispatch")
      flush_schedule()
      vim.notify = original
      assert.are.equal(1, #seen_messages)
    end)
  end)

  describe("implicit scheduling", function()
    it("dispatch returns synchronously; impl runs on next event-loop tick", function()
      local notification = notify.warn("hello")
      assert.are.equal(0, #captured) -- impl hasn't run yet
      flush_schedule()
      assert.are.equal(1, #captured)
      assert.are.equal(notification, captured[1]) -- same table reference
    end)

    it("_native populated by impl is mutated onto the returned Notification", function()
      notify._set_impl(function(notification)
        return vim.tbl_extend("force", notification, { _native = "fake-record" })
      end)
      local notification = notify.warn("X")
      assert.is_nil(notification._native) -- before flush
      flush_schedule()
      assert.are.equal("fake-record", notification._native) -- after flush
    end)

    it("preserves FIFO order across sync-adjacent calls", function()
      notify.warn("first")
      notify.warn("second")
      notify.warn("third")
      flush_schedule()
      assert.are.equal(3, #captured)
      assert.are.equal("first", captured[1].message)
      assert.are.equal("second", captured[2].message)
      assert.are.equal("third", captured[3].message)
    end)
  end)

  describe("backend selection", function()
    it("falls back to default_impl when nvim-notify is not on the runtimepath", function()
      package.loaded["flemma.notify"] = nil
      package.loaded["flemma.integrations.nvim_notify"] = nil
      package.loaded["notify"] = nil
      -- Prevent real nvim-notify from loading so the integration cannot be detected.
      package.preload["notify"] = function()
        error("notify not available")
      end
      local fresh = require("flemma.notify")
      local original = vim.notify
      local seen_messages = {}
      vim.notify = function(msg, level) ---@diagnostic disable-line: duplicate-set-field
        table.insert(seen_messages, { msg = msg, level = level })
      end
      fresh.warn("hello")
      flush_schedule()
      vim.notify = original
      assert.are.equal(1, #seen_messages)
      assert.are.equal("Flemma: hello", seen_messages[1].msg)
    end)

    it("uses integration adapter when nvim-notify is on the runtimepath", function()
      package.loaded["flemma.notify"] = nil
      package.loaded["flemma.integrations.nvim_notify"] = nil
      package.loaded["notify"] = nil
      local nvim_notify_calls = {}
      package.preload["notify"] = function()
        return setmetatable({}, {
          __call = function(_, msg, level, opts)
            table.insert(nvim_notify_calls, { msg = msg, level = level, opts = opts })
            return { id = #nvim_notify_calls } -- fake native record
          end,
        })
      end
      local fresh = require("flemma.notify")
      fresh.warn("hello", { icon = "!", timeout = 500 })
      flush_schedule()
      package.preload["notify"] = nil
      package.loaded["notify"] = nil
      assert.are.equal(1, #nvim_notify_calls)
      assert.are.equal("hello", nvim_notify_calls[1].msg)
      assert.are.equal(vim.log.levels.WARN, nvim_notify_calls[1].level)
      assert.are.equal("Flemma", nvim_notify_calls[1].opts.title)
      assert.are.equal("!", nvim_notify_calls[1].opts.icon)
      assert.are.equal(500, nvim_notify_calls[1].opts.timeout)
    end)

    it("integration adapter passes replace handle's _native through", function()
      package.loaded["flemma.notify"] = nil
      package.loaded["flemma.integrations.nvim_notify"] = nil
      package.loaded["notify"] = nil
      local replace_seen
      package.preload["notify"] = function()
        return setmetatable({}, {
          __call = function(_, _, _, opts)
            replace_seen = opts.replace
            return "fake"
          end,
        })
      end
      local fresh = require("flemma.notify")
      local first = fresh.warn("first")
      flush_schedule()
      fresh.warn("second", { replace = first })
      flush_schedule()
      package.preload["notify"] = nil
      package.loaded["notify"] = nil
      assert.are.equal("fake", replace_seen)
    end)

    it("integration module loads cleanly when nvim-notify is not installed", function()
      -- Required by external require-checkers (nixpkgs' nvimRequireCheck, lazy.nvim
      -- eager loaders) that validate every lua/flemma/**/*.lua without installing
      -- optional runtime deps. The module must survive a missing `notify` and
      -- simply not expose M.impl so flemma.notify falls back to vim.notify.
      package.loaded["flemma.integrations.nvim_notify"] = nil
      package.loaded["notify"] = nil
      -- before_each's preload["notify"] errors, mimicking a missing plugin.
      local ok, integration = pcall(require, "flemma.integrations.nvim_notify")
      assert.is_true(ok, "expected module to load cleanly; got error: " .. tostring(integration))
      assert.is_table(integration)
      assert.is_nil(integration.impl)
    end)

    it("integration adapter survives pcall failure inside nvim-notify", function()
      package.loaded["flemma.notify"] = nil
      package.loaded["flemma.integrations.nvim_notify"] = nil
      package.loaded["notify"] = nil
      local nvim_notify_calls = 0
      package.preload["notify"] = function()
        return setmetatable({}, {
          __call = function()
            nvim_notify_calls = nvim_notify_calls + 1
            error("simulated nvim-notify failure")
          end,
        })
      end
      local fresh = require("flemma.notify")
      -- Must not raise.
      local notification = fresh.warn("hello")
      flush_schedule()
      package.preload["notify"] = nil
      package.loaded["notify"] = nil
      -- Confirm the adapter was selected and called (not silently bypassed for default_impl).
      assert.are.equal(1, nvim_notify_calls)
      assert.is_nil(notification._native) -- failure degrades silently
    end)
  end)
end)
