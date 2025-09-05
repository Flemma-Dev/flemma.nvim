--- Test file for the base provider functionality
describe("Base Provider", function()
  local base = require("claudius.provider.base")

  before_each(function()
    -- Clear any registered fixtures
    base.clear_fixtures()
  end)

  after_each(function()
    -- Clean up any buffers created during the test
    vim.cmd("silent! %bdelete!")
  end)

  describe("parse_message_content_chunks", function()
    it("should handle text-only content", function()
      local provider = base.new({})
      local content = "Hello, this is just text content."
      local parser = provider:parse_message_content_chunks(content)

      local chunks = {}
      while true do
        local status, chunk = coroutine.resume(parser)
        if not status or not chunk then
          break
        end
        table.insert(chunks, chunk)
      end

      assert.are.equal(1, #chunks)
      assert.are.equal("text", chunks[1].type)
      assert.are.equal("Hello, this is just text content.", chunks[1].value)
    end)

    it("should handle mixed text and file references", function()
      -- Create a temporary readable file for testing
      local tmp_file = os.tmpname()
      local f = io.open(tmp_file, "w")
      f:write("test content")
      f:close()

      local provider = base.new({})
      local content = "Hello @./" .. vim.fn.fnamemodify(tmp_file, ":t") .. " and more text."

      -- Copy the temp file to a relative path in current directory for the test
      local rel_file = "./" .. vim.fn.fnamemodify(tmp_file, ":t")
      vim.fn.system("cp " .. tmp_file .. " " .. rel_file)

      local parser = provider:parse_message_content_chunks(content)

      local chunks = {}
      while true do
        local status, chunk = coroutine.resume(parser)
        if not status or not chunk then
          break
        end
        table.insert(chunks, chunk)
      end

      -- Clean up
      os.remove(tmp_file)
      os.remove(rel_file)

      -- Should have text, file, text chunks
      assert.is_true(#chunks >= 2)
      assert.are.equal("text", chunks[1].type)
      assert.are.equal("Hello ", chunks[1].value)

      -- Find the file chunk
      local file_chunk = nil
      for _, chunk in ipairs(chunks) do
        if chunk.type == "file" then
          file_chunk = chunk
          break
        end
      end

      assert.is_not_nil(file_chunk)
      assert.are.equal("file", file_chunk.type)
      assert.is_true(file_chunk.readable)
      assert.are.equal("test content", file_chunk.content)
    end)

    it("should handle non-existent file references and emit warnings", function()
      local provider = base.new({})
      local non_existent_file = "./this_file_does_not_exist.txt"
      local content = "Please read @" .. non_existent_file .. " and process it."
      local parser = provider:parse_message_content_chunks(content)

      local chunks = {}
      while true do
        local status, chunk = coroutine.resume(parser)
        if not status or not chunk then
          break
        end
        table.insert(chunks, chunk)
      end

      -- Should have text, file, text chunks
      assert.is_true(#chunks >= 2)

      -- Find the file chunk
      local file_chunk = nil
      for _, chunk in ipairs(chunks) do
        if chunk.type == "file" then
          file_chunk = chunk
          break
        end
      end

      assert.is_not_nil(file_chunk, "Expected a file chunk to be generated")
      assert.are.equal("file", file_chunk.type)
      assert.is_false(file_chunk.readable)
      assert.are.equal(non_existent_file, file_chunk.filename)
      assert.are.equal(non_existent_file, file_chunk.raw_filename)
      assert.is_not_nil(file_chunk.error)
      assert.is_true(
        string.find(file_chunk.error, "not found") ~= nil or string.find(file_chunk.error, "not readable") ~= nil
      )
    end)

    it("should handle multiple non-existent files", function()
      local provider = base.new({})
      local content = "Read @./missing1.txt and @./missing2.txt files."
      local parser = provider:parse_message_content_chunks(content)

      local chunks = {}
      while true do
        local status, chunk = coroutine.resume(parser)
        if not status or not chunk then
          break
        end
        table.insert(chunks, chunk)
      end

      local file_chunks = {}
      for _, chunk in ipairs(chunks) do
        if chunk.type == "file" then
          table.insert(file_chunks, chunk)
        end
      end

      assert.are.equal(2, #file_chunks)
      for _, file_chunk in ipairs(file_chunks) do
        assert.is_false(file_chunk.readable)
        assert.is_not_nil(file_chunk.error)
      end
    end)

    it("should emit warnings chunk for unreadable files", function()
      local provider = base.new({})
      local content = "Read @./missing1.txt and @./missing2.txt files."
      local parser = provider:parse_message_content_chunks(content)

      local chunks = {}
      while true do
        local status, chunk = coroutine.resume(parser)
        if not status or not chunk then
          break
        end
        table.insert(chunks, chunk)
      end

      local warning_chunks = {}
      for _, chunk in ipairs(chunks) do
        if chunk.type == "warnings" then
          table.insert(warning_chunks, chunk)
        end
      end

      assert.are.equal(1, #warning_chunks)
      local warnings_chunk = warning_chunks[1]
      assert.is_not_nil(warnings_chunk.warnings)
      assert.are.equal(2, #warnings_chunk.warnings)
      for _, warning in ipairs(warnings_chunk.warnings) do
        assert.is_not_nil(warning.filename)
        assert.is_not_nil(warning.error)
        assert.is_true(
          string.find(warning.error, "not found") ~= nil or string.find(warning.error, "not readable") ~= nil
        )
      end
    end)

    it("should handle URL-encoded filenames", function()
      -- Create a file with a space in the name in current directory
      local spaced_file = "./file with spaces.txt"
      local f = io.open(spaced_file, "w")
      f:write("content with spaces")
      f:close()

      local provider = base.new({})
      -- URL encode the space as %20
      local encoded_path = "./file%20with%20spaces.txt"
      local content = "Read @" .. encoded_path .. " please."
      local parser = provider:parse_message_content_chunks(content)

      local chunks = {}
      while true do
        local status, chunk = coroutine.resume(parser)
        if not status or not chunk then
          break
        end
        table.insert(chunks, chunk)
      end

      -- Clean up
      os.remove(spaced_file)

      local file_chunk = nil
      for _, chunk in ipairs(chunks) do
        if chunk.type == "file" then
          file_chunk = chunk
          break
        end
      end

      assert.is_not_nil(file_chunk)
      assert.are.equal("file", file_chunk.type)
      assert.is_true(file_chunk.readable)
      assert.are.equal(spaced_file, file_chunk.filename) -- Should be decoded
      assert.are.equal("content with spaces", file_chunk.content)
    end)

    it("should integrate with provider to show user notifications for warnings", function()
      local claude = require("claudius.provider.claude")

      -- Create a Claude provider instance
      local provider = claude.new({ model = "claude-3-5-sonnet", max_tokens = 1000, temperature = 0.7 })

      -- Mock vim.notify to capture calls
      local notify_calls = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level, opts)
        table.insert(notify_calls, { message = msg, level = level, opts = opts })
      end

      local messages = {
        { type = "System", content = "Be helpful" },
        { type = "You", content = "Please read @./missing_file.txt and @./another_missing.txt" },
      }

      local formatted_messages, system_message = provider:format_messages(messages)
      local request_body = provider:create_request_body(formatted_messages, system_message)

      -- Restore original vim.notify
      vim.notify = original_notify

      -- Verify request body was created successfully
      assert.is_not_nil(request_body)
      assert.are.equal("claude-3-5-sonnet", request_body.model)

      -- Verify that vim.notify was called with warning about missing files
      assert.are.equal(1, #notify_calls)
      local notification = notify_calls[1]
      assert.are.equal(vim.log.levels.WARN, notification.level)
      assert.is_true(string.find(notification.message, "missing_file.txt") ~= nil)
      assert.is_true(string.find(notification.message, "another_missing.txt") ~= nil)
      assert.is_true(string.find(notification.message, "could not be processed") ~= nil)
      assert.are.equal("Claudius File Warnings", notification.opts.title)
    end)
  end)
end)
