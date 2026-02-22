describe("sandbox bwrap backend", function()
  local bwrap

  before_each(function()
    package.loaded["flemma.sandbox.backends.bwrap"] = nil
    bwrap = require("flemma.sandbox.backends.bwrap")
  end)

  describe("available", function()
    it("returns error on non-Linux", function()
      local original_has = vim.fn.has
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.fn.has = function(feature)
        if feature == "linux" then
          return 0
        end
        return original_has(feature)
      end

      local ok, err = bwrap.available({})
      assert.is_false(ok)
      assert.is_truthy(err:match("requires Linux"))

      vim.fn.has = original_has
    end)

    it("returns error when bwrap not installed", function()
      -- Only test on Linux
      if vim.fn.has("linux") ~= 1 then
        pending("Test requires Linux")
        return
      end

      local ok, err = bwrap.available({ path = "/nonexistent/bwrap-fake" })
      assert.is_false(ok)
      assert.is_truthy(err:match("not found"))
    end)
  end)

  describe("wrap", function()
    -- These tests validate argument construction — they don't need a real bwrap binary.
    -- We mock available() to always return true.
    local original_available

    before_each(function()
      original_available = bwrap.available
      ---@diagnostic disable-next-line: duplicate-set-field
      bwrap.available = function()
        return true, nil
      end
    end)

    after_each(function()
      bwrap.available = original_available
    end)

    it("returns correct argument structure for default policy", function()
      local policy = {
        rw_paths = { "/home/user/project", "/tmp" },
        network = true,
        allow_privileged = false,
      }
      local inner = { "bash", "-c", "echo hello" }
      local args, err = bwrap.wrap(policy, {}, inner)

      assert.is_nil(err)
      assert.is_not_nil(args)
      assert.are.equal("bwrap", args[1])
      -- Should contain --ro-bind / /
      assert.is_truthy(vim.tbl_contains(args, "--ro-bind"))
      -- Should end with the inner command
      assert.are.equal("bash", args[#args - 2])
      assert.are.equal("-c", args[#args - 1])
      assert.are.equal("echo hello", args[#args])
    end)

    it("includes --bind for each rw_path", function()
      local policy = {
        rw_paths = { "/home/user/project", "/data/workspace" },
        network = true,
        allow_privileged = false,
      }
      local args = bwrap.wrap(policy, {}, { "echo" })

      -- Find --bind entries
      local binds = {}
      for i, arg in ipairs(args) do
        if arg == "--bind" and i < #args - 1 then
          table.insert(binds, { args[i + 1], args[i + 2] })
        end
      end
      assert.are.equal(2, #binds)
      assert.are.same({ "/home/user/project", "/home/user/project" }, binds[1])
      assert.are.same({ "/data/workspace", "/data/workspace" }, binds[2])
    end)

    it("includes --unshare-user when allow_privileged = false", function()
      local policy = {
        rw_paths = {},
        network = true,
        allow_privileged = false,
      }
      local args = bwrap.wrap(policy, {}, { "echo" })
      assert.is_truthy(vim.tbl_contains(args, "--unshare-user"))
    end)

    it("omits --unshare-user when allow_privileged = true", function()
      local policy = {
        rw_paths = {},
        network = true,
        allow_privileged = true,
      }
      local args = bwrap.wrap(policy, {}, { "echo" })
      assert.is_falsy(vim.tbl_contains(args, "--unshare-user"))
    end)

    it("includes --unshare-net when network = false", function()
      local policy = {
        rw_paths = {},
        network = false,
        allow_privileged = false,
      }
      local args = bwrap.wrap(policy, {}, { "echo" })
      assert.is_truthy(vim.tbl_contains(args, "--unshare-net"))
      assert.is_falsy(vim.tbl_contains(args, "--share-net"))
    end)

    it("includes --share-net when network = true", function()
      local policy = {
        rw_paths = {},
        network = true,
        allow_privileged = false,
      }
      local args = bwrap.wrap(policy, {}, { "echo" })
      assert.is_truthy(vim.tbl_contains(args, "--share-net"))
      assert.is_falsy(vim.tbl_contains(args, "--unshare-net"))
    end)

    it("includes extra_args from backend config", function()
      local policy = {
        rw_paths = {},
        network = true,
        allow_privileged = false,
      }
      local backend_config = {
        extra_args = { "--tmpfs", "/tmp" },
      }
      local args = bwrap.wrap(policy, backend_config, { "echo" })
      -- extra_args should appear before the inner command
      local found_tmpfs = false
      for i, arg in ipairs(args) do
        if arg == "--tmpfs" and args[i + 1] == "/tmp" then
          found_tmpfs = true
          break
        end
      end
      assert.is_true(found_tmpfs)
    end)

    it("uses custom bwrap path", function()
      local policy = {
        rw_paths = {},
        network = true,
        allow_privileged = false,
      }
      local backend_config = { path = "/usr/local/bin/bwrap" }
      local args = bwrap.wrap(policy, backend_config, { "echo" })
      assert.are.equal("/usr/local/bin/bwrap", args[1])
    end)

    it("appends inner_cmd at the end", function()
      local policy = {
        rw_paths = {},
        network = true,
        allow_privileged = false,
      }
      local inner = { "bash", "-c", "ls -la" }
      local args = bwrap.wrap(policy, {}, inner)
      assert.are.equal("bash", args[#args - 2])
      assert.are.equal("-c", args[#args - 1])
      assert.are.equal("ls -la", args[#args])
    end)

    it("includes lifecycle safety flags", function()
      local policy = {
        rw_paths = {},
        network = true,
        allow_privileged = false,
      }
      local args = bwrap.wrap(policy, {}, { "echo" })
      assert.is_truthy(vim.tbl_contains(args, "--die-with-parent"))
      assert.is_truthy(vim.tbl_contains(args, "--new-session"))
      assert.is_truthy(vim.tbl_contains(args, "--unshare-pid"))
      assert.is_truthy(vim.tbl_contains(args, "--unshare-uts"))
      assert.is_truthy(vim.tbl_contains(args, "--unshare-ipc"))
    end)

    it("re-binds /run/current-system read-only on NixOS", function()
      local policy = {
        rw_paths = {},
        network = true,
        allow_privileged = false,
      }
      local args = bwrap.wrap(policy, {}, { "echo" })

      -- On NixOS (where /run/current-system exists), bwrap should
      -- ro-bind it after the /run tmpfs so system packages stay visible.
      if vim.uv.fs_stat("/run/current-system") then
        local found = false
        for i, arg in ipairs(args) do
          if arg == "--ro-bind" and args[i + 1] == "/run/current-system" and args[i + 2] == "/run/current-system" then
            found = true
            break
          end
        end
        assert.is_true(found, "expected --ro-bind /run/current-system on NixOS")
      else
        -- On non-NixOS, the bind should not be present
        local found = false
        for i, arg in ipairs(args) do
          if arg == "--ro-bind" and args[i + 1] == "/run/current-system" then
            found = true
            break
          end
        end
        assert.is_false(found, "should not bind /run/current-system on non-NixOS")
      end
    end)

    it("includes dev and proc mounts", function()
      local policy = {
        rw_paths = {},
        network = true,
        allow_privileged = false,
      }
      local args = bwrap.wrap(policy, {}, { "echo" })
      assert.is_truthy(vim.tbl_contains(args, "--dev"))
      assert.is_truthy(vim.tbl_contains(args, "--proc"))
    end)
  end)
end)
