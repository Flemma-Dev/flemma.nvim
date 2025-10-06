local stub = require("luassert.stub")

describe("File References and Path Parsing", function()
  local content_parser
  local stubs = {}

  local function create_stub(obj, method, replacement)
    local s = stub(obj, method, replacement)
    table.insert(stubs, s)
    return s
  end

  before_each(function()
    -- Clear the module cache to ensure fresh state
    package.loaded["flemma.content_parser"] = nil
    content_parser = require("flemma.content_parser")
    stubs = {}
  end)

  after_each(function()
    -- Restore all stubs
    for _, s in ipairs(stubs) do
      s:revert()
    end
    stubs = {}
  end)

  describe("URL-encoded file path parsing", function()
    it("correctly decodes URL-encoded characters and strips trailing punctuation", function()
      -- Mock vim.fn.filereadable to return success (file exists)
      local filereadable_stub = create_stub(vim.fn, "filereadable")
      filereadable_stub.returns(1)

      -- Mock mime_util.get_mime_type to return a dummy MIME type
      local mime_util = require("flemma.mime")
      local mime_stub = create_stub(mime_util, "get_mime_type")
      mime_stub.returns("text/plain", nil)

      -- Mock io.open to simulate file reading
      local mock_file = {
        read = function(self, mode)
          if mode == "*a" then
            return "test file content"
          end
        end,
        close = function(self) end,
      }
      local io_open_stub = create_stub(io, "open")
      io_open_stub.returns(mock_file)

      -- Test string with URL-encoded filename and trailing punctuation
      local test_content = "Check this file: @./my%20report.txt."
      local parser = content_parser.parse(test_content)

      local chunks = {}
      while true do
        local status, chunk = coroutine.resume(parser)
        if not status or not chunk then
          break
        end
        table.insert(chunks, chunk)
      end

      -- Should have text chunk, file chunk, and possibly text chunk
      local file_chunk = nil
      for _, chunk in ipairs(chunks) do
        if chunk.type == "file" then
          file_chunk = chunk
          break
        end
      end

      -- Assertions
      assert.is_not_nil(file_chunk)
      assert.equals("file", file_chunk.type)
      assert.equals("./my report.txt", file_chunk.filename) -- URL-decoded
      assert.equals("./my%20report.txt", file_chunk.raw_filename) -- Original with encoding, punctuation stripped
      assert.equals("text/plain", file_chunk.mime_type)
      assert.equals("test file content", file_chunk.content)
      assert.is_true(file_chunk.readable)

      -- Verify that vim.fn.filereadable was called with the decoded filename
      assert.stub(filereadable_stub).was_called_with("./my report.txt")
    end)

    it("handles multiple URL-encoded characters in filename", function()
      -- Mock vim.fn.filereadable to return success
      local filereadable_stub = create_stub(vim.fn, "filereadable")
      filereadable_stub.returns(1)

      -- Mock mime_util.get_mime_type
      local mime_util = require("flemma.mime")
      local mime_stub = create_stub(mime_util, "get_mime_type")
      mime_stub.returns("application/json", nil)

      -- Mock io.open
      local mock_file = {
        read = function(self, mode)
          if mode == "*a" then
            return '{"test": "data"}'
          end
        end,
        close = function(self) end,
      }
      local io_open_stub = create_stub(io, "open")
      io_open_stub.returns(mock_file)

      -- Test with multiple encoded characters: space (%20), plus (%2B), ampersand (%26)
      local test_content = "Load @./data%20file%2Bwith%26symbols.json"
      local parser = content_parser.parse(test_content)

      local chunks = {}
      while true do
        local status, chunk = coroutine.resume(parser)
        if not status or not chunk then
          break
        end
        table.insert(chunks, chunk)
      end

      local file_chunk = nil
      for _, chunk in ipairs(chunks) do
        if chunk.type == "file" then
          file_chunk = chunk
          break
        end
      end

      assert.is_not_nil(file_chunk)
      assert.equals("./data file+with&symbols.json", file_chunk.filename) -- All characters decoded
      assert.equals("./data%20file%2Bwith%26symbols.json", file_chunk.raw_filename)
    end)

    it("handles plus signs as spaces in URL decoding", function()
      -- Mock vim.fn.filereadable to return success
      local filereadable_stub = create_stub(vim.fn, "filereadable")
      filereadable_stub.returns(1)

      -- Mock mime_util.get_mime_type
      local mime_util = require("flemma.mime")
      local mime_stub = create_stub(mime_util, "get_mime_type")
      mime_stub.returns("text/plain", nil)

      -- Mock io.open
      local mock_file = {
        read = function(self, mode)
          if mode == "*a" then
            return "content"
          end
        end,
        close = function(self) end,
      }
      local io_open_stub = create_stub(io, "open")
      io_open_stub.returns(mock_file)

      -- Test with plus signs that should be converted to spaces
      local test_content = "Read @./file+with+plus+signs.txt"
      local parser = content_parser.parse(test_content)

      local chunks = {}
      while true do
        local status, chunk = coroutine.resume(parser)
        if not status or not chunk then
          break
        end
        table.insert(chunks, chunk)
      end

      local file_chunk = nil
      for _, chunk in ipairs(chunks) do
        if chunk.type == "file" then
          file_chunk = chunk
          break
        end
      end

      assert.is_not_nil(file_chunk)
      assert.equals("./file with plus signs.txt", file_chunk.filename) -- Plus signs converted to spaces
      assert.equals("./file+with+plus+signs.txt", file_chunk.raw_filename)
    end)
  end)

  describe("buffer-relative path resolution", function()
    it("resolves file paths relative to buffer directory instead of working directory", function()
      -- Create a temporary directory structure
      local temp_dir = vim.fn.tempname() .. "_file_ref_test"
      vim.fn.mkdir(temp_dir, "p")
      vim.fn.mkdir(temp_dir .. "/subdir", "p")

      -- Create a test file in the subdirectory
      local test_file_path = temp_dir .. "/subdir/data.txt"
      local test_file = io.open(test_file_path, "w")
      test_file:write("Test file content from subdir")
      test_file:close()

      -- Mock vim.fn.filereadable to return success
      local filereadable_stub = create_stub(vim.fn, "filereadable")
      filereadable_stub.returns(1)

      -- Mock mime_util.get_mime_type
      local mime_util = require("flemma.mime")
      local mime_stub = create_stub(mime_util, "get_mime_type")
      mime_stub.returns("text/plain", nil)

      -- Mock io.open to return our test file content
      local mock_file = {
        read = function(self, mode)
          if mode == "*a" then
            return "Test file content from subdir"
          end
        end,
        close = function(self) end,
      }
      local io_open_stub = create_stub(io, "open")
      io_open_stub.returns(mock_file)

      -- Test with context containing __filename (unified with eval environment pattern)
      local context = { __filename = temp_dir .. "/subdir/test.chat" }
      local test_content = "Check @./data.txt"
      local parser = content_parser.parse(test_content, context)

      local chunks = {}
      while true do
        local status, chunk = coroutine.resume(parser)
        if not status or not chunk then
          break
        end
        table.insert(chunks, chunk)
      end

      local file_chunk = nil
      for _, chunk in ipairs(chunks) do
        if chunk.type == "file" then
          file_chunk = chunk
          break
        end
      end

      assert.is_not_nil(file_chunk)
      assert.equals("file", file_chunk.type)
      -- The filename should be resolved relative to buffer_dir
      assert.equals(temp_dir .. "/subdir/data.txt", file_chunk.filename)
      assert.equals("./data.txt", file_chunk.raw_filename)

      -- Verify that vim.fn.filereadable was called with the resolved path
      assert.stub(filereadable_stub).was_called_with(temp_dir .. "/subdir/data.txt")

      -- Clean up
      vim.fn.delete(temp_dir, "rf")
    end)

    it("handles parent directory references relative to buffer", function()
      -- Create a temporary directory structure
      local temp_dir = vim.fn.tempname() .. "_file_ref_parent_test"
      vim.fn.mkdir(temp_dir, "p")
      vim.fn.mkdir(temp_dir .. "/subdir", "p")

      -- Create a test file in the parent directory
      local test_file_path = temp_dir .. "/parent.txt"
      local test_file = io.open(test_file_path, "w")
      test_file:write("Parent file content")
      test_file:close()

      -- Mock vim.fn.filereadable to return success
      local filereadable_stub = create_stub(vim.fn, "filereadable")
      filereadable_stub.returns(1)

      -- Mock mime_util.get_mime_type
      local mime_util = require("flemma.mime")
      local mime_stub = create_stub(mime_util, "get_mime_type")
      mime_stub.returns("text/plain", nil)

      -- Mock io.open
      local mock_file = {
        read = function(self, mode)
          if mode == "*a" then
            return "Parent file content"
          end
        end,
        close = function(self) end,
      }
      local io_open_stub = create_stub(io, "open")
      io_open_stub.returns(mock_file)

      -- Test with context containing __filename in subdir, referencing parent
      local context = { __filename = temp_dir .. "/subdir/test.chat" }
      local test_content = "Check @../parent.txt"
      local parser = content_parser.parse(test_content, context)

      local chunks = {}
      while true do
        local status, chunk = coroutine.resume(parser)
        if not status or not chunk then
          break
        end
        table.insert(chunks, chunk)
      end

      local file_chunk = nil
      for _, chunk in ipairs(chunks) do
        if chunk.type == "file" then
          file_chunk = chunk
          break
        end
      end

      assert.is_not_nil(file_chunk)
      -- The filename should be resolved relative to buffer_dir
      assert.equals(temp_dir .. "/parent.txt", file_chunk.filename)
      assert.equals("../parent.txt", file_chunk.raw_filename)

      -- Clean up
      vim.fn.delete(temp_dir, "rf")
    end)

    it("uses working directory when context is nil or has no __filename", function()
      -- Mock vim.fn.filereadable to return success
      local filereadable_stub = create_stub(vim.fn, "filereadable")
      filereadable_stub.returns(1)

      -- Mock mime_util.get_mime_type
      local mime_util = require("flemma.mime")
      local mime_stub = create_stub(mime_util, "get_mime_type")
      mime_stub.returns("text/plain", nil)

      -- Mock io.open
      local mock_file = {
        read = function(self, mode)
          if mode == "*a" then
            return "content"
          end
        end,
        close = function(self) end,
      }
      local io_open_stub = create_stub(io, "open")
      io_open_stub.returns(mock_file)

      -- Test without context (should use working directory)
      local test_content = "Check @./file.txt"
      local parser = content_parser.parse(test_content, nil)

      local chunks = {}
      while true do
        local status, chunk = coroutine.resume(parser)
        if not status or not chunk then
          break
        end
        table.insert(chunks, chunk)
      end

      local file_chunk = nil
      for _, chunk in ipairs(chunks) do
        if chunk.type == "file" then
          file_chunk = chunk
          break
        end
      end

      assert.is_not_nil(file_chunk)
      -- The filename should remain as-is (not resolved)
      assert.equals("./file.txt", file_chunk.filename)

      -- Verify that vim.fn.filereadable was called with the non-resolved path
      assert.stub(filereadable_stub).was_called_with("./file.txt")
    end)
  end)

  describe("trailing punctuation handling", function()
    it("removes various types of trailing punctuation from file paths", function()
      -- Mock vim.fn.filereadable to return success
      local filereadable_stub = create_stub(vim.fn, "filereadable")
      filereadable_stub.returns(1)

      -- Mock mime_util.get_mime_type
      local mime_util = require("flemma.mime")
      local mime_stub = create_stub(mime_util, "get_mime_type")
      mime_stub.returns("text/plain", nil)

      -- Mock io.open
      local mock_file = {
        read = function(self, mode)
          if mode == "*a" then
            return "content"
          end
        end,
        close = function(self) end,
      }
      local io_open_stub = create_stub(io, "open")
      io_open_stub.returns(mock_file)

      local test_cases = {
        { input = "@./file.txt.", expected_filename = "./file.txt", description = "period" },
        { input = "@./file.txt,", expected_filename = "./file.txt", description = "comma" },
        { input = "@./file.txt!", expected_filename = "./file.txt", description = "exclamation" },
        { input = "@./file.txt?", expected_filename = "./file.txt", description = "question mark" },
        { input = "@./file.txt;", expected_filename = "./file.txt", description = "semicolon" },
        { input = "@./file.txt:", expected_filename = "./file.txt", description = "colon" },
        { input = "@./file.txt...", expected_filename = "./file.txt", description = "multiple periods" },
        { input = "@./file.txt.,!", expected_filename = "./file.txt", description = "multiple punctuation marks" },
      }

      for _, test_case in ipairs(test_cases) do
        -- Reset stubs for each test case
        filereadable_stub:clear()
        mime_stub:clear()
        io_open_stub:clear()

        local parser = content_parser.parse("Text before " .. test_case.input .. " text after")

        local chunks = {}
        while true do
          local status, chunk = coroutine.resume(parser)
          if not status or not chunk then
            break
          end
          table.insert(chunks, chunk)
        end

        local file_chunk = nil
        for _, chunk in ipairs(chunks) do
          if chunk.type == "file" then
            file_chunk = chunk
            break
          end
        end

        assert.is_not_nil(file_chunk, "Failed to find file chunk for " .. test_case.description)
        assert.equals(
          test_case.expected_filename,
          file_chunk.filename,
          "Incorrect filename for " .. test_case.description
        )
      end
    end)

    it("preserves periods that are part of the actual filename", function()
      -- Mock vim.fn.filereadable to return success
      local filereadable_stub = create_stub(vim.fn, "filereadable")
      filereadable_stub.returns(1)

      -- Mock mime_util.get_mime_type
      local mime_util = require("flemma.mime")
      local mime_stub = create_stub(mime_util, "get_mime_type")
      mime_stub.returns("text/plain", nil)

      -- Mock io.open
      local mock_file = {
        read = function(self, mode)
          if mode == "*a" then
            return "content"
          end
        end,
        close = function(self) end,
      }
      local io_open_stub = create_stub(io, "open")
      io_open_stub.returns(mock_file)

      -- Test case where periods are part of the filename
      local test_content = "Check @../config/.env.local file"
      local parser = content_parser.parse(test_content)

      local chunks = {}
      while true do
        local status, chunk = coroutine.resume(parser)
        if not status or not chunk then
          break
        end
        table.insert(chunks, chunk)
      end

      local file_chunk = nil
      for _, chunk in ipairs(chunks) do
        if chunk.type == "file" then
          file_chunk = chunk
          break
        end
      end

      assert.is_not_nil(file_chunk)
      assert.equals("../config/.env.local", file_chunk.filename) -- Periods preserved in path/filename
      assert.equals("../config/.env.local", file_chunk.raw_filename)
    end)
  end)

  describe("combined URL decoding and punctuation handling", function()
    it("correctly handles URL-encoded filename with trailing punctuation", function()
      -- Mock vim.fn.filereadable to return success
      local filereadable_stub = create_stub(vim.fn, "filereadable")
      filereadable_stub.returns(1)

      -- Mock mime_util.get_mime_type
      local mime_util = require("flemma.mime")
      local mime_stub = create_stub(mime_util, "get_mime_type")
      mime_stub.returns("application/pdf", nil)

      -- Mock io.open
      local mock_file = {
        read = function(self, mode)
          if mode == "*a" then
            return "PDF content"
          end
        end,
        close = function(self) end,
      }
      local io_open_stub = create_stub(io, "open")
      io_open_stub.returns(mock_file)

      -- Test URL-encoded filename with trailing punctuation in a sentence
      local test_content = "Please review the document @./quarterly%20report%202023.pdf, and let me know your thoughts."
      local parser = content_parser.parse(test_content)

      local chunks = {}
      while true do
        local status, chunk = coroutine.resume(parser)
        if not status or not chunk then
          break
        end
        table.insert(chunks, chunk)
      end

      local file_chunk = nil
      for _, chunk in ipairs(chunks) do
        if chunk.type == "file" then
          file_chunk = chunk
          break
        end
      end

      assert.is_not_nil(file_chunk)
      assert.equals("./quarterly report 2023.pdf", file_chunk.filename) -- URL-decoded
      assert.equals("./quarterly%20report%202023.pdf", file_chunk.raw_filename) -- Original encoding, punctuation stripped
      assert.equals("application/pdf", file_chunk.mime_type)
      assert.equals("PDF content", file_chunk.content)

      -- Verify the text chunks were properly separated
      local text_chunks = {}
      for _, chunk in ipairs(chunks) do
        if chunk.type == "text" then
          table.insert(text_chunks, chunk.value)
        end
      end

      assert.is_true(#text_chunks >= 2)
      assert.equals("Please review the document ", text_chunks[1])
      assert.equals(", and let me know your thoughts.", text_chunks[2])
    end)

    it("handles complex filename with MIME type override, URL encoding, and punctuation", function()
      -- Mock vim.fn.filereadable to return success
      local filereadable_stub = create_stub(vim.fn, "filereadable")
      filereadable_stub.returns(1)

      -- Mock io.open
      local mock_file = {
        read = function(self, mode)
          if mode == "*a" then
            return "binary data"
          end
        end,
        close = function(self) end,
      }
      local io_open_stub = create_stub(io, "open")
      io_open_stub.returns(mock_file)

      -- Complex case: URL-encoded filename with MIME type override and trailing punctuation
      local test_content = "The data is in @./data%20files/results%2Bfinal.dat;type=application/octet-stream."
      local parser = content_parser.parse(test_content)

      local chunks = {}
      while true do
        local status, chunk = coroutine.resume(parser)
        if not status or not chunk then
          break
        end
        table.insert(chunks, chunk)
      end

      local file_chunk = nil
      for _, chunk in ipairs(chunks) do
        if chunk.type == "file" then
          file_chunk = chunk
          break
        end
      end

      assert.is_not_nil(file_chunk)
      assert.equals("./data files/results+final.dat", file_chunk.filename) -- URL-decoded
      assert.equals("./data%20files/results%2Bfinal.dat;type=application/octet-stream", file_chunk.raw_filename) -- Original encoding with cleaned type override
      assert.equals("application/octet-stream", file_chunk.mime_type) -- MIME type override applied
      assert.equals("binary data", file_chunk.content)

      -- Verify that filereadable was called with the decoded path
      assert.stub(filereadable_stub).was_called_with("./data files/results+final.dat")
    end)
  end)

  describe("Provider-Specific File Formatting", function()
    describe("Claude Provider", function()
      it("formats PNG images correctly", function()
        -- Setup Claude provider
        local claude = require("flemma.provider.claude")
        local provider = claude.new({ model = "claude-sonnet-4-0", max_tokens = 1000 })

        -- Mock file operations
        local filereadable_stub = create_stub(vim.fn, "filereadable")
        filereadable_stub.returns(1)

        local mime_util = require("flemma.mime")
        local mime_stub = create_stub(mime_util, "get_mime_type")
        mime_stub.returns("image/png", nil)

        local mock_file = {
          read = function(self, mode)
            if mode == "*a" then
              return "fake_png_data"
            end
          end,
          close = function(self) end,
        }
        local io_open_stub = create_stub(io, "open")
        io_open_stub.returns(mock_file)

        -- Create messages with file reference
        local messages = {
          { type = "You", content = "Look at @./image.png" },
        }

        -- Format messages and create request body
        local formatted_messages, system_message = provider:format_messages(messages)
        local request_body = provider:create_request_body(formatted_messages, system_message)

        -- Verify request body format
        assert.is_not_nil(request_body)
        assert.is_not_nil(request_body.messages)
        assert.equals(1, #request_body.messages)

        local user_message = request_body.messages[1]
        assert.equals("user", user_message.role)
        assert.is_table(user_message.content)

        -- Should have text part and image part
        local text_part = nil
        local image_part = nil
        for _, part in ipairs(user_message.content) do
          if part.type == "text" then
            text_part = part
          elseif part.type == "image" then
            image_part = part
          end
        end

        assert.is_not_nil(text_part)
        assert.equals("Look at ", text_part.text)

        assert.is_not_nil(image_part)
        assert.equals("image", image_part.type)
        assert.is_not_nil(image_part.source)
        assert.equals("base64", image_part.source.type)
        assert.equals("image/png", image_part.source.media_type)
        assert.is_string(image_part.source.data)
      end)

      it("formats PDF documents correctly", function()
        -- Setup Claude provider
        local claude = require("flemma.provider.claude")
        local provider = claude.new({ model = "claude-sonnet-4-0", max_tokens = 1000 })

        -- Mock file operations
        local filereadable_stub = create_stub(vim.fn, "filereadable")
        filereadable_stub.returns(1)

        local mime_util = require("flemma.mime")
        local mime_stub = create_stub(mime_util, "get_mime_type")
        mime_stub.returns("application/pdf", nil)

        local mock_file = {
          read = function(self, mode)
            if mode == "*a" then
              return "fake_pdf_data"
            end
          end,
          close = function(self) end,
        }
        local io_open_stub = create_stub(io, "open")
        io_open_stub.returns(mock_file)

        -- Create messages with file reference
        local messages = {
          { type = "You", content = "Review @./document.pdf" },
        }

        -- Format messages and create request body
        local formatted_messages, system_message = provider:format_messages(messages)
        local request_body = provider:create_request_body(formatted_messages, system_message)

        -- Verify request body format
        assert.is_not_nil(request_body)

        local user_message = request_body.messages[1]
        local document_part = nil
        for _, part in ipairs(user_message.content) do
          if part.type == "document" then
            document_part = part
            break
          end
        end

        assert.is_not_nil(document_part)
        assert.equals("document", document_part.type)
        assert.is_not_nil(document_part.source)
        assert.equals("base64", document_part.source.type)
        assert.equals("application/pdf", document_part.source.media_type)
        assert.is_string(document_part.source.data)
      end)

      it("formats text files correctly", function()
        -- Setup Claude provider
        local claude = require("flemma.provider.claude")
        local provider = claude.new({ model = "claude-sonnet-4-0", max_tokens = 1000 })

        -- Mock file operations
        local filereadable_stub = create_stub(vim.fn, "filereadable")
        filereadable_stub.returns(1)

        local mime_util = require("flemma.mime")
        local mime_stub = create_stub(mime_util, "get_mime_type")
        mime_stub.returns("text/plain", nil)

        local mock_file = {
          read = function(self, mode)
            if mode == "*a" then
              return "This is the content of the text file."
            end
          end,
          close = function(self) end,
        }
        local io_open_stub = create_stub(io, "open")
        io_open_stub.returns(mock_file)

        -- Create messages with file reference
        local messages = {
          { type = "You", content = "Read @./notes.txt" },
        }

        -- Format messages and create request body
        local formatted_messages, system_message = provider:format_messages(messages)
        local request_body = provider:create_request_body(formatted_messages, system_message)

        -- Verify request body format
        assert.is_not_nil(request_body)

        local user_message = request_body.messages[1]
        local text_parts = {}
        for _, part in ipairs(user_message.content) do
          if part.type == "text" then
            table.insert(text_parts, part.text)
          end
        end

        -- Should have "Read " and the file content as separate text parts
        assert.equals(2, #text_parts)
        assert.equals("Read ", text_parts[1])
        assert.equals("This is the content of the text file.", text_parts[2])
      end)
    end)

    describe("OpenAI Provider", function()
      it("formats PNG images correctly", function()
        -- Setup OpenAI provider
        local openai = require("flemma.provider.openai")
        local provider = openai.new({ model = "gpt-4o", max_tokens = 1000 })

        -- Mock file operations
        local filereadable_stub = create_stub(vim.fn, "filereadable")
        filereadable_stub.returns(1)

        local mime_util = require("flemma.mime")
        local mime_stub = create_stub(mime_util, "get_mime_type")
        mime_stub.returns("image/png", nil)

        local mock_file = {
          read = function(self, mode)
            if mode == "*a" then
              return "fake_png_data"
            end
          end,
          close = function(self) end,
        }
        local io_open_stub = create_stub(io, "open")
        io_open_stub.returns(mock_file)

        -- Create messages with file reference
        local messages = {
          { type = "You", content = "Analyze @./chart.png" },
        }

        -- Format messages and create request body
        local formatted_messages, system_message = provider:format_messages(messages)
        local request_body = provider:create_request_body(formatted_messages, system_message)

        -- Verify request body format
        assert.is_not_nil(request_body)
        assert.is_not_nil(request_body.messages)
        assert.equals(1, #request_body.messages)

        local user_message = request_body.messages[1]
        assert.equals("user", user_message.role)
        assert.is_table(user_message.content)

        -- Should have text part and image_url part
        local text_part = nil
        local image_part = nil
        for _, part in ipairs(user_message.content) do
          if part.type == "text" then
            text_part = part
          elseif part.type == "image_url" then
            image_part = part
          end
        end

        assert.is_not_nil(text_part)
        assert.equals("Analyze ", text_part.text)

        assert.is_not_nil(image_part)
        assert.equals("image_url", image_part.type)
        assert.is_not_nil(image_part.image_url)
        assert.is_string(image_part.image_url.url)
        assert.is_true(string.match(image_part.image_url.url, "^data:image/png;base64,") ~= nil)
        assert.equals("auto", image_part.image_url.detail)
      end)

      it("formats PDF documents correctly", function()
        -- Setup OpenAI provider
        local openai = require("flemma.provider.openai")
        local provider = openai.new({ model = "gpt-4o", max_tokens = 1000 })

        -- Mock file operations
        local filereadable_stub = create_stub(vim.fn, "filereadable")
        filereadable_stub.returns(1)

        local mime_util = require("flemma.mime")
        local mime_stub = create_stub(mime_util, "get_mime_type")
        mime_stub.returns("application/pdf", nil)

        local mock_file = {
          read = function(self, mode)
            if mode == "*a" then
              return "fake_pdf_data"
            end
          end,
          close = function(self) end,
        }
        local io_open_stub = create_stub(io, "open")
        io_open_stub.returns(mock_file)

        -- Create messages with file reference
        local messages = {
          { type = "You", content = "Summarize @./report.pdf" },
        }

        -- Format messages and create request body
        local formatted_messages, system_message = provider:format_messages(messages)
        local request_body = provider:create_request_body(formatted_messages, system_message)

        -- Verify request body format
        assert.is_not_nil(request_body)

        local user_message = request_body.messages[1]
        local file_part = nil
        for _, part in ipairs(user_message.content) do
          if part.type == "file" then
            file_part = part
            break
          end
        end

        assert.is_not_nil(file_part)
        assert.equals("file", file_part.type)
        assert.is_not_nil(file_part.file)
        assert.is_string(file_part.file.filename)
        assert.is_string(file_part.file.file_data)
        assert.is_true(string.match(file_part.file.file_data, "^data:application/pdf;base64,") ~= nil)
      end)

      it("formats text files correctly", function()
        -- Setup OpenAI provider
        local openai = require("flemma.provider.openai")
        local provider = openai.new({ model = "gpt-4o", max_tokens = 1000 })

        -- Mock file operations
        local filereadable_stub = create_stub(vim.fn, "filereadable")
        filereadable_stub.returns(1)

        local mime_util = require("flemma.mime")
        local mime_stub = create_stub(mime_util, "get_mime_type")
        mime_stub.returns("text/plain", nil)

        local mock_file = {
          read = function(self, mode)
            if mode == "*a" then
              return "Sample text file content."
            end
          end,
          close = function(self) end,
        }
        local io_open_stub = create_stub(io, "open")
        io_open_stub.returns(mock_file)

        -- Create messages with file reference
        local messages = {
          { type = "You", content = "Process @./data.txt" },
        }

        -- Format messages and create request body
        local formatted_messages, system_message = provider:format_messages(messages)
        local request_body = provider:create_request_body(formatted_messages, system_message)

        -- Verify request body format
        assert.is_not_nil(request_body)

        local user_message = request_body.messages[1]

        -- For OpenAI, when there are only text parts, they get concatenated into a single string
        if type(user_message.content) == "string" then
          assert.equals("Process Sample text file content.", user_message.content)
        else
          -- If it's a table, extract text parts
          local text_parts = {}
          for _, part in ipairs(user_message.content) do
            if part.type == "text" then
              table.insert(text_parts, part.text)
            end
          end

          -- Should have "Process " and the file content as separate text parts
          assert.equals(2, #text_parts)
          assert.equals("Process ", text_parts[1])
          assert.equals("Sample text file content.", text_parts[2])
        end
      end)
    end)

    describe("Vertex AI Provider", function()
      it("formats PNG images correctly", function()
        -- Setup Vertex AI provider
        local vertex = require("flemma.provider.vertex")
        local provider = vertex.new({ model = "gemini-2.5-pro", max_tokens = 1000, project_id = "test-project" })

        -- Mock file operations
        local filereadable_stub = create_stub(vim.fn, "filereadable")
        filereadable_stub.returns(1)

        local mime_util = require("flemma.mime")
        local mime_stub = create_stub(mime_util, "get_mime_type")
        mime_stub.returns("image/png", nil)

        local mock_file = {
          read = function(self, mode)
            if mode == "*a" then
              return "fake_png_data"
            end
          end,
          close = function(self) end,
        }
        local io_open_stub = create_stub(io, "open")
        io_open_stub.returns(mock_file)

        -- Create messages with file reference
        local messages = {
          { type = "You", content = "Describe @./photo.png" },
        }

        -- Format messages and create request body
        local formatted_messages, system_message = provider:format_messages(messages)
        local request_body = provider:create_request_body(formatted_messages, system_message)

        -- Verify request body format
        assert.is_not_nil(request_body)
        assert.is_not_nil(request_body.contents)
        assert.equals(1, #request_body.contents)

        local user_content = request_body.contents[1]
        assert.equals("user", user_content.role)
        assert.is_table(user_content.parts)

        -- Should have text part and inlineData part
        local text_part = nil
        local image_part = nil
        for _, part in ipairs(user_content.parts) do
          if part.text then
            text_part = part
          elseif part.inlineData then
            image_part = part
          end
        end

        assert.is_not_nil(text_part)
        assert.equals("Describe ", text_part.text)

        assert.is_not_nil(image_part)
        assert.is_not_nil(image_part.inlineData)
        assert.equals("image/png", image_part.inlineData.mimeType)
        assert.is_string(image_part.inlineData.data)
        assert.is_string(image_part.inlineData.displayName)
      end)

      it("formats PDF documents correctly", function()
        -- Setup Vertex AI provider
        local vertex = require("flemma.provider.vertex")
        local provider = vertex.new({ model = "gemini-2.5-pro", max_tokens = 1000, project_id = "test-project" })

        -- Mock file operations
        local filereadable_stub = create_stub(vim.fn, "filereadable")
        filereadable_stub.returns(1)

        local mime_util = require("flemma.mime")
        local mime_stub = create_stub(mime_util, "get_mime_type")
        mime_stub.returns("application/pdf", nil)

        local mock_file = {
          read = function(self, mode)
            if mode == "*a" then
              return "fake_pdf_data"
            end
          end,
          close = function(self) end,
        }
        local io_open_stub = create_stub(io, "open")
        io_open_stub.returns(mock_file)

        -- Create messages with file reference
        local messages = {
          { type = "You", content = "Analyze @./study.pdf" },
        }

        -- Format messages and create request body
        local formatted_messages, system_message = provider:format_messages(messages)
        local request_body = provider:create_request_body(formatted_messages, system_message)

        -- Verify request body format
        assert.is_not_nil(request_body)

        local user_content = request_body.contents[1]
        local document_part = nil
        for _, part in ipairs(user_content.parts) do
          if part.inlineData then
            document_part = part
            break
          end
        end

        assert.is_not_nil(document_part)
        assert.is_not_nil(document_part.inlineData)
        assert.equals("application/pdf", document_part.inlineData.mimeType)
        assert.is_string(document_part.inlineData.data)
        assert.is_string(document_part.inlineData.displayName)
      end)

      it("formats text files correctly", function()
        -- Setup Vertex AI provider
        local vertex = require("flemma.provider.vertex")
        local provider = vertex.new({ model = "gemini-2.5-pro", max_tokens = 1000, project_id = "test-project" })

        -- Mock file operations
        local filereadable_stub = create_stub(vim.fn, "filereadable")
        filereadable_stub.returns(1)

        local mime_util = require("flemma.mime")
        local mime_stub = create_stub(mime_util, "get_mime_type")
        mime_stub.returns("text/plain", nil)

        local mock_file = {
          read = function(self, mode)
            if mode == "*a" then
              return "Configuration file content."
            end
          end,
          close = function(self) end,
        }
        local io_open_stub = create_stub(io, "open")
        io_open_stub.returns(mock_file)

        -- Create messages with file reference
        local messages = {
          { type = "You", content = "Check @./config.txt" },
        }

        -- Format messages and create request body
        local formatted_messages, system_message = provider:format_messages(messages)
        local request_body = provider:create_request_body(formatted_messages, system_message)

        -- Verify request body format
        assert.is_not_nil(request_body)

        local user_content = request_body.contents[1]
        local text_parts = {}
        for _, part in ipairs(user_content.parts) do
          if part.text then
            table.insert(text_parts, part.text)
          end
        end

        -- Should have "Check " and the file content as separate text parts
        assert.equals(2, #text_parts)
        assert.equals("Check ", text_parts[1])
        assert.equals("Configuration file content.", text_parts[2])
      end)
    end)
  end)
end)
