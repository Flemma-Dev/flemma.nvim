local migration -- loaded in before_each
local notify = require("flemma.notify")

describe("migration", function()
  before_each(function()
    package.loaded["flemma.migration"] = nil
    migration = require("flemma.migration")
  end)

  describe("needs_migration", function()
    it("returns true for old format with colon-space", function()
      local lines = { "@You: Hello world" }
      assert.is_true(migration.needs_migration(lines))
    end)

    it("returns true for old format with content directly after colon", function()
      local lines = { "@Assistant:Hello" }
      assert.is_true(migration.needs_migration(lines))
    end)

    it("returns false for new format", function()
      local lines = { "@You:", "Hello world" }
      assert.is_false(migration.needs_migration(lines))
    end)

    it("returns false for role marker with only whitespace after colon", function()
      local lines = { "@You:  ", "Hello world" }
      assert.is_false(migration.needs_migration(lines))
    end)

    it("returns false for empty buffer", function()
      assert.is_false(migration.needs_migration({}))
    end)

    it("returns false for non-chat content", function()
      local lines = { "Hello @You: not a marker" }
      assert.is_false(migration.needs_migration(lines))
    end)

    it("detects all three role types", function()
      assert.is_true(migration.needs_migration({ "@System: prompt" }))
      assert.is_true(migration.needs_migration({ "@You: question" }))
      assert.is_true(migration.needs_migration({ "@Assistant: answer" }))
    end)

    it("ignores unknown roles", function()
      assert.is_false(migration.needs_migration({ "@Foo: bar" }))
    end)
  end)

  describe("migrate_lines", function()
    it("splits role marker with colon-space onto its own line", function()
      local result = migration.migrate_lines({ "@You: Hello world" })
      assert.same({ "@You:", "Hello world" }, result)
    end)

    it("splits role marker with content directly after colon", function()
      local result = migration.migrate_lines({ "@Assistant:Hello" })
      assert.same({ "@Assistant:", "Hello" }, result)
    end)

    it("preserves content whitespace exactly", function()
      local result = migration.migrate_lines({ "@You:   hello  world  " })
      assert.same({ "@You:", "  hello  world  " }, result)
    end)

    it("preserves multi-line content after role marker", function()
      local result = migration.migrate_lines({
        "@You: Hello",
        "second line",
        "",
        "@Assistant: World",
      })
      assert.same({
        "@You:",
        "Hello",
        "second line",
        "",
        "@Assistant:",
        "World",
      }, result)
    end)

    it("is a no-op for already-migrated content", function()
      local lines = { "@You:", "Hello", "", "@Assistant:", "World" }
      assert.same(lines, migration.migrate_lines(lines))
    end)

    it("handles mixed old and new format", function()
      local result = migration.migrate_lines({
        "@You:", -- already new format
        "Hello",
        "",
        "@Assistant: World", -- old format
      })
      assert.same({
        "@You:",
        "Hello",
        "",
        "@Assistant:",
        "World",
      }, result)
    end)

    it("does not split tool use headers", function()
      local lines = {
        "@Assistant:",
        "**Tool Use:** `calc` (`id123`)",
      }
      assert.same(lines, migration.migrate_lines(lines))
    end)

    it("does not split tool result headers", function()
      local lines = {
        "@You:",
        "**Tool Result:** `id123`",
      }
      assert.same(lines, migration.migrate_lines(lines))
    end)

    it("handles frontmatter before first role marker", function()
      local result = migration.migrate_lines({
        "```lua",
        'flemma.opt.model = "claude"',
        "```",
        "@System: You are helpful.",
      })
      assert.same({
        "```lua",
        'flemma.opt.model = "claude"',
        "```",
        "@System:",
        "You are helpful.",
      }, result)
    end)

    it("preserves empty role marker (user hasn't typed content yet)", function()
      local lines = { "@You:", "" }
      assert.same(lines, migration.migrate_lines(lines))
    end)
  end)

  describe("migrate_buffer", function()
    it("replaces buffer content with migrated lines", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You: Hello",
        "",
        "@Assistant: World",
      })
      migration.migrate_buffer(bufnr)
      local result = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.same({
        "@You:",
        "Hello",
        "",
        "@Assistant:",
        "World",
      }, result)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("is a no-op for already-migrated content", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local lines = { "@You:", "Hello" }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      migration.migrate_buffer(bufnr)
      assert.same(lines, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("tool name colon-to-dot migration", function()
    it("detects colon-separated tool names in Tool Use headers", function()
      local lines = {
        "@Assistant:",
        "",
        "**Tool Use:** `slack:channels_list` (`toolu_01`)",
        "```json",
        '{ "channel": "general" }',
        "```",
      }
      assert.is_true(migration.needs_migration(lines))
    end)

    it("migrates Tool Use headers from colon to dot separator", function()
      local lines = {
        "@Assistant:",
        "",
        "**Tool Use:** `slack:channels_list` (`toolu_01`)",
        "```json",
        '{ "channel": "general" }',
        "```",
      }
      local result = migration.migrate_lines(lines)
      assert.equals("**Tool Use:** `slack.channels_list` (`toolu_01`)", result[3])
    end)

    it("migrates multi-segment colon names", function()
      local lines = {
        "@Assistant:",
        "",
        "**Tool Use:** `flemma:jobs:status` (`toolu_02`)",
        "```json",
        '{ "job_id": "j1" }',
        "```",
      }
      local result = migration.migrate_lines(lines)
      assert.equals("**Tool Use:** `flemma.jobs.status` (`toolu_02`)", result[3])
    end)

    it("does not modify tool names without colons", function()
      local lines = {
        "@Assistant:",
        "",
        "**Tool Use:** `bash` (`toolu_03`)",
        "```json",
        '{ "command": "ls" }',
        "```",
      }
      local result = migration.migrate_lines(lines)
      assert.equals("**Tool Use:** `bash` (`toolu_03`)", result[3])
    end)

    it("does not flag dot-separated names as needing migration", function()
      local lines = {
        "@Assistant:",
        "",
        "**Tool Use:** `slack.channels_list` (`toolu_01`)",
        "```json",
        "{}",
        "```",
      }
      assert.is_false(migration.needs_migration(lines))
    end)

    it("handles mixed old and new format in same buffer", function()
      local lines = {
        "@Assistant:",
        "",
        "**Tool Use:** `slack:send_message` (`toolu_01`)",
        "```json",
        "{}",
        "```",
        "",
        "**Tool Use:** `bash` (`toolu_02`)",
        "```json",
        "{}",
        "```",
      }
      local result = migration.migrate_lines(lines)
      assert.equals("**Tool Use:** `slack.send_message` (`toolu_01`)", result[3])
      assert.equals("**Tool Use:** `bash` (`toolu_02`)", result[8])
    end)

    it("returns tool_names_migrated=true when Tool Use headers were rewritten", function()
      local lines = {
        "@Assistant:",
        "",
        "**Tool Use:** `slack:send` (`toolu_01`)",
        "```json",
        "{}",
        "```",
      }
      local _, info = migration.migrate_lines(lines)
      assert.is_true(info.tool_names_migrated)
    end)

    it("returns tool_names_migrated=false when no Tool Use headers had colons", function()
      local lines = {
        "@Assistant:",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        "{}",
        "```",
      }
      local _, info = migration.migrate_lines(lines)
      assert.is_false(info.tool_names_migrated)
    end)
  end)

  describe("frontmatter tool name migration", function()
    it("migrates colon tool names on flemma.opt.tools lines", function()
      local warnings = {}
      notify._set_impl(function(notification)
        if notification.level == vim.log.levels.WARN then
          table.insert(warnings, notification.message)
        end
      end)

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "```lua",
        'flemma.opt.tools:append({ "slack:channels_list", "github:issue_read" })',
        "```",
        "@You:",
        "test",
        "",
        "@Assistant:",
        "",
        "**Tool Use:** `slack:channels_list` (`toolu_01`)",
        "```json",
        "{}",
        "```",
      })

      migration.migrate_buffer(bufnr)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      -- Tool Use header migrated
      assert.equals("**Tool Use:** `slack.channels_list` (`toolu_01`)", lines[9])
      -- Frontmatter also migrated
      assert.equals('flemma.opt.tools:append({ "slack.channels_list", "github.issue_read" })', lines[2])

      -- Review warning fires
      vim.wait(200, function()
        return #warnings > 0
      end)
      assert.equals(1, #warnings)
      assert.truthy(warnings[1]:match("frontmatter"))

      vim.api.nvim_buf_delete(bufnr, { force = true })
      notify._reset_impl()
    end)

    it("does not touch frontmatter lines without flemma.opt.tools", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "```lua",
        'local x = "key:value"',
        'flemma.opt.model = "anthropic"',
        "```",
        "@Assistant:",
        "",
        "**Tool Use:** `slack:send` (`toolu_01`)",
        "```json",
        "{}",
        "```",
      })

      migration.migrate_buffer(bufnr)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals('local x = "key:value"', lines[2])
      assert.equals('flemma.opt.model = "anthropic"', lines[3])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("does not warn when no frontmatter colon tool names", function()
      local warnings = {}
      notify._set_impl(function(notification)
        if notification.level == vim.log.levels.WARN then
          table.insert(warnings, notification.message)
        end
      end)

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "",
        "**Tool Use:** `slack:channels_list` (`toolu_01`)",
        "```json",
        "{}",
        "```",
      })

      migration.migrate_buffer(bufnr)

      vim.wait(200, function()
        return #warnings > 0
      end)
      assert.equals(0, #warnings)

      vim.api.nvim_buf_delete(bufnr, { force = true })
      notify._reset_impl()
    end)

    it("migrates glob patterns in frontmatter", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "```lua",
        'flemma.opt.tools.auto_approve = { "slack:*", "read" }',
        "```",
        "@Assistant:",
        "",
        "**Tool Use:** `slack:send` (`toolu_01`)",
        "```json",
        "{}",
        "```",
      })

      migration.migrate_buffer(bufnr)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals('flemma.opt.tools.auto_approve = { "slack.*", "read" }', lines[2])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
