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
    package.loaded["flemma.ast.dump"] = nil
    package.loaded["flemma.ast.query"] = nil
    package.loaded["flemma.ast.nodes"] = nil
    package.loaded["flemma.preprocessor"] = nil
    package.loaded["flemma.preprocessor.registry"] = nil
    package.loaded["flemma.preprocessor.runner"] = nil
    package.loaded["flemma.preprocessor.context"] = nil
    package.loaded["flemma.utilities.encoding"] = nil
    package.loaded["flemma.preprocessor.rewriters.file_references"] = nil
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
    flemma.setup({ lsp = { enabled = true } })

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

  it("attaches to chat buffers when lsp is enabled", function()
    flemma.setup({ lsp = { enabled = true } })

    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = "chat"
    vim.cmd("doautocmd FileType")

    local clients = vim.lsp.get_clients({ name = "flemma", bufnr = bufnr })
    assert.is_true(#clients > 0, "Expected flemma LSP client to be attached")
  end)

  it("does not attach when lsp is disabled", function()
    flemma.setup({ lsp = { enabled = false } })

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
    assert.is_truthy(result.contents.value:find("expression"))
    assert.is_truthy(result.contents.value:find("name"))
  end)

  it("returns hover for plain text", function()
    local bufnr, client = setup_chat_buffer({
      "@You:",
      "Hello world",
    })

    local result = hover_sync(client, bufnr, 1, 2) -- on "Hello"
    assert.is_not_nil(result)
    assert.is_truthy(result.contents.value:find("text"))
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
    assert.is_truthy(result.contents.value:find("thinking"))
    assert.is_truthy(result.contents.value:find("This is a long thought"))
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
    assert.is_truthy(result.contents.value:find("tool_use"))
    assert.is_truthy(result.contents.value:find("bash"))
    assert.is_truthy(result.contents.value:find("call_abc123"))
  end)

  --- Helper: make a synchronous definition request
  ---@param client vim.lsp.Client
  ---@param bufnr integer
  ---@param line integer 0-indexed line
  ---@param character integer 0-indexed column
  ---@return table|nil result
  local function definition_sync(client, bufnr, line, character)
    local response = client:request_sync("textDocument/definition", {
      textDocument = { uri = vim.uri_from_bufnr(bufnr) },
      position = { line = line, character = character },
    }, 2000, bufnr)
    if response and response.result then
      return response.result
    end
    return nil
  end

  it("returns hover for @./file reference as expression segment", function()
    -- Regression: preprocessor-generated expression segments must have
    -- end_col so find_segment_at_position can match them by cursor column
    local fixture_dir = vim.fn.fnamemodify("tests/fixtures", ":p")

    flemma.setup({ lsp = { enabled = true } })

    test_counter = test_counter + 1
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, fixture_dir .. "lsp_hover_fileref_" .. test_counter .. ".chat")
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "See @./include_target.txt for details",
    })
    vim.bo[bufnr].filetype = "chat"
    vim.cmd("doautocmd FileType")

    vim.wait(1000, function()
      return #vim.lsp.get_clients({ name = "flemma", bufnr = bufnr }) > 0
    end)

    local clients = vim.lsp.get_clients({ name = "flemma", bufnr = bufnr })
    assert.is_true(#clients > 0, "Client should be attached")
    local client = clients[1]

    -- Hover on the file reference (0-indexed: line 1, col 6 = on the '/')
    local result = hover_sync(client, bufnr, 1, 6)
    assert.is_not_nil(result, "Expected hover result on file reference")
    assert.is_truthy(result.contents.value:find("expression"), "Should show expression, not text")
    assert.is_truthy(result.contents.value:find("include"))
  end)

  it("returns definition for @./file reference", function()
    -- Name the buffer inside fixtures/ so @./include_target.txt resolves
    local fixture_dir = vim.fn.fnamemodify("tests/fixtures", ":p")
    local target_path = fixture_dir .. "include_target.txt"

    flemma.setup({ lsp = { enabled = true } })

    test_counter = test_counter + 1
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, fixture_dir .. "lsp_def_test_" .. test_counter .. ".chat")
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "See @./include_target.txt for details",
    })
    vim.bo[bufnr].filetype = "chat"
    vim.cmd("doautocmd FileType")

    vim.wait(1000, function()
      return #vim.lsp.get_clients({ name = "flemma", bufnr = bufnr }) > 0
    end)

    local clients = vim.lsp.get_clients({ name = "flemma", bufnr = bufnr })
    assert.is_true(#clients > 0, "Client should be attached")
    local client = clients[1]

    -- Position on the file reference (0-indexed: line 1, on the @./ path)
    local result = definition_sync(client, bufnr, 1, 6)
    assert.is_not_nil(result, "Expected definition result for file reference")
    assert.equals(vim.uri_from_fname(target_path), result.uri)
  end)

  it("returns definition for @./file at start, middle, and end of reference", function()
    -- Regression: expression segments from preprocessor must have end_col
    -- so the cursor can match anywhere within the reference span
    local fixture_dir = vim.fn.fnamemodify("tests/fixtures", ":p")
    local target_path = fixture_dir .. "include_target.txt"

    flemma.setup({ lsp = { enabled = true } })

    test_counter = test_counter + 1
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, fixture_dir .. "lsp_def_pos_" .. test_counter .. ".chat")
    vim.api.nvim_set_current_buf(bufnr)
    -- "See @./include_target.txt ok"
    --  0123456789...
    --      ^                    ^ @=col4, t=col25 (0-indexed)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "See @./include_target.txt ok",
    })
    vim.bo[bufnr].filetype = "chat"
    vim.cmd("doautocmd FileType")

    vim.wait(1000, function()
      return #vim.lsp.get_clients({ name = "flemma", bufnr = bufnr }) > 0
    end)

    local clients = vim.lsp.get_clients({ name = "flemma", bufnr = bufnr })
    assert.is_true(#clients > 0, "Client should be attached")
    local client = clients[1]

    -- At start of reference (0-indexed col 4 = '@')
    local result_start = definition_sync(client, bufnr, 1, 4)
    assert.is_not_nil(result_start, "Should resolve at start of @./file reference")
    assert.equals(vim.uri_from_fname(target_path), result_start.uri)

    -- In the middle (0-indexed col 12 = somewhere in 'include_target')
    local result_mid = definition_sync(client, bufnr, 1, 12)
    assert.is_not_nil(result_mid, "Should resolve in middle of @./file reference")
    assert.equals(vim.uri_from_fname(target_path), result_mid.uri)

    -- Near end (0-indexed col 24 = 'x' in '.txt')
    local result_end = definition_sync(client, bufnr, 1, 24)
    assert.is_not_nil(result_end, "Should resolve at end of @./file reference")
    assert.equals(vim.uri_from_fname(target_path), result_end.uri)
  end)

  it("returns nil for definition on non-include expression", function()
    local bufnr, client = setup_chat_buffer({
      "@You:",
      "Hello {{ 1 + 1 }} world",
    })

    local result = definition_sync(client, bufnr, 1, 10) -- on the expression
    assert.is_nil(result, "Non-include expression should not have a definition")
  end)

  it("returns nil for definition on plain text", function()
    local bufnr, client = setup_chat_buffer({
      "@You:",
      "Just some plain text",
    })

    local result = definition_sync(client, bufnr, 1, 5)
    assert.is_nil(result, "Plain text should not have a definition")
  end)

  it("returns hover for role marker line", function()
    local bufnr, client = setup_chat_buffer({
      "@You:",
      "Hello world",
    })

    local result = hover_sync(client, bufnr, 0, 0) -- 0-indexed, on "@You:" line
    assert.is_not_nil(result, "Expected hover result on role marker")
    assert.equals("markdown", result.contents.kind)
    assert.is_truthy(result.contents.value:find("message"))
    assert.is_truthy(result.contents.value:find("You"))
    assert.is_truthy(result.contents.value:find("segments"))
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
    assert.is_truthy(result.contents.value:find("frontmatter"))
    assert.is_truthy(result.contents.value:find("yaml"))
  end)

  it("returns definition from tool_use to tool_result", function()
    local bufnr, client = setup_chat_buffer({
      "@Assistant:",
      "**Tool Use:** `bash` (`call_nav1`)",
      "```json",
      '{"command": "ls"}',
      "```",
      "@You:",
      "**Tool Result:** `call_nav1`",
      "",
      "```",
      "output here",
      "```",
    })

    -- Cursor on tool_use header (0-indexed line 1)
    local result = definition_sync(client, bufnr, 1, 5)
    assert.is_not_nil(result, "Expected definition from tool_use to tool_result")
    -- Tool result header is at line 7 (1-indexed) = line 6 (0-indexed)
    assert.equals(6, result.range.start.line)
  end)

  it("returns definition from tool_result to tool_use", function()
    local bufnr, client = setup_chat_buffer({
      "@Assistant:",
      "**Tool Use:** `bash` (`call_nav2`)",
      "```json",
      '{"command": "pwd"}',
      "```",
      "@You:",
      "**Tool Result:** `call_nav2`",
      "",
      "```",
      "result data",
      "```",
    })

    -- Cursor on tool_result header (0-indexed line 6)
    local result = definition_sync(client, bufnr, 6, 5)
    assert.is_not_nil(result, "Expected definition from tool_result to tool_use")
    -- Tool use header is at line 2 (1-indexed) = line 1 (0-indexed)
    assert.equals(1, result.range.start.line)
  end)

  it("returns nil for tool_use with no result", function()
    local bufnr, client = setup_chat_buffer({
      "@Assistant:",
      "**Tool Use:** `bash` (`call_noresult`)",
      "```json",
      '{"command": "ls"}',
      "```",
    })

    local result = definition_sync(client, bufnr, 1, 5)
    assert.is_nil(result, "No definition when tool_use has no result")
  end)

  it("falls through to include resolution for non-tool segments", function()
    local bufnr, client = setup_chat_buffer({
      "@You:",
      "Just some plain text",
    })

    -- Plain text should return nil (no definition)
    local result = definition_sync(client, bufnr, 1, 5)
    assert.is_nil(result)
  end)

  it("returns definition for {{ include(file) }} with frontmatter variable", function()
    -- End-to-end: frontmatter sets a variable, expression uses it for include,
    -- LSP definition resolves to the included file.
    local fixture_dir = vim.fn.fnamemodify("tests/fixtures", ":p")
    local target_path = fixture_dir .. "include_target.txt"

    flemma.setup({ lsp = { enabled = true } })

    test_counter = test_counter + 1
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, fixture_dir .. "lsp_fm_include_" .. test_counter .. ".chat")
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```lua",
      "file = './include_target.txt'",
      "```",
      "@System:",
      "{{ include(file) }}",
    })
    vim.bo[bufnr].filetype = "chat"
    vim.cmd("doautocmd FileType")

    vim.wait(1000, function()
      return #vim.lsp.get_clients({ name = "flemma", bufnr = bufnr }) > 0
    end)

    local clients = vim.lsp.get_clients({ name = "flemma", bufnr = bufnr })
    assert.is_true(#clients > 0, "Client should be attached")
    local client = clients[1]

    -- Cursor on the expression (0-indexed: line 4, col 5)
    local result = definition_sync(client, bufnr, 4, 5)
    assert.is_not_nil(result, "LSP definition should resolve include with frontmatter variable")
    assert.equals(vim.uri_from_fname(target_path), result.uri)
  end)

  it("returns definition for indirect include via frontmatter variable", function()
    -- Frontmatter evaluates include() at definition time, storing the result
    -- in a variable. The body expression {{ mod }} references that variable.
    -- Navigation must trace SOURCE_PATH through the indirection.
    local fixture_dir = vim.fn.fnamemodify("tests/fixtures", ":p")
    local target_path = fixture_dir .. "include_target.txt"

    flemma.setup({ lsp = { enabled = true } })

    test_counter = test_counter + 1
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, fixture_dir .. "lsp_indirect_" .. test_counter .. ".chat")
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```lua",
      "file = './include_target.txt'",
      "mod = include(file)",
      "```",
      "@System:",
      "{{ mod }}",
    })
    vim.bo[bufnr].filetype = "chat"
    vim.cmd("doautocmd FileType")

    vim.wait(1000, function()
      return #vim.lsp.get_clients({ name = "flemma", bufnr = bufnr }) > 0
    end)

    local clients = vim.lsp.get_clients({ name = "flemma", bufnr = bufnr })
    assert.is_true(#clients > 0, "Client should be attached")
    local client = clients[1]

    -- Cursor on {{ mod }} (0-indexed: line 5, col 4)
    local result = definition_sync(client, bufnr, 5, 4)
    assert.is_not_nil(result, "Indirect include via frontmatter variable should resolve")
    assert.equals(vim.uri_from_fname(target_path), result.uri)
  end)

  it("returns definition for include when frontmatter uses flemma.opt", function()
    -- Regression: frontmatter with flemma.opt writes must not crash navigation.
    -- The write proxy requires bufnr to be passed through; without it, nested
    -- access like flemma.opt.tools.max_concurrent errors on a plain {} table.
    local fixture_dir = vim.fn.fnamemodify("tests/fixtures", ":p")
    local target_path = fixture_dir .. "include_target.txt"

    flemma.setup({ lsp = { enabled = true } })

    test_counter = test_counter + 1
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, fixture_dir .. "lsp_fm_opt_" .. test_counter .. ".chat")
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```lua",
      "flemma.opt.thinking = 'minimal'",
      "flemma.opt.tools.max_concurrent = 1",
      "file = './include_target.txt'",
      "```",
      "@System:",
      "{{ include(file) }}",
    })
    vim.bo[bufnr].filetype = "chat"
    vim.cmd("doautocmd FileType")

    vim.wait(1000, function()
      return #vim.lsp.get_clients({ name = "flemma", bufnr = bufnr }) > 0
    end)

    local clients = vim.lsp.get_clients({ name = "flemma", bufnr = bufnr })
    assert.is_true(#clients > 0, "Client should be attached")
    local client = clients[1]

    -- Cursor on the expression (0-indexed: line 6, col 5)
    local result = definition_sync(client, bufnr, 6, 5)
    assert.is_not_nil(result, "flemma.opt in frontmatter must not break LSP include resolution")
    assert.equals(vim.uri_from_fname(target_path), result.uri)
  end)

  it("returns definition for include of file containing literal {{ }} syntax", function()
    -- Regression: files like README.md that document {{ }} and {% %} syntax
    -- cause template compilation errors. Navigation's path-only include()
    -- must resolve the path without reading or compiling file content.
    local fixture_dir = vim.fn.fnamemodify("tests/fixtures", ":p")
    local target_path = fixture_dir .. "doc_with_templates.txt"

    flemma.setup({ lsp = { enabled = true } })

    test_counter = test_counter + 1
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, fixture_dir .. "lsp_doc_templates_" .. test_counter .. ".chat")
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```lua",
      "doc = './doc_with_templates.txt'",
      "```",
      "@System:",
      "{{ include(doc) }}",
    })
    vim.bo[bufnr].filetype = "chat"
    vim.cmd("doautocmd FileType")

    vim.wait(1000, function()
      return #vim.lsp.get_clients({ name = "flemma", bufnr = bufnr }) > 0
    end)

    local clients = vim.lsp.get_clients({ name = "flemma", bufnr = bufnr })
    assert.is_true(#clients > 0, "Client should be attached")
    local client = clients[1]

    -- Cursor on the expression (0-indexed: line 4, col 5)
    local result = definition_sync(client, bufnr, 4, 5)
    assert.is_not_nil(result, "Include of file with literal {{ }} must resolve via LSP")
    assert.equals(vim.uri_from_fname(target_path), result.uri)
  end)

  it("returns nil for urn:flemma: personality includes", function()
    local bufnr, client = setup_chat_buffer({
      "@System:",
      "{{ include('urn:flemma:personality:coding-assistant') }}",
    })

    -- URN includes are virtual — no file to jump to
    local result = definition_sync(client, bufnr, 1, 5)
    assert.is_nil(result, "URN personality includes have no file definition")
  end)

  it("returns definition from tool_use json body to tool_result", function()
    local bufnr, client = setup_chat_buffer({
      "@Assistant:",
      "**Tool Use:** `bash` (`call_body`)",
      "```json",
      '{"command": "ls"}',
      "```",
      "@You:",
      "**Tool Result:** `call_body`",
      "",
      "```",
      "output",
      "```",
    })

    -- Cursor on JSON body line (0-indexed line 3, inside tool_use segment)
    local result = definition_sync(client, bufnr, 3, 2)
    assert.is_not_nil(result, "Should navigate from tool_use body to tool_result")
    assert.equals(6, result.range.start.line)
  end)
end)
