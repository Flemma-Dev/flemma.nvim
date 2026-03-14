describe("preprocessor.syntax", function()
  local syntax
  local preprocessor

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.preprocessor"] = nil
    package.loaded["flemma.preprocessor.syntax"] = nil
    package.loaded["flemma.preprocessor.registry"] = nil
    package.loaded["flemma.preprocessor.context"] = nil
    package.loaded["flemma.preprocessor.runner"] = nil
    package.loaded["flemma.preprocessor.rewriters.file_references"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.config"] = nil

    require("flemma").setup({})
    syntax = require("flemma.preprocessor.syntax")
    preprocessor = require("flemma.preprocessor")
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
    -- Clear any test highlight groups
    for _, group in ipairs({ "TestSyntaxMatch", "TestSyntaxRegion", "TestSyntaxRaw" }) do
      vim.cmd("highlight clear " .. group)
    end
  end)

  describe("resolve_containedin", function()
    it("should map '*' to all content regions", function()
      local result = syntax.resolve_containedin("*")
      assert.are.equal("FlemmaUser,FlemmaSystem,FlemmaAssistant", result)
    end)

    it("should default to '*' when nil", function()
      local result = syntax.resolve_containedin(nil)
      assert.are.equal("FlemmaUser,FlemmaSystem,FlemmaAssistant", result)
    end)

    it("should map a table of role names", function()
      local result = syntax.resolve_containedin({ "user", "system" })
      assert.are.equal("FlemmaUser,FlemmaSystem", result)
    end)

    it("should map a single role name string", function()
      local result = syntax.resolve_containedin("user")
      assert.are.equal("FlemmaUser", result)
    end)
  end)

  describe("generate_command", function()
    it("should generate a match command with default containedin", function()
      local cmd = syntax.generate_command({
        kind = "match",
        group = "TestSyntaxMatch",
        pattern = [[test pattern]],
        hl = "Include",
      })
      assert.are.equal(
        'syntax match TestSyntaxMatch "test pattern" contained containedin=FlemmaUser,FlemmaSystem,FlemmaAssistant',
        cmd
      )
    end)

    it("should generate a match command with specific containedin", function()
      local cmd = syntax.generate_command({
        kind = "match",
        group = "TestSyntaxMatch",
        pattern = [=[@\v(\.\.?\/)\S*[^[:punct:]\s]]=],
        containedin = { "user", "system" },
        hl = "Include",
      })
      assert.are.equal(
        [=[syntax match TestSyntaxMatch "@\v(\.\.?\/)\S*[^[:punct:]\s]" contained containedin=FlemmaUser,FlemmaSystem]=],
        cmd
      )
    end)

    it("should generate a match command with options", function()
      local cmd = syntax.generate_command({
        kind = "match",
        group = "TestSyntaxMatch",
        pattern = "test",
        containedin = "user",
        options = "display",
        hl = "Include",
      })
      assert.are.equal(
        'syntax match TestSyntaxMatch "test" display contained containedin=FlemmaUser',
        cmd
      )
    end)

    it("should generate a region command", function()
      local cmd = syntax.generate_command({
        kind = "region",
        group = "TestSyntaxRegion",
        start = "START",
        end_ = "END",
        containedin = { "assistant" },
        hl = "Include",
      })
      assert.are.equal(
        'syntax region TestSyntaxRegion start="START" end="END" contained containedin=FlemmaAssistant',
        cmd
      )
    end)

    it("should generate a region command with options and contains", function()
      local cmd = syntax.generate_command({
        kind = "region",
        group = "TestSyntaxRegion",
        start = "START",
        end_ = "END",
        containedin = "*",
        contains = "TestNested",
        options = "oneline keepend",
        hl = "Include",
      })
      assert.are.equal(
        'syntax region TestSyntaxRegion start="START" end="END" oneline keepend contains=TestNested contained containedin=FlemmaUser,FlemmaSystem,FlemmaAssistant',
        cmd
      )
    end)

    it("should return raw string when raw field is set", function()
      local cmd = syntax.generate_command({
        kind = "match",
        group = "TestSyntaxRaw",
        raw = 'syntax match TestSyntaxRaw /custom"pattern/ containedin=FlemmaUser',
        hl = "Include",
      })
      assert.are.equal('syntax match TestSyntaxRaw /custom"pattern/ containedin=FlemmaUser', cmd)
    end)
  end)

  describe("apply", function()
    it("should skip rewriters without get_vim_syntax", function()
      -- Unregister all built-in rewriters so only our test rewriter is present
      preprocessor.unregister("file-references")

      local rewriter = preprocessor.create_rewriter("no-syntax")
      preprocessor.register(rewriter)

      local config = require("flemma.state").get_config()
      local set_highlight_called = false
      syntax.apply(config, function()
        set_highlight_called = true
      end)
      assert.is_false(set_highlight_called)

      preprocessor.unregister("no-syntax")
    end)

    it("should call set_highlight for each rule", function()
      -- Unregister built-ins so we control exactly what's registered
      preprocessor.unregister("file-references")

      local rewriter = preprocessor.create_rewriter("test-syntax")
      rewriter.get_vim_syntax = function(_)
        return {
          { kind = "match", group = "TestSyntaxMatch", pattern = "test", hl = "Include" },
        }
      end
      preprocessor.register(rewriter)

      -- Set up a buffer with chat syntax so vim.cmd syntax commands work
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.cmd("runtime! syntax/chat.vim")

      local highlight_calls = {}
      syntax.apply(require("flemma.state").get_config(), function(group, value)
        table.insert(highlight_calls, { group = group, value = value })
      end)

      assert.are.equal(1, #highlight_calls)
      assert.are.equal("TestSyntaxMatch", highlight_calls[1].group)
      assert.are.equal("Include", highlight_calls[1].value)

      preprocessor.unregister("test-syntax")
    end)
  end)
end)
