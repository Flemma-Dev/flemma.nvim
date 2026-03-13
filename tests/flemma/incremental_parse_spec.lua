local parser = require("flemma.parser")
local state = require("flemma.state")

describe("parse_messages extraction", function()
  it("parse_lines produces same result after refactor - simple conversation", function()
    local lines = {
      "@System:",
      "You are helpful.",
      "@You:",
      "Hello",
      "@Assistant:",
      "Hi there!",
      "@You:",
      "Thanks",
    }
    local doc = parser.parse_lines(lines)
    assert.equals(4, #doc.messages)
    assert.equals("System", doc.messages[1].role)
    assert.equals("You", doc.messages[2].role)
    assert.equals("Assistant", doc.messages[3].role)
    assert.equals("You", doc.messages[4].role)
    assert.equals(1, doc.messages[1].position.start_line)
    assert.equals(2, doc.messages[1].position.end_line)
    assert.equals(3, doc.messages[2].position.start_line)
    assert.equals(4, doc.messages[2].position.end_line)
    assert.equals(5, doc.messages[3].position.start_line)
    assert.equals(6, doc.messages[3].position.end_line)
    assert.equals(7, doc.messages[4].position.start_line)
    assert.equals(8, doc.messages[4].position.end_line)
  end)

  it("parse_lines with frontmatter offsets positions correctly", function()
    local lines = {
      "```toml",
      'model = "test"',
      "```",
      "@You:",
      "Hello",
      "@Assistant:",
      "World",
    }
    local doc = parser.parse_lines(lines)
    assert.is_not_nil(doc.frontmatter)
    assert.equals(2, #doc.messages)
    assert.equals(4, doc.messages[1].position.start_line)
    assert.equals(5, doc.messages[1].position.end_line)
    assert.equals(6, doc.messages[2].position.start_line)
    assert.equals(7, doc.messages[2].position.end_line)
  end)
end)

describe("create_snapshot", function()
  local bufnr

  before_each(function()
    package.loaded["flemma.parser"] = nil
    package.loaded["flemma.state"] = nil
    parser = require("flemma.parser")
    state = require("flemma.state")
    bufnr = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    state.cleanup_buffer_state(bufnr)
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("captures frontmatter and messages from buffer", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```toml",
      'model = "test"',
      "```",
      "@System:",
      "You are helpful.",
      "@You:",
      "Hello",
    })

    parser.create_snapshot(bufnr)

    local bs = state.get_buffer_state(bufnr)
    local snapshot = bs.ast_snapshot_before_send
    assert.is_not_nil(snapshot)
    assert.is_not_nil(snapshot.frontmatter)
    assert.equals("toml", snapshot.frontmatter.language)
    assert.equals(2, #snapshot.messages)
    assert.equals("System", snapshot.messages[1].role)
    assert.equals("You", snapshot.messages[2].role)
    assert.equals(8, snapshot.freeze_line)
  end)

  it("sets freeze_line to line after last content", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "Hello",
    })

    parser.create_snapshot(bufnr)

    local snapshot = state.get_buffer_state(bufnr).ast_snapshot_before_send
    assert.equals(3, snapshot.freeze_line)
  end)

  it("handles empty buffer", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

    parser.create_snapshot(bufnr)

    local snapshot = state.get_buffer_state(bufnr).ast_snapshot_before_send
    assert.is_not_nil(snapshot)
    assert.is_nil(snapshot.frontmatter)
    assert.equals(0, #snapshot.messages)
  end)
end)

describe("clear_snapshot", function()
  local bufnr

  before_each(function()
    package.loaded["flemma.parser"] = nil
    package.loaded["flemma.state"] = nil
    parser = require("flemma.parser")
    state = require("flemma.state")
    bufnr = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    state.cleanup_buffer_state(bufnr)
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("removes snapshot from buffer state", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "Hello",
    })

    parser.create_snapshot(bufnr)
    assert.is_not_nil(state.get_buffer_state(bufnr).ast_snapshot_before_send)

    parser.clear_snapshot(bufnr)
    assert.is_nil(state.get_buffer_state(bufnr).ast_snapshot_before_send)
  end)
end)

