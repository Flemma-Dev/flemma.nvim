describe("utilities.variables", function()
  local variables

  before_each(function()
    package.loaded["flemma.utilities.variables"] = nil
    variables = require("flemma.utilities.variables")
  end)

  describe("expand", function()
    it("returns literal paths unchanged", function()
      assert.are.equal("/tmp", variables.expand("/tmp"))
    end)

    it("expands URN variables using registered resolvers", function()
      variables.register("urn:flemma:cwd", function()
        return "/home/user/project"
      end)
      assert.are.equal("/home/user/project", variables.expand("urn:flemma:cwd"))
    end)

    it("returns nil when URN resolver returns nil", function()
      variables.register("urn:flemma:buffer:path", function()
        return nil
      end)
      assert.is_nil(variables.expand("urn:flemma:buffer:path"))
    end)

    it("expands $VAR from environment", function()
      -- HOME is always set
      local home = os.getenv("HOME")
      assert.are.equal(home, variables.expand("$HOME"))
    end)

    it("returns nil for unset $VAR without default", function()
      assert.is_nil(variables.expand("$FLEMMA_TEST_NONEXISTENT_VAR_12345"))
    end)

    it("expands ${VAR:-default} using env value when set", function()
      local home = os.getenv("HOME")
      assert.are.equal(home, variables.expand("${HOME:-/fallback}"))
    end)

    it("expands ${VAR:-default} using default when unset", function()
      assert.are.equal("/fallback/path", variables.expand("${FLEMMA_TEST_NONEXISTENT_VAR_12345:-/fallback/path}"))
    end)

    it("expands ~ in default values", function()
      local home = os.getenv("HOME")
      assert.are.equal(home .. "/.cache", variables.expand("${FLEMMA_TEST_NONEXISTENT_VAR_12345:-~/.cache}"))
    end)

    it("expands ~ at start of literal paths", function()
      local home = os.getenv("HOME")
      assert.are.equal(home .. "/.config", variables.expand("~/.config"))
    end)

    it("does not expand ~ in the middle of a path", function()
      assert.are.equal("/home/~/weird", variables.expand("/home/~/weird"))
    end)

    it("errors on unregistered URN", function()
      assert.has_error(function()
        variables.expand("urn:flemma:nonexistent")
      end)
    end)

    it("passes context to URN resolvers", function()
      variables.register("urn:flemma:test", function(ctx)
        return ctx.some_value
      end)
      assert.are.equal("hello", variables.expand("urn:flemma:test", { some_value = "hello" }))
    end)
  end)

  describe("expand_list", function()
    it("expands all entries and drops nils", function()
      variables.register("urn:flemma:cwd", function()
        return "/project"
      end)
      variables.register("urn:flemma:buffer:path", function()
        return nil -- unnamed buffer
      end)
      local result = variables.expand_list({
        "urn:flemma:cwd",
        "urn:flemma:buffer:path",
        "/tmp",
      })
      assert.are.same({ "/project", "/tmp" }, result)
    end)
  end)

  describe("expand_inline", function()
    it("expands ${VAR:-default} within a larger string", function()
      local original = os.getenv("FLEMMA_TEST_UNSET_VAR_1")
      assert.is_nil(original)
      local result = variables.expand_inline("${FLEMMA_TEST_UNSET_VAR_1:-/fallback}/sub/path")
      assert.equals("/fallback/sub/path", result)
    end)

    it("expands ${VAR:-default} using env value when set", function()
      vim.env.FLEMMA_TEST_INLINE_1 = "/custom"
      local result = variables.expand_inline("${FLEMMA_TEST_INLINE_1:-/fallback}/sub/path")
      vim.env.FLEMMA_TEST_INLINE_1 = nil
      assert.equals("/custom/sub/path", result)
    end)

    it("expands bare $VAR inline", function()
      vim.env.FLEMMA_TEST_INLINE_2 = "resolved"
      local result = variables.expand_inline("prefix/$FLEMMA_TEST_INLINE_2/suffix")
      vim.env.FLEMMA_TEST_INLINE_2 = nil
      assert.equals("prefix/resolved/suffix", result)
    end)

    it("expands tilde in defaults", function()
      local home = os.getenv("HOME") or ""
      local result = variables.expand_inline("${FLEMMA_TEST_UNSET_VAR_2:-~/.local/share}/flemma")
      assert.equals(home .. "/.local/share/flemma", result)
    end)

    it("leaves {{...}} template expressions untouched", function()
      local result = variables.expand_inline("${FLEMMA_TEST_UNSET_VAR_3:-/tmp}/flemma_{{ source }}_{{ id }}.txt")
      assert.equals("/tmp/flemma_{{ source }}_{{ id }}.txt", result)
    end)

    it("handles multiple expansions in one string", function()
      vim.env.FLEMMA_TEST_INLINE_A = "aaa"
      vim.env.FLEMMA_TEST_INLINE_B = "bbb"
      local result = variables.expand_inline("$FLEMMA_TEST_INLINE_A/${FLEMMA_TEST_INLINE_B:-fallback}")
      vim.env.FLEMMA_TEST_INLINE_A = nil
      vim.env.FLEMMA_TEST_INLINE_B = nil
      assert.equals("aaa/bbb", result)
    end)

    it("returns string unchanged when no patterns match", function()
      local result = variables.expand_inline("/plain/path/no/vars")
      assert.equals("/plain/path/no/vars", result)
    end)

    it("replaces bare $VAR with empty string when unset", function()
      local result = variables.expand_inline("prefix/$FLEMMA_TEST_UNSET_VAR_4/suffix")
      assert.equals("prefix//suffix", result)
    end)

    it("expands leading tilde", function()
      local home = os.getenv("HOME") or ""
      local result = variables.expand_inline("~/documents/file.txt")
      assert.equals(home .. "/documents/file.txt", result)
    end)
  end)

  describe("deduplicate_by_prefix", function()
    it("removes paths subsumed by a parent", function()
      local result = variables.deduplicate_by_prefix({
        "/tmp",
        "/tmp/foo/bar",
        "/home/user",
        "/home/user/project",
      })
      assert.are.same({ "/home/user", "/tmp" }, result)
    end)

    it("keeps distinct paths", function()
      local result = variables.deduplicate_by_prefix({
        "/tmp",
        "/home/user",
        "/data/project",
      })
      assert.are.same({ "/data/project", "/home/user", "/tmp" }, result)
    end)

    it("handles single path", function()
      local result = variables.deduplicate_by_prefix({ "/tmp" })
      assert.are.same({ "/tmp" }, result)
    end)

    it("handles empty list", function()
      local result = variables.deduplicate_by_prefix({})
      assert.are.same({}, result)
    end)

    it("does not treat /tmp as parent of /tmpfs", function()
      local result = variables.deduplicate_by_prefix({ "/tmp", "/tmpfs" })
      assert.are.same({ "/tmp", "/tmpfs" }, result)
    end)
  end)
end)
