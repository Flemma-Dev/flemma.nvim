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
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@Assistant:", "test" })

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
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "test" })

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
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@System:", "test" })

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
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@Assistant:", "test" })

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
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@Assistant:", "test" })

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
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@Assistant:", "test" })
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
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@Assistant:", "test" })
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
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@Assistant:", "test" })
      highlight.apply_syntax()

      local hl = vim.api.nvim_get_hl(0, { name = "FlemmaToolResultTitle" })
      assert.is_truthy(hl.link or hl.fg, "FlemmaToolResultTitle should be defined via tool_result_title config key")
    end)
  end)
end)

describe("^ contrast operator in expressions", function()
  local highlight
  local color

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.highlight"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.utilities.color"] = nil
    require("flemma").setup({})
    highlight = require("flemma.highlight")
    color = require("flemma.utilities.color")
    -- Set up known highlight groups for testing
    vim.api.nvim_set_hl(0, "TestDarkBg", { bg = 0x111111, fg = 0x222222 })
    vim.api.nvim_set_hl(0, "TestLightFg", { fg = 0xffffff })
  end)

  after_each(function()
    vim.api.nvim_set_hl(0, "TestDarkBg", {})
    vim.api.nvim_set_hl(0, "TestLightFg", {})
  end)

  it("should pass through fg that already meets contrast", function()
    -- White fg against dark bg: already high contrast
    local result = highlight.resolve_expression("TestLightFg^fg:4.5", "#111111")
    assert.is_not_nil(result)
    assert.is_not_nil(result.fg)
    assert.are.equal("#ffffff", result.fg)
  end)

  it("should adjust fg when contrast is insufficient", function()
    -- Dark fg against dark bg: insufficient contrast
    local result = highlight.resolve_expression("TestDarkBg^fg:4.5", "#111111")
    assert.is_not_nil(result)
    assert.is_not_nil(result.fg)
    -- Should be lighter than the original #222222
    local ratio = color.contrast_ratio(result.fg, "#111111")
    assert.is_true(ratio >= 4.5, "adjusted fg should meet 4.5:1 contrast: got " .. tostring(ratio))
  end)

  it("should compose with blend operations: blend first then contrast", function()
    -- Blend first, then ensure contrast
    local result = highlight.resolve_expression("TestLightFg-fg:#dddddd^fg:4.5", "#111111")
    assert.is_not_nil(result)
    assert.is_not_nil(result.fg)
    local ratio = color.contrast_ratio(result.fg, "#111111")
    assert.is_true(ratio >= 4.5, "composed expression should meet contrast: got " .. tostring(ratio))
  end)

  it("should ignore ^ operator when no contrast_bg provided", function()
    -- Without contrast_bg, ^ is a no-op (doesn't crash, returns blended result)
    local result = highlight.resolve_expression("TestDarkBg^fg:4.5", nil)
    assert.is_not_nil(result)
    assert.is_not_nil(result.fg)
    -- Should be the original value, unadjusted
    assert.are.equal("#222222", result.fg)
  end)
end)

