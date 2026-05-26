--- Tests for flemma.utilities.glob

package.loaded["flemma.utilities.glob"] = nil

local glob = require("flemma.utilities.glob")

describe("flemma.utilities.glob", function()
  describe("is_glob", function()
    it("returns true when string contains *", function()
      assert.is_true(glob.is_glob("github.*"))
    end)

    it("returns false for plain strings", function()
      assert.is_false(glob.is_glob("github.create_issue"))
    end)

    it("returns false for empty string", function()
      assert.is_false(glob.is_glob(""))
    end)
  end)

  describe("match", function()
    it("matches a trailing wildcard", function()
      assert.is_true(glob.match("github.create_issue", "github.*"))
    end)

    it("rejects a non-matching name", function()
      assert.is_false(glob.match("slack.post_message", "github.*"))
    end)

    it("matches an exact name without wildcards", function()
      assert.is_true(glob.match("read", "read"))
    end)

    it("rejects a partial exact mismatch", function()
      assert.is_false(glob.match("readonly", "read"))
    end)

    it("matches a leading wildcard", function()
      assert.is_true(glob.match("github.create_issue", "*.create_issue"))
    end)

    it("matches a middle wildcard", function()
      assert.is_true(glob.match("github.v2.create_issue", "github.*.create_issue"))
    end)

    it("matches a bare wildcard against anything", function()
      assert.is_true(glob.match("anything", "*"))
    end)

    it("escapes lua pattern metacharacters in the glob", function()
      assert.is_true(glob.match("my-tool.v1+beta", "my-tool.v1+beta"))
      assert.is_false(glob.match("my-toolXv1Xbeta", "my-tool.v1+beta"))
    end)
  end)

  describe("matches_any", function()
    it("returns true when any pattern matches", function()
      assert.is_true(glob.matches_any("github.create_issue", { "slack.*", "github.*" }))
    end)

    it("returns false when no pattern matches", function()
      assert.is_false(glob.matches_any("trello.create_card", { "slack.*", "github.*" }))
    end)

    it("handles a mix of exact names and globs", function()
      assert.is_true(glob.matches_any("read", { "read", "github.*" }))
      assert.is_true(glob.matches_any("github.list_repos", { "read", "github.*" }))
      assert.is_false(glob.matches_any("write", { "read", "github.*" }))
    end)

    it("returns false for an empty pattern list", function()
      assert.is_false(glob.matches_any("anything", {}))
    end)
  end)
end)