describe("incremental get_parsed_document", function()
  local bufnr

  before_each(function()
    package.loaded["flemma.parser"] = nil
    package.loaded["flemma.state"] = nil
    parser = require("flemma.parser")
    state = require("flemma.state")
    bufnr = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    state.cleanup_buffer_state(bufnr)
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  --- Deep-compare two AST documents, ignoring table identity.
  --- Compares kind, role, positions, segment values — everything
  --- that matters for correctness.
  ---@param doc_a flemma.ast.DocumentNode
  ---@param doc_b flemma.ast.DocumentNode
  local function assert_docs_equal(doc_a, doc_b)
    -- Frontmatter
    if doc_a.frontmatter then
      assert.is_not_nil(doc_b.frontmatter, "Both docs should have frontmatter")
      assert.equals(doc_a.frontmatter.language, doc_b.frontmatter.language)
      assert.equals(doc_a.frontmatter.code, doc_b.frontmatter.code)
    else
      assert.is_nil(doc_b.frontmatter, "Neither doc should have frontmatter")
    end

    -- Messages
    assert.equals(#doc_a.messages, #doc_b.messages, "Message count should match")
    for i, msg_a in ipairs(doc_a.messages) do
      local msg_b = doc_b.messages[i]
      assert.equals(msg_a.role, msg_b.role, "Message " .. i .. " role")
      assert.equals(msg_a.position.start_line, msg_b.position.start_line, "Message " .. i .. " start_line")
      assert.equals(msg_a.position.end_line, msg_b.position.end_line, "Message " .. i .. " end_line")
      assert.equals(#msg_a.segments, #msg_b.segments, "Message " .. i .. " segment count")
      for j, seg_a in ipairs(msg_a.segments) do
        local seg_b = msg_b.segments[j]
        local prefix = "Message " .. i .. " segment " .. j
        assert.equals(seg_a.kind, seg_b.kind, prefix .. " kind")
        if seg_a.kind == "text" then
          assert.equals(seg_a.value, seg_b.value, prefix .. " value")
        elseif seg_a.kind == "thinking" then
          assert.equals(seg_a.content, seg_b.content, prefix .. " content")
        elseif seg_a.kind == "tool_use" then
          assert.equals(seg_a.id, seg_b.id, prefix .. " id")
          assert.equals(seg_a.name, seg_b.name, prefix .. " name")
        elseif seg_a.kind == "tool_result" then
          assert.equals(seg_a.tool_use_id, seg_b.tool_use_id, prefix .. " tool_use_id")
          assert.equals(seg_a.content, seg_b.content, prefix .. " content")
        end
      end
    end

    -- Document position
    assert.equals(doc_a.position.start_line, doc_b.position.start_line)
    assert.equals(doc_a.position.end_line, doc_b.position.end_line)

    -- Errors
    assert.equals(#doc_a.errors, #doc_b.errors, "Error count should match")
  end

  it("incremental parse produces same result as full parse", function()
    -- Phase 1: Set up buffer with existing conversation
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```toml",
      'model = "test"',
      "```",
      "@System:",
      "You are helpful.",
      "@You:",
      "Hello",
    })

    -- Phase 2: Create snapshot (simulates pre-send)
    parser.create_snapshot(bufnr)

    -- Phase 3: Append new content (simulates streaming)
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, {
      "@Assistant:",
      "Hi there! I can help you.",
      "",
      "What would you like to know?",
    })

    -- Phase 4: Get incremental parse result
    local incremental_doc = parser.get_parsed_document(bufnr)

    -- Phase 5: Clear snapshot and invalidate cache to force full parse
    parser.clear_snapshot(bufnr)
    state.get_buffer_state(bufnr).ast_cache = nil
    local full_doc = parser.get_parsed_document(bufnr)

    -- Phase 6: Compare
    assert_docs_equal(full_doc, incremental_doc)
  end)

  it("incremental parse handles assistant with tool use", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "List files",
    })

    parser.create_snapshot(bufnr)

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, {
      "@Assistant:",
      "",
      "**Tool Use:** `bash` (`call_abc`)",
      "```json",
      '{"command": "ls"}',
      "```",
    })

    local incremental_doc = parser.get_parsed_document(bufnr)

    parser.clear_snapshot(bufnr)
    state.get_buffer_state(bufnr).ast_cache = nil
    local full_doc = parser.get_parsed_document(bufnr)

    assert_docs_equal(full_doc, incremental_doc)
  end)

  it("incremental parse handles assistant with thinking", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@System:",
      "Be thoughtful.",
      "@You:",
      "What is 2+2?",
    })

    parser.create_snapshot(bufnr)

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, {
      "@Assistant:",
      "<thinking>",
      "Let me calculate: 2+2=4",
      "</thinking>",
      "The answer is 4.",
    })

    local incremental_doc = parser.get_parsed_document(bufnr)

    parser.clear_snapshot(bufnr)
    state.get_buffer_state(bufnr).ast_cache = nil
    local full_doc = parser.get_parsed_document(bufnr)

    assert_docs_equal(full_doc, incremental_doc)
  end)

  it("incremental parse with blank lines between freeze and assistant", function()
    -- Tests the accepted position divergence: a blank separator line added
    -- after the snapshot will be absorbed into the last @You: message by a
    -- full parse (extending its end_line) but NOT by the incremental parse
    -- (the snapshot captured @You: before the blank existed). This is
    -- documented in the Design Decisions section of the plan — the divergence
    -- is visually invisible and corrected on clear_snapshot.
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "Hello",
    })

    parser.create_snapshot(bufnr)

    -- start_progress / on_content typically adds a blank line before @Assistant:
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, {
      "",
      "@Assistant:",
      "Response here",
    })

    local incremental_doc = parser.get_parsed_document(bufnr)

    parser.clear_snapshot(bufnr)
    state.get_buffer_state(bufnr).ast_cache = nil
    local full_doc = parser.get_parsed_document(bufnr)

    -- Message count and roles must match
    assert.equals(#full_doc.messages, #incremental_doc.messages)
    assert.equals("You", incremental_doc.messages[1].role)
    assert.equals("Assistant", incremental_doc.messages[2].role)

    -- @Assistant: message positions and content match exactly
    assert.equals(
      full_doc.messages[2].position.start_line,
      incremental_doc.messages[2].position.start_line
    )
    assert.equals(
      full_doc.messages[2].position.end_line,
      incremental_doc.messages[2].position.end_line
    )

    -- @You: end_line diverges by 1 (accepted — see Design Decisions)
    -- Full parse: @You: absorbs the blank line (end_line = 3)
    -- Incremental: @You: was snapshotted without it (end_line = 2)
    assert.equals(2, incremental_doc.messages[1].position.end_line)
    assert.equals(3, full_doc.messages[1].position.end_line)
  end)

  it("uses changedtick cache even with snapshot", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "Hello",
    })

    parser.create_snapshot(bufnr)

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, {
      "@Assistant:",
      "Hi",
    })

    -- First call parses
    local doc1 = parser.get_parsed_document(bufnr)
    -- Second call should return cached (same changedtick)
    local doc2 = parser.get_parsed_document(bufnr)
    assert.equals(doc1, doc2, "Should return same table reference from cache")
  end)

  it("full parse resumes after clear_snapshot", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "Hello",
    })

    parser.create_snapshot(bufnr)

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, {
      "@Assistant:",
      "Hi",
    })

    -- Incremental parse
    parser.get_parsed_document(bufnr)

    -- Clear snapshot
    parser.clear_snapshot(bufnr)

    -- Append more content
    line_count = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, {
      "@You:",
      "Thanks",
    })

    -- Should do full parse now (no snapshot)
    local doc = parser.get_parsed_document(bufnr)
    assert.equals(3, #doc.messages)
    assert.equals("You", doc.messages[3].role)
  end)
end)