describe("notification bar highlights", function()
  local highlight
  local color

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.highlight"] = nil
    package.loaded["flemma.utilities.color"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.core"] = nil
    -- Truly clear notification groups so default = true can re-define them.
    -- nvim_set_hl(0, group, {}) leaves an empty definition that default = true
    -- treats as "already defined"; highlight clear actually removes the group.
    for _, group in ipairs({
      "FlemmaNotificationsBar",
      "FlemmaNotificationsSecondary",
      "FlemmaNotificationsMuted",
      "FlemmaNotificationsBottom",
      "FlemmaNotificationsCacheGood",
      "FlemmaNotificationsCacheBad",
    }) do
      vim.cmd("highlight clear " .. group)
    end
    -- Set up PmenuSel (the fallback in default notifications.highlight list)
    -- so the notification bar has a base group with both fg and bg
    vim.api.nvim_set_hl(0, "PmenuSel", { bg = 0x3c3836, fg = 0xd5c4a1 })
    vim.api.nvim_set_hl(0, "DiagnosticOk", { fg = 0x00ff00 })
    vim.api.nvim_set_hl(0, "DiagnosticWarn", { fg = 0xffff00 })
    -- Populate config with defaults so notifications.highlight is available
    require("flemma").setup({})
    highlight = require("flemma.highlight")
    color = require("flemma.utilities.color")
  end)

  after_each(function()
    for _, group in ipairs({
      "FlemmaNotificationsBar",
      "FlemmaNotificationsSecondary",
      "FlemmaNotificationsMuted",
      "FlemmaNotificationsBottom",
      "FlemmaNotificationsCacheGood",
      "FlemmaNotificationsCacheBad",
    }) do
      vim.api.nvim_set_hl(0, group, {})
    end
    vim.api.nvim_set_hl(0, "PmenuSel", {})
    vim.api.nvim_set_hl(0, "DiagnosticOk", {})
    vim.api.nvim_set_hl(0, "DiagnosticWarn", {})
  end)

  local function setup_and_apply()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = "chat"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@Assistant:", "test" })
    highlight.apply_syntax()
  end

  it("should define FlemmaNotificationsBar with PmenuSel bg", function()
    setup_and_apply()
    local hl = vim.api.nvim_get_hl(0, { name = "FlemmaNotificationsBar", link = false })
    assert.is_not_nil(hl.bg, "FlemmaNotificationsBar should have bg")
    -- Should match PmenuSel bg (0x3c3836)
    assert.are.equal(0x3c3836, hl.bg)
  end)

  it("should define FlemmaNotificationsBar with PmenuSel fg", function()
    setup_and_apply()
    local hl = vim.api.nvim_get_hl(0, { name = "FlemmaNotificationsBar", link = false })
    assert.is_not_nil(hl.fg, "FlemmaNotificationsBar should have fg")
    assert.are.equal(0xd5c4a1, hl.fg)
  end)

  it("should define FlemmaNotificationsSecondary with same bg as bar", function()
    setup_and_apply()
    local bar_hl = vim.api.nvim_get_hl(0, { name = "FlemmaNotificationsBar", link = false })
    local sec_hl = vim.api.nvim_get_hl(0, { name = "FlemmaNotificationsSecondary", link = false })
    assert.is_not_nil(sec_hl.bg)
    assert.are.equal(bar_hl.bg, sec_hl.bg)
  end)

  it("should define FlemmaNotificationsMuted with same bg as bar", function()
    setup_and_apply()
    local bar_hl = vim.api.nvim_get_hl(0, { name = "FlemmaNotificationsBar", link = false })
    local muted_hl = vim.api.nvim_get_hl(0, { name = "FlemmaNotificationsMuted", link = false })
    assert.is_not_nil(muted_hl.bg)
    assert.are.equal(bar_hl.bg, muted_hl.bg)
  end)

  it("should define FlemmaNotificationsBottom with underline", function()
    setup_and_apply()
    local hl = vim.api.nvim_get_hl(0, { name = "FlemmaNotificationsBottom", link = false })
    assert.is_true(hl.underline, "FlemmaNotificationsBottom should have underline")
    assert.is_not_nil(hl.sp, "FlemmaNotificationsBottom should have sp")
  end)

  it("should define FlemmaNotificationsCacheGood with sufficient contrast", function()
    setup_and_apply()
    local hl = vim.api.nvim_get_hl(0, { name = "FlemmaNotificationsCacheGood", link = false })
    assert.is_not_nil(hl.fg, "FlemmaNotificationsCacheGood should have fg")
    local fg_hex = string.format("#%06x", hl.fg)
    local bg_hex = string.format("#%06x", 0x3c3836)
    local ratio = color.contrast_ratio(fg_hex, bg_hex)
    assert.is_true(ratio >= 4.5, "cache good fg should have >= 4.5:1 contrast against bar bg: got " .. tostring(ratio))
  end)

  it("should define FlemmaNotificationsCacheBad with sufficient contrast", function()
    setup_and_apply()
    local hl = vim.api.nvim_get_hl(0, { name = "FlemmaNotificationsCacheBad", link = false })
    assert.is_not_nil(hl.fg, "FlemmaNotificationsCacheBad should have fg")
    local fg_hex = string.format("#%06x", hl.fg)
    local bg_hex = string.format("#%06x", 0x3c3836)
    local ratio = color.contrast_ratio(fg_hex, bg_hex)
    assert.is_true(ratio >= 4.5, "cache bad fg should have >= 4.5:1 contrast against bar bg: got " .. tostring(ratio))
  end)
end)

