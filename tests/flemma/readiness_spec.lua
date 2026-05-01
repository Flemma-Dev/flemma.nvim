describe("flemma.readiness", function()
  local readiness

  before_each(function()
    package.loaded["flemma.readiness"] = nil
    readiness = require("flemma.readiness")
    readiness._reset_for_tests()
  end)

  describe("Suspense + is_suspense", function()
    it("error(Suspense.new(...)) is caught by pcall and identified by is_suspense", function()
      local boundary = readiness.get_or_create_boundary("k1", function(done)
        done()
      end)
      local ok, err = pcall(function()
        error(readiness.Suspense.new("test", boundary))
      end)
      assert.is_false(ok)
      assert.is_true(readiness.is_suspense(err))
      assert.equals("test", err.message)
      assert.equals(boundary, err.boundary)
    end)

    it("is_suspense returns false for non-suspense errors", function()
      assert.is_false(readiness.is_suspense("plain string"))
      assert.is_false(readiness.is_suspense({ message = "fake" }))
      assert.is_false(readiness.is_suspense(nil))
    end)
  end)

  describe("get_or_create_boundary", function()
    it("returns the same boundary for the same key", function()
      local runner_calls = 0
      local b1 = readiness.get_or_create_boundary("dup", function(done)
        runner_calls = runner_calls + 1
        done()
      end)
      local b2 = readiness.get_or_create_boundary("dup", function(_done)
        error("must not be called")
      end)
      assert.equals(b1, b2)
      vim.wait(50, function()
        return runner_calls > 0
      end)
      assert.equals(1, runner_calls)
    end)

    it("creates fresh boundary after previous one completed", function()
      local first_done
      readiness.get_or_create_boundary("k", function(done)
        first_done = done
      end)
      vim.wait(20, function()
        return first_done ~= nil
      end)
      first_done({ ok = true })
      vim.wait(20)
      local second_runner_called = false
      readiness.get_or_create_boundary("k", function(done)
        second_runner_called = true
        done()
      end)
      vim.wait(20, function()
        return second_runner_called
      end)
      assert.is_true(second_runner_called)
    end)
  end)

  describe("Boundary:subscribe", function()
    it("fires on_complete with runner's result", function()
      local b = readiness.get_or_create_boundary("s1", function(done)
        vim.schedule(function()
          done({ ok = true, value = 42 })
        end)
      end)
      local received
      b:subscribe(function(result)
        received = result
      end)
      vim.wait(50, function()
        return received ~= nil
      end)
      assert.same({ ok = true, value = 42 }, received)
    end)

    it("does not fire when subscription is cancelled", function()
      local b = readiness.get_or_create_boundary("s2", function(done)
        vim.schedule(function()
          done({ ok = true })
        end)
      end)
      local fired = false
      local sub = b:subscribe(function()
        fired = true
      end)
      sub:cancel()
      vim.wait(50)
      assert.is_false(fired)
      assert.is_true(sub.cancelled)
    end)

    it("multiple subscribers all fire", function()
      local b = readiness.get_or_create_boundary("s3", function(done)
        vim.schedule(function()
          done({ ok = true })
        end)
      end)
      local count = 0
      b:subscribe(function()
        count = count + 1
      end)
      b:subscribe(function()
        count = count + 1
      end)
      vim.wait(50, function()
        return count == 2
      end)
      assert.equals(2, count)
    end)

    it("fires immediately (via schedule) when subscribing after boundary completed", function()
      local captured_done
      local b = readiness.get_or_create_boundary("late", function(done)
        captured_done = done
      end)
      vim.wait(20, function()
        return captured_done ~= nil
      end)
      captured_done({ ok = true, late = true })
      vim.wait(20)
      local received
      b:subscribe(function(result)
        received = result
      end)
      vim.wait(50, function()
        return received ~= nil
      end)
      assert.same({ ok = true, late = true }, received)
    end)
  end)

  describe("concurrent consumers share one runner", function()
    it("two get_or_create_boundary calls + two subscribes → one runner, both fire", function()
      local runner_invocations = 0
      local function make_runner(done_on_invoke)
        return function(done)
          runner_invocations = runner_invocations + 1
          vim.schedule(function()
            done(done_on_invoke)
          end)
        end
      end

      local b1 = readiness.get_or_create_boundary("shared", make_runner({ ok = true, who = "first" }))
      local b2 = readiness.get_or_create_boundary("shared", make_runner({ ok = true, who = "second" }))
      assert.equals(b1, b2)

      local results = {}
      b1:subscribe(function(r)
        table.insert(results, r)
      end)
      b2:subscribe(function(r)
        table.insert(results, r)
      end)

      vim.wait(50, function()
        return #results == 2
      end)
      assert.equals(1, runner_invocations)
      assert.equals(2, #results)
      assert.equals("first", results[1].who)
      assert.equals("first", results[2].who)
    end)
  end)

  describe("runner panic isolation", function()
    it("sync panic in runner completes the boundary with ok=false", function()
      local b = readiness.get_or_create_boundary("panic", function(_done)
        error("boom")
      end)
      local result
      b:subscribe(function(r)
        result = r
      end)
      vim.wait(50, function()
        return result ~= nil
      end)
      assert.is_false(result.ok)
      assert.equals("readiness", result.diagnostics[1].resolver)
      assert.matches("runner panic", result.diagnostics[1].message)
    end)

    it("panic after done() does not double-complete", function()
      local complete_count = 0
      local b = readiness.get_or_create_boundary("panic2", function(done)
        done({ ok = true, value = 1 })
        error("boom after done")
      end)
      b:subscribe(function()
        complete_count = complete_count + 1
      end)
      vim.wait(50)
      assert.equals(1, complete_count)
    end)
  end)
end)
