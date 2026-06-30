package.loaded["flemma.ui.highlighter"] = nil

local highlighter = require("flemma.ui.highlighter")

---Check whether the bash treesitter grammar is available in this environment.
---@return boolean
local function has_bash_grammar()
  local ok = pcall(vim.treesitter.get_string_parser, "echo", "bash")
  return ok
end

describe("flemma.ui.highlighter", function()
  before_each(function()
    package.loaded["flemma.ui.highlighter"] = nil
    highlighter = require("flemma.ui.highlighter")
  end)

  describe("highlight()", function()
    it("calls back with nil for unknown language", function()
      local result = "not_called"
      highlighter.highlight("x", "nonexistent_lang_xyz", function(lines_chunks)
        result = lines_chunks
      end)
      vim.wait(1000, function()
        return result ~= "not_called"
      end)
      assert.is_nil(result)
    end)

    if has_bash_grammar() then
      it("returns chunks with syntax highlights for bash", function()
        local result
        highlighter.highlight("echo hello", "bash", function(lines_chunks)
          result = lines_chunks
        end)
        vim.wait(1000, function()
          return result ~= nil
        end)
        assert.is_not_nil(result, "callback was never called")
        assert.equals(1, #result, "expected 1 line")
        assert.is_true(#result[1] >= 1, "expected at least 1 chunk")
        for _, chunk in ipairs(result[1]) do
          assert.equals("string", type(chunk[1]), "chunk text must be a string")
          assert.equals("string", type(chunk[2]), "chunk hl_group must be a string")
        end
        local reassembled = ""
        for _, chunk in ipairs(result[1]) do
          reassembled = reassembled .. chunk[1]
        end
        assert.equals("echo hello", reassembled)
      end)

      it("returns highlighted chunks for multi-line input", function()
        local result
        highlighter.highlight("echo a\necho b", "bash", function(lines_chunks)
          result = lines_chunks
        end)
        vim.wait(1000, function()
          return result ~= nil
        end)
        assert.is_not_nil(result)
        assert.equals(2, #result, "expected 2 lines")
        for i, expected in ipairs({ "echo a", "echo b" }) do
          local reassembled = ""
          for _, chunk in ipairs(result[i]) do
            reassembled = reassembled .. chunk[1]
          end
          assert.equals(expected, reassembled)
        end
      end)

      it("calls back synchronously on cache hit", function()
        local primed
        highlighter.highlight("echo cached", "bash", function(lines_chunks)
          primed = lines_chunks
        end)
        vim.wait(1000, function()
          return primed ~= nil
        end)
        assert.is_not_nil(primed)

        local sync_called = false
        highlighter.highlight("echo cached", "bash", function(lines_chunks)
          sync_called = true
          assert.is_not_nil(lines_chunks)
          local reassembled = ""
          for _, chunk in ipairs(lines_chunks[1]) do
            reassembled = reassembled .. chunk[1]
          end
          assert.equals("echo cached", reassembled)
        end)
        assert.is_true(sync_called, "expected synchronous callback on cache hit")
      end)

      it("returns chunk array for empty string", function()
        local result
        highlighter.highlight("", "bash", function(lines_chunks)
          result = lines_chunks
        end)
        vim.wait(1000, function()
          return result ~= nil
        end)
        if result then
          assert.equals("table", type(result))
        end
      end)
    end
  end)
end)