describe("CursorLine overlay highlights", function()
  local highlight

  -- Known highlight groups for predictable testing
  local NORMAL_BG = 0x1a1a2e
  local CURSORLINE_BG = 0x252540

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.highlight"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.utilities.color"] = nil

    -- Set predictable Normal and CursorLine
    vim.api.nvim_set_hl(0, "Normal", { bg = NORMAL_BG, fg = 0xeeeeee })
    vim.api.nvim_set_hl(0, "CursorLine", { bg = CURSORLINE_BG })

    -- Clear CursorLine variant groups so default = true can take effect
    for _, group in ipairs({
      "FlemmaLineFrontmatterCursorLine",
      "FlemmaLineSystemCursorLine",
      "FlemmaLineUserCursorLine",
      "FlemmaLineAssistantCursorLine",
      "FlemmaThinkingBlockCursorLine",
      "FlemmaThinkingFoldPreview",
    }) do
      vim.api.nvim_set_hl(0, group, {})
    end

    require("flemma").setup({})
    highlight = require("flemma.highlight")
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
    vim.api.nvim_set_hl(0, "Normal", {})
    vim.api.nvim_set_hl(0, "CursorLine", {})
    for _, group in ipairs({
      "FlemmaLineFrontmatterCursorLine",
      "FlemmaLineSystemCursorLine",
      "FlemmaLineUserCursorLine",
      "FlemmaLineAssistantCursorLine",
      "FlemmaThinkingBlockCursorLine",
      "FlemmaThinkingFoldPreview",
      "FlemmaLineAssistant",
      "FlemmaLineUser",
      "FlemmaLineSystem",
      "FlemmaLineFrontmatter",
      "FlemmaThinkingBlock",
    }) do
      vim.api.nvim_set_hl(0, group, {})
    end
  end)

  local function setup_and_apply()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = "chat"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@Assistant:", "test" })
    highlight.apply_syntax()
  end

  it("should create CursorLine variant for each line highlight group", function()
    setup_and_apply()
    for _, group in ipairs({
      "FlemmaLineFrontmatterCursorLine",
      "FlemmaLineSystemCursorLine",
      "FlemmaLineUserCursorLine",
      "FlemmaLineAssistantCursorLine",
      "FlemmaThinkingBlockCursorLine",
    }) do
      local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
      assert.is_not_nil(hl.bg, group .. " should have bg")
    end
  end)

  it("should apply CursorLine bg delta to role bg", function()
    setup_and_apply()

    -- CursorLine delta from Normal: (0x25-0x1a, 0x25-0x1a, 0x40-0x2e) = (11, 11, 18)
    -- FlemmaLineAssistant bg = Normal bg + #102020 = (0x1a+0x10, 0x1a+0x20, 0x2e+0x20) = (0x2a, 0x3a, 0x4e)
    -- Expected CursorLine variant = assistant bg + delta = (0x2a+11, 0x3a+11, 0x4e+18) = (0x35, 0x45, 0x60)
    local assistant_cl = vim.api.nvim_get_hl(0, { name = "FlemmaLineAssistantCursorLine", link = false })
    local assistant_base = vim.api.nvim_get_hl(0, { name = "FlemmaLineAssistant", link = false })

    -- The CursorLine variant bg should differ from the base by the CursorLine delta
    assert.are_not.equal(assistant_base.bg, assistant_cl.bg, "CursorLine variant should differ from base")

    -- Verify the delta is consistent: both should shift by the same amount as CursorLine shifts from Normal
    local normal_bg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
    local cl_bg = vim.api.nvim_get_hl(0, { name = "CursorLine", link = false }).bg

    -- Extract red channel from each to verify the delta math
    local normal_r = math.floor(normal_bg / 0x10000) % 256
    local cl_r = math.floor(cl_bg / 0x10000) % 256
    local expected_delta_r = cl_r - normal_r

    local base_r = math.floor(assistant_base.bg / 0x10000) % 256
    local variant_r = math.floor(assistant_cl.bg / 0x10000) % 256
    local actual_delta_r = variant_r - base_r

    assert.are.equal(expected_delta_r, actual_delta_r, "red channel delta should match CursorLine-Normal delta")
  end)

  it("should carry CursorLine decoration attributes to variants", function()
    -- Set CursorLine with underline
    vim.api.nvim_set_hl(0, "CursorLine", { bg = CURSORLINE_BG, underline = true })
    -- Clear variants so they get recreated
    for _, group in ipairs({
      "FlemmaLineAssistantCursorLine",
      "FlemmaLineUserCursorLine",
    }) do
      vim.api.nvim_set_hl(0, group, {})
    end

    setup_and_apply()

    local hl = vim.api.nvim_get_hl(0, { name = "FlemmaLineAssistantCursorLine", link = false })
    assert.is_true(hl.underline, "CursorLine variant should inherit underline from CursorLine")
  end)

  it("should not create variants when CursorLine is empty", function()
    vim.api.nvim_set_hl(0, "CursorLine", {})
    -- Clear variants
    for _, group in ipairs({
      "FlemmaLineAssistantCursorLine",
    }) do
      vim.api.nvim_set_hl(0, group, {})
    end

    setup_and_apply()

    local hl = vim.api.nvim_get_hl(0, { name = "FlemmaLineAssistantCursorLine", link = false })
    assert.is_nil(hl.bg, "should not create variant when CursorLine has no attributes")
  end)

  describe("FlemmaThinkingFoldPreview", function()
    it("should have fg but no bg", function()
      setup_and_apply()
      local hl = vim.api.nvim_get_hl(0, { name = "FlemmaThinkingFoldPreview", link = false })
      assert.is_not_nil(hl.fg, "FlemmaThinkingFoldPreview should have fg")
      assert.is_nil(hl.bg, "FlemmaThinkingFoldPreview should NOT have bg (let line_hl_group provide it)")
    end)

    it("should derive fg from FlemmaThinkingBlock", function()
      setup_and_apply()
      local thinking_hl = vim.api.nvim_get_hl(0, { name = "FlemmaThinkingBlock", link = false })
      local fold_hl = vim.api.nvim_get_hl(0, { name = "FlemmaThinkingFoldPreview", link = false })

      if thinking_hl.fg then
        assert.are.equal(thinking_hl.fg, fold_hl.fg, "FlemmaThinkingFoldPreview fg should match FlemmaThinkingBlock fg")
      else
        -- Falls back to Comment fg
        local comment_hl = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
        assert.are.equal(comment_hl.fg, fold_hl.fg, "FlemmaThinkingFoldPreview fg should fall back to Comment fg")
      end
    end)
  end)
end)
