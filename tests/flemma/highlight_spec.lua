describe("Highlight", function()
  local flemma
  local highlight

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.highlight"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.core"] = nil

    flemma = require("flemma")
    highlight = require("flemma.highlight")
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
    -- Clear Flemma highlight groups so `default = true` doesn't leak between tests
    for _, group in ipairs({
      "FlemmaRoleSystem",
      "FlemmaRoleUser",
      "FlemmaRoleAssistant",
      "FlemmaSystem",
      "FlemmaUser",
      "FlemmaAssistant",
      "FlemmaAssistantSpinner",
    }) do
      vim.api.nvim_set_hl(0, group, {})
    end
  end)

  describe("role marker highlights", function()
    it("should have fg color even when FlemmaAssistant only defines bg", function()
      -- Setup with bg-only expression for assistant
      flemma.setup({
        highlights = {
          assistant = "Normal+bg:#102020",
        },
      })

      -- Create a buffer with chat content so apply_syntax runs
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@Assistant: test" })

      -- Apply syntax to define the highlight groups
      highlight.apply_syntax()

      -- FlemmaRoleAssistant should have a fg color (fallback from Normal or defaults)
      local role_hl = vim.api.nvim_get_hl(0, { name = "FlemmaRoleAssistant", link = false })
      assert.is_not_nil(role_hl.fg, "FlemmaRoleAssistant should have fg even when FlemmaAssistant only defines bg")
    end)

    it("should apply role_style as gui attributes", function()
      flemma.setup({
        role_style = "bold,underline",
      })

      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You: test" })

      highlight.apply_syntax()

      local role_hl = vim.api.nvim_get_hl(0, { name = "FlemmaRoleUser", link = false })
      assert.is_true(role_hl.bold, "FlemmaRoleUser should have bold")
      assert.is_true(role_hl.underline, "FlemmaRoleUser should have underline")
    end)

    it("should use fg from base highlight group when available", function()
      -- Set a known fg on a test group
      vim.api.nvim_set_hl(0, "TestHighlight", { fg = "#ff0000" })

      flemma.setup({
        highlights = {
          system = "TestHighlight",
        },
      })

      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@System: test" })

      highlight.apply_syntax()

      local role_hl = vim.api.nvim_get_hl(0, { name = "FlemmaRoleSystem", link = false })
      assert.is_not_nil(role_hl.fg, "FlemmaRoleSystem should have fg from TestHighlight")
    end)
  end)

  describe("spinner highlight", function()
    it("should have fg but no bg", function()
      flemma.setup({
        highlights = {
          assistant = "Normal+bg:#102020",
        },
      })

      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@Assistant: test" })

      highlight.apply_syntax()

      local spinner_hl = vim.api.nvim_get_hl(0, { name = "FlemmaAssistantSpinner", link = false })
      assert.is_not_nil(spinner_hl.fg, "FlemmaAssistantSpinner should have fg")
      assert.is_nil(spinner_hl.bg, "FlemmaAssistantSpinner should NOT have bg (let line highlights provide it)")
    end)

    it("should not be a link to FlemmaAssistant", function()
      flemma.setup({})

      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@Assistant: test" })

      highlight.apply_syntax()

      local spinner_hl = vim.api.nvim_get_hl(0, { name = "FlemmaAssistantSpinner" })
      assert.is_nil(spinner_hl.link, "FlemmaAssistantSpinner should not be a link")
    end)
  end)

  describe("fold and tool highlight groups", function()
    local function setup_and_apply()
      flemma.setup({})
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@Assistant: test" })
      highlight.apply_syntax()
    end

    it("should define FlemmaToolIcon after apply_syntax", function()
      setup_and_apply()
      local hl = vim.api.nvim_get_hl(0, { name = "FlemmaToolIcon" })
      assert.is_truthy(hl.link or hl.fg, "FlemmaToolIcon should be defined")
    end)

    it("should define FlemmaToolName after apply_syntax", function()
      setup_and_apply()
      local hl = vim.api.nvim_get_hl(0, { name = "FlemmaToolName" })
      assert.is_truthy(hl.link or hl.fg, "FlemmaToolName should be defined")
    end)

    it("should define FlemmaFoldPreview after apply_syntax", function()
      setup_and_apply()
      local hl = vim.api.nvim_get_hl(0, { name = "FlemmaFoldPreview" })
      assert.is_truthy(hl.link or hl.fg, "FlemmaFoldPreview should be defined")
    end)

    it("should define FlemmaFoldMeta after apply_syntax", function()
      setup_and_apply()
      local hl = vim.api.nvim_get_hl(0, { name = "FlemmaFoldMeta" })
      assert.is_truthy(hl.link or hl.fg, "FlemmaFoldMeta should be defined")
    end)

    it("should still define FlemmaToolPreview (unchanged)", function()
      setup_and_apply()
      local hl = vim.api.nvim_get_hl(0, { name = "FlemmaToolPreview" })
      assert.is_truthy(hl.link or hl.fg, "FlemmaToolPreview should still be defined")
    end)

    it("should accept renamed config key tool_use_title", function()
      flemma.setup({
        highlights = { tool_use_title = "DiagnosticInfo" },
      })
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@Assistant: test" })
      highlight.apply_syntax()

      local hl = vim.api.nvim_get_hl(0, { name = "FlemmaToolUseTitle" })
      assert.is_truthy(hl.link or hl.fg, "FlemmaToolUseTitle should be defined via tool_use_title config key")
    end)

    it("should accept renamed config key tool_result_title", function()
      flemma.setup({
        highlights = { tool_result_title = "DiagnosticInfo" },
      })
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@Assistant: test" })
      highlight.apply_syntax()

      local hl = vim.api.nvim_get_hl(0, { name = "FlemmaToolResultTitle" })
      assert.is_truthy(hl.link or hl.fg, "FlemmaToolResultTitle should be defined via tool_result_title config key")
    end)
  end)
end)
