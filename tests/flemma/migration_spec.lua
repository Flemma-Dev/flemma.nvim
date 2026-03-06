local migration -- loaded in before_each

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
        '**Tool Use:** `calc` (`id123`)',
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
end)
