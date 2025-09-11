--- Test file for the base provider functionality
describe("Base Provider", function()
  local base = require("flemma.provider.base")
  local content_parser = require("flemma.content_parser")
  local client = require("flemma.client")

  before_each(function()
    -- Clear any registered fixtures (now handled by client)
    client.clear_fixtures()
  end)

  after_each(function()
    -- Clean up any buffers created during the test
    vim.cmd("silent! %bdelete!")
  end)

  describe("parse_message_content_chunks", function()
    it("should handle text-only content", function()
      local provider = base.new({})
      local content = "Hello, this is just text content."
      local parser = content_parser.parse(content)

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

      local parser = content_parser.parse(content)

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
      local parser = content_parser.parse(content)

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
      local parser = content_parser.parse(content)

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
      local parser = content_parser.parse(content)

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

    it("should integrate with provider to show user notifications for warnings", function()
      local claude = require("flemma.provider.claude")

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
      assert.are.equal("Flemma File Warnings", notification.opts.title)
    end)

    it("should handle MIME type overrides in file references", function()
      -- Create a temporary JSON file
      local tmp_file = os.tmpname()
      local f = io.open(tmp_file, "w")
      f:write('{"test": "content"}')
      f:close()

      -- Copy the temp file to a relative path in current directory for the test
      local rel_file = "./" .. vim.fn.fnamemodify(tmp_file, ":t")
      vim.fn.system("cp " .. tmp_file .. " " .. rel_file)

      local provider = base.new({})
      -- Reference the file with a MIME type override
      local content = "Process @" .. rel_file .. ";type=text/plain as plain text."
      local parser = content_parser.parse(content)

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
      assert.are.equal('{"test": "content"}', file_chunk.content)
      -- Verify that the overridden MIME type is used instead of auto-detected
      assert.are.equal("text/plain", file_chunk.mime_type)
      -- Verify that the raw_filename includes the type override
      assert.is_true(string.find(file_chunk.raw_filename, ";type=text/plain") ~= nil)
    end)

    it("should handle multiple files with different MIME type overrides", function()
      -- Create two temporary files
      local tmp_file1 = os.tmpname()
      local f1 = io.open(tmp_file1, "w")
      f1:write('{"key": "value"}')
      f1:close()

      local tmp_file2 = os.tmpname()
      local f2 = io.open(tmp_file2, "w")
      f2:write("<xml>content</xml>")
      f2:close()

      -- Copy the temp files to relative paths in current directory for the test
      local rel_file1 = "./" .. vim.fn.fnamemodify(tmp_file1, ":t")
      local rel_file2 = "./" .. vim.fn.fnamemodify(tmp_file2, ":t")
      vim.fn.system("cp " .. tmp_file1 .. " " .. rel_file1)
      vim.fn.system("cp " .. tmp_file2 .. " " .. rel_file2)

      local provider = base.new({})
      local content = "Read @" .. rel_file1 .. ";type=text/plain and @" .. rel_file2 .. ";type=image/png files."
      local parser = content_parser.parse(content)

      local chunks = {}
      while true do
        local status, chunk = coroutine.resume(parser)
        if not status or not chunk then
          break
        end
        table.insert(chunks, chunk)
      end

      -- Clean up
      os.remove(tmp_file1)
      os.remove(tmp_file2)
      os.remove(rel_file1)
      os.remove(rel_file2)

      -- Find file chunks
      local file_chunks = {}
      for _, chunk in ipairs(chunks) do
        if chunk.type == "file" then
          table.insert(file_chunks, chunk)
        end
      end

      assert.are.equal(2, #file_chunks)

      -- Verify first file
      local file1_chunk = file_chunks[1]
      assert.are.equal("text/plain", file1_chunk.mime_type)
      assert.are.equal('{"key": "value"}', file1_chunk.content)

      -- Verify second file
      local file2_chunk = file_chunks[2]
      assert.are.equal("image/png", file2_chunk.mime_type)
      assert.are.equal("<xml>content</xml>", file2_chunk.content)
    end)

    it("should handle MIME type overrides with trailing punctuation", function()
      -- Create a temporary file
      local tmp_file = os.tmpname()
      local f = io.open(tmp_file, "w")
      f:write("test content")
      f:close()

      -- Copy the temp file to a relative path in current directory for the test
      local rel_file = "./" .. vim.fn.fnamemodify(tmp_file, ":t")
      vim.fn.system("cp " .. tmp_file .. " " .. rel_file)

      local provider = base.new({})
      -- Reference with MIME type override and trailing punctuation (common in sentences)
      local content = "Process @" .. rel_file .. ";type=text/plain."
      local parser = content_parser.parse(content)

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
      -- Verify that trailing punctuation is removed from MIME type
      assert.are.equal("text/plain", file_chunk.mime_type)
      -- Verify that the raw_filename includes the clean type override
      assert.is_true(string.find(file_chunk.raw_filename, ";type=text/plain") ~= nil)
      assert.is_false(string.find(file_chunk.raw_filename, "text/plain%.") ~= nil)
    end)
  end)
end)
