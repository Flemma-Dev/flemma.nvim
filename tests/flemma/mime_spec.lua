local stub = require("luassert.stub")

describe("MIME type detection", function()
  local mime
  local stubs = {}

  local function create_stub(obj, method, replacement)
    local s = stub(obj, method, replacement)
    table.insert(stubs, s)
    return s
  end

  before_each(function()
    -- Clear the module cache to ensure fresh state
    package.loaded["flemma.mime"] = nil
    mime = require("flemma.mime")
    stubs = {}
  end)

  after_each(function()
    -- Restore all stubs
    for _, s in ipairs(stubs) do
      s:revert()
    end
    stubs = {}
  end)

  describe("get_mime_type", function()
    it("returns correct MIME type when file command succeeds", function()
      -- Mock os.execute to simulate file command being available
      local os_execute_stub = create_stub(os, "execute")
      os_execute_stub.on_call_with("command -v file >/dev/null 2>&1").returns(0)

      -- Mock io.popen to simulate successful file command execution
      local mock_handle = {
        read = function(self, mode)
          if mode == "*a" then
            return "image/png\n"
          end
        end,
        close = function(self)
          return true, "exit", 0
        end,
      }

      local io_popen_stub = create_stub(io, "popen")
      io_popen_stub.returns(mock_handle)

      -- Mock vim.fn.shellescape
      local vim_shellescape_stub = create_stub(vim.fn, "shellescape")
      vim_shellescape_stub.returns("'dummy.png'")

      -- Test the function
      local result, error_msg = mime.get_mime_type("dummy.png")

      -- Assertions
      assert.is_nil(error_msg)
      assert.equals("image/png", result)

      -- Verify the file command was called correctly
      assert.stub(io_popen_stub).was_called_with("file -b --mime-type 'dummy.png'", "r")
      assert.stub(vim_shellescape_stub).was_called_with("dummy.png")
    end)

    it("returns error when io.popen fails", function()
      -- Mock os.execute to simulate file command being available
      local os_execute_stub = create_stub(os, "execute")
      os_execute_stub.on_call_with("command -v file >/dev/null 2>&1").returns(0)

      -- Mock io.popen to simulate failure
      local io_popen_stub = create_stub(io, "popen")
      io_popen_stub.returns(nil)

      -- Mock vim.fn.shellescape
      local vim_shellescape_stub = create_stub(vim.fn, "shellescape")
      vim_shellescape_stub.returns("'dummy.png'")

      -- Test the function
      local result, error_msg = mime.get_mime_type("dummy.png")

      -- Assertions
      assert.is_nil(result)
      assert.equals("Failed to execute 'file' command", error_msg)
    end)

    it("returns error when file command exits with non-zero status", function()
      -- Mock os.execute to simulate file command being available
      local os_execute_stub = create_stub(os, "execute")
      os_execute_stub.on_call_with("command -v file >/dev/null 2>&1").returns(0)

      -- Mock io.popen to simulate command execution with error
      local mock_handle = {
        read = function(self, mode)
          if mode == "*a" then
            return "cannot open (No such file or directory)\n"
          end
        end,
        close = function(self)
          return false, "exit", 1
        end,
      }

      local io_popen_stub = create_stub(io, "popen")
      io_popen_stub.returns(mock_handle)

      -- Mock vim.fn.shellescape
      local vim_shellescape_stub = create_stub(vim.fn, "shellescape")
      vim_shellescape_stub.returns("'nonexistent.png'")

      -- Test the function
      local result, error_msg = mime.get_mime_type("nonexistent.png")

      -- Assertions
      assert.is_nil(result)
      assert.matches('Failed to get MIME type for "nonexistent.png"', error_msg)
      assert.matches("exit code: 1", error_msg)
    end)

    it("returns error when file command returns empty output", function()
      -- Mock os.execute to simulate file command being available
      local os_execute_stub = create_stub(os, "execute")
      os_execute_stub.on_call_with("command -v file >/dev/null 2>&1").returns(0)

      -- Mock io.popen to simulate command with empty output
      local mock_handle = {
        read = function(self, mode)
          if mode == "*a" then
            return ""
          end
        end,
        close = function(self)
          return true, "exit", 0
        end,
      }

      local io_popen_stub = create_stub(io, "popen")
      io_popen_stub.returns(mock_handle)

      -- Mock vim.fn.shellescape
      local vim_shellescape_stub = create_stub(vim.fn, "shellescape")
      vim_shellescape_stub.returns("'empty.txt'")

      -- Test the function
      local result, error_msg = mime.get_mime_type("empty.txt")

      -- Assertions
      assert.is_nil(result)
      assert.matches('Failed to get MIME type for "empty.txt"', error_msg)
      assert.matches("exit code: 0", error_msg)
    end)

    it("returns error when file command returns whitespace-only output", function()
      -- Mock os.execute to simulate file command being available
      local os_execute_stub = create_stub(os, "execute")
      os_execute_stub.on_call_with("command -v file >/dev/null 2>&1").returns(0)

      -- Mock io.popen to simulate command with whitespace-only output
      local mock_handle = {
        read = function(self, mode)
          if mode == "*a" then
            return "   \n  \t  "
          end
        end,
        close = function(self)
          return true, "exit", 0
        end,
      }

      local io_popen_stub = create_stub(io, "popen")
      io_popen_stub.returns(mock_handle)

      -- Mock vim.fn.shellescape
      local vim_shellescape_stub = create_stub(vim.fn, "shellescape")
      vim_shellescape_stub.returns("'whitespace.txt'")

      -- Test the function
      local result, error_msg = mime.get_mime_type("whitespace.txt")

      -- Assertions
      assert.is_nil(result)
      assert.equals("Failed to determine MIME type (empty output)", error_msg)
    end)

    it("trims whitespace from MIME type output", function()
      -- Mock os.execute to simulate file command being available
      local os_execute_stub = create_stub(os, "execute")
      os_execute_stub.on_call_with("command -v file >/dev/null 2>&1").returns(0)

      -- Mock io.popen to simulate output with extra whitespace
      local mock_handle = {
        read = function(self, mode)
          if mode == "*a" then
            return "   text/plain   \n  "
          end
        end,
        close = function(self)
          return true, "exit", 0
        end,
      }

      local io_popen_stub = create_stub(io, "popen")
      io_popen_stub.returns(mock_handle)

      -- Mock vim.fn.shellescape
      local vim_shellescape_stub = create_stub(vim.fn, "shellescape")
      vim_shellescape_stub.returns("'test.txt'")

      -- Test the function
      local result, error_msg = mime.get_mime_type("test.txt")

      -- Assertions
      assert.is_nil(error_msg)
      assert.equals("text/plain", result)
    end)

    describe("caching mechanism", function()
      it(
        "caches file command availability and errors immediately on subsequent calls when command not found",
        function()
          -- Mock os.execute to simulate file command NOT being available
          local os_execute_stub = create_stub(os, "execute")
          os_execute_stub.on_call_with("command -v file >/dev/null 2>&1").returns(1)

          -- First call should check for command and cache the failure
          local success1, err1 = pcall(mime.get_mime_type, "dummy.png")
          assert.is_false(success1)
          assert.matches("The 'file' command is required", err1)

          -- Second call should immediately error without calling os.execute again
          local success2, err2 = pcall(mime.get_mime_type, "dummy2.png")
          assert.is_false(success2)
          assert.matches("The 'file' command is required", err2)

          -- Verify os.execute was only called once (during first call)
          assert.stub(os_execute_stub).was_called(1)
        end
      )

      it("caches file command availability and skips check on subsequent calls when command found", function()
        -- Mock os.execute to simulate file command being available
        local os_execute_stub = create_stub(os, "execute")
        os_execute_stub.on_call_with("command -v file >/dev/null 2>&1").returns(0)

        -- Mock io.popen for both calls
        local call_count = 0
        local io_popen_stub = create_stub(io, "popen")
        io_popen_stub.invokes(function(cmd, mode)
          call_count = call_count + 1
          return {
            read = function(self, mode)
              if mode == "*a" then
                return "text/plain\n"
              end
            end,
            close = function(self)
              return true, "exit", 0
            end,
          }
        end)

        -- Mock vim.fn.shellescape
        local vim_shellescape_stub = create_stub(vim.fn, "shellescape")
        vim_shellescape_stub.on_call_with("file1.txt").returns("'file1.txt'")
        vim_shellescape_stub.on_call_with("file2.txt").returns("'file2.txt'")

        -- First call should check for command and cache success
        local result1, error1 = mime.get_mime_type("file1.txt")
        assert.is_nil(error1)
        assert.equals("text/plain", result1)

        -- Second call should skip the command check
        local result2, error2 = mime.get_mime_type("file2.txt")
        assert.is_nil(error2)
        assert.equals("text/plain", result2)

        -- Verify os.execute was only called once (during first call)
        assert.stub(os_execute_stub).was_called(1)
        -- But io.popen should be called twice (once for each file)
        assert.equals(2, call_count)
      end)
    end)
  end)
end)
