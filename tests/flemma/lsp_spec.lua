describe("Flemma LSP", function()
  local flemma

  before_each(function()
    -- Clear the FlemmaLsp augroup to prevent stale autocmds from previous tests
    vim.api.nvim_create_augroup("FlemmaLsp", { clear = true })
    -- Stop any lingering LSP clients
    for _, client in pairs(vim.lsp.get_clients({ name = "flemma" })) do
      client:stop(true)
    end
    vim.cmd("silent! %bdelete!")
    package.loaded["flemma"] = nil
    package.loaded["flemma.lsp"] = nil
    package.loaded["flemma.parser"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.ast"] = nil
    package.loaded["flemma.ast.query"] = nil
    package.loaded["flemma.ast.nodes"] = nil
    flemma = require("flemma")
  end)

  after_each(function()
    for _, client in pairs(vim.lsp.get_clients({ name = "flemma" })) do
      client:stop(true)
    end
    vim.cmd("silent! %bdelete!")
  end)

  local test_counter = 0

  --- Helper: create a named chat buffer with given lines, attach LSP, return bufnr and client
  ---@param lines string[]
  ---@return integer bufnr
  ---@return vim.lsp.Client client
  local function setup_chat_buffer(lines)
    flemma.setup({ experimental = { lsp = true } })

    test_counter = test_counter + 1
    local bufnr = vim.api.nvim_create_buf(true, false)
    -- Named buffers are required for URI resolution in the LSP hover handler
    vim.api.nvim_buf_set_name(bufnr, "/tmp/flemma_lsp_test_" .. test_counter .. ".chat")
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].filetype = "chat"
    vim.cmd("doautocmd FileType")

    vim.wait(1000, function()
      return #vim.lsp.get_clients({ name = "flemma", bufnr = bufnr }) > 0
    end)

    local clients = vim.lsp.get_clients({ name = "flemma", bufnr = bufnr })
    assert.is_true(#clients > 0, "Client should be attached")
    return bufnr, clients[1]
  end

  --- Helper: make a synchronous hover request
  ---@param client vim.lsp.Client
  ---@param bufnr integer
  ---@param line integer 0-indexed line
  ---@param character integer 0-indexed column
  ---@return table|nil result
  local function hover_sync(client, bufnr, line, character)
    local response = client:request_sync("textDocument/hover", {
      textDocument = { uri = vim.uri_from_bufnr(bufnr) },
      position = { line = line, character = character },
    }, 2000, bufnr)
    if response and response.result then
      return response.result
    end
    return nil
  end

  it("attaches to chat buffers when experimental.lsp is enabled", function()
    flemma.setup({ experimental = { lsp = true } })

    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = "chat"
    vim.cmd("doautocmd FileType")

    local clients = vim.lsp.get_clients({ name = "flemma", bufnr = bufnr })
    assert.is_true(#clients > 0, "Expected flemma LSP client to be attached")
  end)

  it("does not attach when experimental.lsp is disabled", function()
    flemma.setup({ experimental = { lsp = false } })

    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = "chat"
    vim.cmd("doautocmd FileType")

    local clients = vim.lsp.get_clients({ name = "flemma", bufnr = bufnr })
    assert.equals(0, #clients, "Expected no flemma LSP client when disabled")
  end)

  it("returns hover for expression segment", function()
    local bufnr, client = setup_chat_buffer({
      "@You:",
      "Hello {{ name }}",
    })

    local result = hover_sync(client, bufnr, 1, 8) -- 0-indexed, on "{{ name }}"
    assert.is_not_nil(result, "Expected hover result")
    assert.is_not_nil(result.contents)
    assert.equals("markdown", result.contents.kind)
    assert.is_truthy(result.contents.value:find("ExpressionSegment"))
    assert.is_truthy(result.contents.value:find("name"))
  end)

  it("returns hover for plain text", function()
    local bufnr, client = setup_chat_buffer({
      "@You:",
      "Hello world",
    })

    local result = hover_sync(client, bufnr, 1, 2) -- on "Hello"
    assert.is_not_nil(result)
    assert.is_truthy(result.contents.value:find("TextSegment"))
  end)

  it("returns hover with full thinking content (no truncation)", function()
    local long_thought = string.rep("This is a long thought. ", 100)
    local bufnr, client = setup_chat_buffer({
      "@Assistant:",
      "<thinking>",
      long_thought,
      "</thinking>",
      "Answer here",
    })

    local result = hover_sync(client, bufnr, 2, 0) -- inside thinking block
    assert.is_not_nil(result)
    assert.is_truthy(result.contents.value:find("ThinkingSegment"))
    assert.is_truthy(result.contents.value:find("This is a long thought"))
    assert.is_true(#result.contents.value > #long_thought)
  end)

  it("returns hover for tool_use segment", function()
    local bufnr, client = setup_chat_buffer({
      "@Assistant:",
      "**Tool Use:** `bash` (`call_abc123`)",
      "```json",
      '{"command": "ls -la"}',
      "```",
    })

    local result = hover_sync(client, bufnr, 1, 5) -- on tool use header
    assert.is_not_nil(result)
    assert.is_truthy(result.contents.value:find("Tool_useSegment"))
    assert.is_truthy(result.contents.value:find("bash"))
    assert.is_truthy(result.contents.value:find("call_abc123"))
  end)

  it("returns hover for role marker line", function()
    local bufnr, client = setup_chat_buffer({
      "@You:",
      "Hello world",
    })

    local result = hover_sync(client, bufnr, 0, 0) -- 0-indexed, on "@You:" line
    assert.is_not_nil(result, "Expected hover result on role marker")
    assert.equals("markdown", result.contents.kind)
    assert.is_truthy(result.contents.value:find("MessageNode"))
    assert.is_truthy(result.contents.value:find("You"))
    assert.is_truthy(result.contents.value:find("Segments"))
  end)

  it("returns hover for frontmatter", function()
    local bufnr, client = setup_chat_buffer({
      "```yaml",
      "model: claude-3",
      "```",
      "@You:",
      "Hello",
    })

    local result = hover_sync(client, bufnr, 1, 0) -- 0-indexed, inside frontmatter
    assert.is_not_nil(result, "Expected hover result on frontmatter")
    assert.equals("markdown", result.contents.kind)
    assert.is_truthy(result.contents.value:find("FrontmatterNode"))
    assert.is_truthy(result.contents.value:find("yaml"))
  end)
end)
