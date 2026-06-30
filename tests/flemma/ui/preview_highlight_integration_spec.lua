package.loaded["flemma.ui.preview"] = nil
package.loaded["flemma.ui.highlighter"] = nil
package.loaded["flemma.tools"] = nil
package.loaded["flemma.tools.registry"] = nil

local preview = require("flemma.ui.preview")
local highlighter = require("flemma.ui.highlighter")

---Check whether the bash treesitter grammar is available in this environment.
---@return boolean
local function has_bash_grammar()
  local ok = pcall(vim.treesitter.get_string_parser, "echo", "bash")
  return ok
end

describe("preview + highlighter integration", function()
  before_each(function()
    package.loaded["flemma.ui.preview"] = nil
    package.loaded["flemma.ui.highlighter"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.tools.registry"] = nil
    preview = require("flemma.ui.preview")
    highlighter = require("flemma.ui.highlighter")
    highlighter._clear_cache()
  end)

  describe("format_tool_preview_multiline with highlight_context", function()
    it("returns highlight_context for bash tool", function()
      local registry = require("flemma.tools.registry")
      registry.register("test_bash", {
        name = "test_bash",
        description = "Test bash",
        input_schema = { type = "object", properties = {} },
        format_preview = function(input)
          return {
            label = input.label,
            detail = "$ " .. (input.command or ""),
            highlight = { lang = "bash" },
          }
        end,
      })

      local lines, _, ctx =
        preview.format_tool_preview_multiline("test_bash", { command = "echo hello", label = "greeting" }, 80)

      assert.is_not_nil(ctx, "expected highlight_context")
      assert.equals("bash", ctx.lang)
      assert.equals("$ echo hello", ctx.text)
      assert.equals("test_bash: ", ctx.name_prefix)
      assert.equals(string.rep(" ", #"test_bash: "), ctx.indent)

      assert.is_not_nil(lines)
      assert.is_true(#lines >= 1)
    end)

    it("returns nil context for tool without highlight", function()
      local registry = require("flemma.tools.registry")
      registry.register("test_edit", {
        name = "test_edit",
        description = "Test edit",
        input_schema = { type = "object", properties = {} },
        format_preview = function(input)
          return { detail = input.path }
        end,
      })

      local _, _, ctx = preview.format_tool_preview_multiline("test_edit", { path = "src/main.lua" }, 80)

      assert.is_nil(ctx, "expected nil context for tool without highlight")
    end)
  end)

  if has_bash_grammar() then
    describe("highlighted chunks preserve text content", function()
      it("reassembled highlighted text matches raw detail lines", function()
        local text = "echo $HOME\nls -la"
        local result
        highlighter.highlight(text, "bash", function(lines_chunks)
          result = lines_chunks
        end)
        vim.wait(1000, function()
          return result ~= nil
        end)

        if result then
          local expected_lines = { "echo $HOME", "ls -la" }
          for i, expected in ipairs(expected_lines) do
            local reassembled = ""
            for _, chunk in ipairs(result[i]) do
              reassembled = reassembled .. chunk[1]
            end
            assert.equals(expected, reassembled)
          end
        end
      end)
    end)

    describe("truncate_chunks + highlighted content", function()
      it("truncated highlighted chunks reassemble to within max_width", function()
        local text = "echo a_very_long_variable_name_that_exceeds_the_width"
        local result
        highlighter.highlight(text, "bash", function(lines_chunks)
          result = lines_chunks
        end)
        vim.wait(1000, function()
          return result ~= nil
        end)

        if result and result[1] then
          local truncated = preview.truncate_chunks(result[1], 20)
          local width = 0
          for _, chunk in ipairs(truncated) do
            width = width + vim.api.nvim_strwidth(chunk[1])
          end
          assert.is_true(width <= 20, "truncated width " .. width .. " exceeds 20")
        end
      end)
    end)
  end
end)
