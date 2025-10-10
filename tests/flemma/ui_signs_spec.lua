describe("UI Sign Placement", function()
  local flemma
  local ui
  local parser

  before_each(function()
    -- Invalidate caches to ensure clean setup
    package.loaded["flemma"] = nil
    package.loaded["flemma.ui"] = nil
    package.loaded["flemma.parser"] = nil
    package.loaded["flemma.config"] = nil

    flemma = require("flemma")
    ui = require("flemma.ui")
    parser = require("flemma.parser")

    -- Setup with signs enabled
    flemma.setup({
      signs = {
        enabled = true,
      },
    })

    -- Clean up any buffers created during previous tests
    vim.cmd("silent! %bdelete!")
  end)

  after_each(function()
    -- Clean up any buffers created during the test
    vim.cmd("silent! %bdelete!")
  end)

  -- Helper function to get placed signs
  local function get_placed_signs(bufnr)
    local signs = vim.fn.sign_getplaced(bufnr, { group = "flemma_ns" })
    if #signs == 0 then
      return {}
    end
    return signs[1].signs or {}
  end

  -- Helper function to extract sign positions and names
  local function get_sign_info(bufnr)
    local signs = get_placed_signs(bufnr)
    local result = {}
    for _, sign in ipairs(signs) do
      table.insert(result, {
        line = sign.lnum,
        name = sign.name,
      })
    end
    -- Sort by line number for consistent comparison
    table.sort(result, function(a, b)
      return a.line < b.line
    end)
    return result
  end

  describe("without frontmatter", function()
    it("should place signs at correct line numbers", function()
      -- Arrange
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You: first message",
        "@Assistant: response",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Act
      ui.update_ui(bufnr)

      -- Assert
      local sign_info = get_sign_info(bufnr)
      assert.are.equal(2, #sign_info)
      assert.are.equal(1, sign_info[1].line)
      assert.are.equal("flemma_user", sign_info[1].name)
      assert.are.equal(2, sign_info[2].line)
      assert.are.equal("flemma_assistant", sign_info[2].name)
    end)

    it("should place signs on all lines of multi-line messages", function()
      -- Arrange
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You: first line",
        "second line",
        "third line",
        "@Assistant: response line 1",
        "response line 2",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Act
      ui.update_ui(bufnr)

      -- Assert
      local sign_info = get_sign_info(bufnr)
      assert.are.equal(5, #sign_info)

      -- User message on lines 1-3
      assert.are.equal(1, sign_info[1].line)
      assert.are.equal("flemma_user", sign_info[1].name)
      assert.are.equal(2, sign_info[2].line)
      assert.are.equal("flemma_user", sign_info[2].name)
      assert.are.equal(3, sign_info[3].line)
      assert.are.equal("flemma_user", sign_info[3].name)

      -- Assistant message on lines 4-5
      assert.are.equal(4, sign_info[4].line)
      assert.are.equal("flemma_assistant", sign_info[4].name)
      assert.are.equal(5, sign_info[5].line)
      assert.are.equal("flemma_assistant", sign_info[5].name)
    end)

    it("should handle System role messages", function()
      -- Arrange
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@System: system prompt",
        "@You: user message",
        "@Assistant: assistant response",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Act
      ui.update_ui(bufnr)

      -- Assert
      local sign_info = get_sign_info(bufnr)
      assert.are.equal(3, #sign_info)
      assert.are.equal("flemma_system", sign_info[1].name)
      assert.are.equal("flemma_user", sign_info[2].name)
      assert.are.equal("flemma_assistant", sign_info[3].name)
    end)
  end)

  describe("with frontmatter", function()
    it("should correctly offset sign positions for Lua frontmatter", function()
      -- Arrange
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "```lua",
        "x = 5",
        "```",
        "@You: first message",
        "@Assistant: response",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Act
      ui.update_ui(bufnr)

      -- Assert
      local sign_info = get_sign_info(bufnr)
      assert.are.equal(2, #sign_info)
      -- Signs should be at lines 4 and 5, NOT lines 1 and 2
      assert.are.equal(4, sign_info[1].line, "User message should be at line 4")
      assert.are.equal("flemma_user", sign_info[1].name)
      assert.are.equal(5, sign_info[2].line, "Assistant message should be at line 5")
      assert.are.equal("flemma_assistant", sign_info[2].name)
    end)

    it("should correctly offset sign positions for JSON frontmatter", function()
      -- Arrange
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "```json",
        '{"key": "value"}',
        "```",
        "@You: first message",
        "@Assistant: response",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Act
      ui.update_ui(bufnr)

      -- Assert
      local sign_info = get_sign_info(bufnr)
      assert.are.equal(2, #sign_info)
      assert.are.equal(4, sign_info[1].line)
      assert.are.equal(5, sign_info[2].line)
    end)

    it("should handle multi-line frontmatter correctly", function()
      -- Arrange
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "```lua",
        "function greet(name)",
        "  return 'Hello, ' .. name",
        "end",
        "x = 42",
        "```",
        "@You: message after frontmatter",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Act
      ui.update_ui(bufnr)

      -- Assert
      local sign_info = get_sign_info(bufnr)
      assert.are.equal(1, #sign_info)
      -- Message should be at line 7, NOT line 1
      assert.are.equal(7, sign_info[1].line, "User message should be at line 7 after 6-line frontmatter block")
      assert.are.equal("flemma_user", sign_info[1].name)
    end)

    it("should handle multi-line messages with frontmatter", function()
      -- Arrange
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "```json",
        '{"name": "test"}',
        "```",
        "@You: first line",
        "second line",
        "third line",
        "@Assistant: response line 1",
        "response line 2",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Act
      ui.update_ui(bufnr)

      -- Assert
      local sign_info = get_sign_info(bufnr)
      assert.are.equal(5, #sign_info)

      -- User message should be on lines 4-6
      assert.are.equal(4, sign_info[1].line)
      assert.are.equal("flemma_user", sign_info[1].name)
      assert.are.equal(5, sign_info[2].line)
      assert.are.equal("flemma_user", sign_info[2].name)
      assert.are.equal(6, sign_info[3].line)
      assert.are.equal("flemma_user", sign_info[3].name)

      -- Assistant message should be on lines 7-8
      assert.are.equal(7, sign_info[4].line)
      assert.are.equal("flemma_assistant", sign_info[4].name)
      assert.are.equal(8, sign_info[5].line)
      assert.are.equal("flemma_assistant", sign_info[5].name)
    end)

    it("should handle frontmatter with System messages", function()
      -- Arrange
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "```lua",
        "model = 'gpt-4'",
        "```",
        "@System: system prompt",
        "@You: user message",
        "@Assistant: assistant response",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Act
      ui.update_ui(bufnr)

      -- Assert
      local sign_info = get_sign_info(bufnr)
      assert.are.equal(3, #sign_info)
      assert.are.equal(4, sign_info[1].line)
      assert.are.equal("flemma_system", sign_info[1].name)
      assert.are.equal(5, sign_info[2].line)
      assert.are.equal("flemma_user", sign_info[2].name)
      assert.are.equal(6, sign_info[3].line)
      assert.are.equal("flemma_assistant", sign_info[3].name)
    end)
  end)

  describe("sign updates during streaming", function()
    it("should maintain correct sign positions as content is added", function()
      -- Arrange - Start with frontmatter and one message
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "```lua",
        "x = 5",
        "```",
        "@You: first message",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      ui.update_ui(bufnr)

      -- Verify initial state
      local initial_signs = get_sign_info(bufnr)
      assert.are.equal(1, #initial_signs)
      assert.are.equal(4, initial_signs[1].line)

      -- Act - Simulate streaming by adding assistant response
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "@Assistant: streaming response" })
      ui.update_ui(bufnr)

      -- Assert - Signs should be at correct positions
      local updated_signs = get_sign_info(bufnr)
      assert.are.equal(2, #updated_signs)
      assert.are.equal(4, updated_signs[1].line, "User message should still be at line 4")
      assert.are.equal("flemma_user", updated_signs[1].name)
      assert.are.equal(5, updated_signs[2].line, "Assistant message should be at line 5")
      assert.are.equal("flemma_assistant", updated_signs[2].name)
    end)

    it("should handle multi-line streaming content", function()
      -- Arrange
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "```lua",
        "x = 5",
        "```",
        "@You: question",
        "@Assistant: line 1",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      ui.update_ui(bufnr)

      -- Act - Add more lines to the assistant response
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "line 2", "line 3" })
      ui.update_ui(bufnr)

      -- Assert
      local signs = get_sign_info(bufnr)
      assert.are.equal(4, #signs)
      -- User at line 4
      assert.are.equal(4, signs[1].line)
      assert.are.equal("flemma_user", signs[1].name)
      -- Assistant at lines 5-7
      assert.are.equal(5, signs[2].line)
      assert.are.equal("flemma_assistant", signs[2].name)
      assert.are.equal(6, signs[3].line)
      assert.are.equal("flemma_assistant", signs[3].name)
      assert.are.equal(7, signs[4].line)
      assert.are.equal("flemma_assistant", signs[4].name)
    end)
  end)

  describe("parser position verification", function()
    it("should return correct positions without frontmatter", function()
      local lines = {
        "@You: first message",
        "@Assistant: response",
      }
      local doc = parser.parse_lines(lines)

      assert.are.equal(2, #doc.messages)
      assert.are.equal(1, doc.messages[1].position.start_line)
      assert.are.equal(1, doc.messages[1].position.end_line)
      assert.are.equal(2, doc.messages[2].position.start_line)
      assert.are.equal(2, doc.messages[2].position.end_line)
    end)

    it("should return correct positions with frontmatter", function()
      local lines = {
        "```lua",
        "x = 5",
        "```",
        "@You: first message",
        "@Assistant: response",
      }
      local doc = parser.parse_lines(lines)

      assert.are.equal(2, #doc.messages)
      -- Messages should start at line 4, not line 1
      assert.are.equal(4, doc.messages[1].position.start_line)
      assert.are.equal(4, doc.messages[1].position.end_line)
      assert.are.equal(5, doc.messages[2].position.start_line)
      assert.are.equal(5, doc.messages[2].position.end_line)
    end)

    it("should return correct positions for multi-line messages with frontmatter", function()
      local lines = {
        "```json",
        '{"key": "value"}',
        "```",
        "@You: line 1",
        "line 2",
        "line 3",
        "@Assistant: response",
      }
      local doc = parser.parse_lines(lines)

      assert.are.equal(2, #doc.messages)
      -- User message spans lines 4-6
      assert.are.equal(4, doc.messages[1].position.start_line)
      assert.are.equal(6, doc.messages[1].position.end_line)
      -- Assistant message at line 7
      assert.are.equal(7, doc.messages[2].position.start_line)
      assert.are.equal(7, doc.messages[2].position.end_line)
    end)
  end)
end)
