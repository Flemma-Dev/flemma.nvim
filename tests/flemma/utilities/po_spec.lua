package.loaded["flemma.utilities.po"] = nil

local po = require("flemma.utilities.po")

describe("flemma.utilities.po", function()
  before_each(function()
    package.loaded["flemma.utilities.po"] = nil
    po = require("flemma.utilities.po")
  end)

  describe("parse", function()
    it("parses a simple msgid/msgstr pair", function()
      local entries = po.parse('msgid "tool.denied"\nmsgstr "The tool was denied by a policy."\n')
      assert.are.same({ ["tool.denied"] = "The tool was denied by a policy." }, entries)
    end)

    it("parses multiple entries separated by blank lines", function()
      local entries = po.parse(table.concat({
        'msgid "a.one"',
        'msgstr "first"',
        "",
        'msgid "a.two"',
        'msgstr "second"',
      }, "\n"))
      assert.are.same({ ["a.one"] = "first", ["a.two"] = "second" }, entries)
    end)

    it("concatenates continuation strings exactly, without implicit whitespace", function()
      local entries = po.parse(table.concat({
        'msgid "key"',
        'msgstr ""',
        '"Hello "',
        '"world"',
        '", exactly"',
      }, "\n"))
      assert.are.equal("Hello world, exactly", entries["key"])
    end)

    it("supports continuation strings on msgid too", function()
      local entries = po.parse(table.concat({
        'msgid "tool.bash"',
        '".description"',
        'msgstr "text"',
      }, "\n"))
      assert.are.equal("text", entries["tool.bash.description"])
    end)

    it("decodes the supported escape sequences", function()
      local entries = po.parse('msgid "k"\nmsgstr "line1\\nline2\\ttabbed \\"quoted\\" back\\\\slash"\n')
      assert.are.equal('line1\nline2\ttabbed "quoted" back\\slash', entries["k"])
    end)

    it("rejects unsupported escape sequences", function()
      assert.has_error(function()
        po.parse('msgid "k"\nmsgstr "bad \\r escape"\n')
      end)
    end)

    it("rejects unescaped quotes inside strings", function()
      assert.has_error(function()
        po.parse('msgid "k"\nmsgstr "has " embedded"\n')
      end)
    end)

    it("skips the header entry (first empty msgid)", function()
      local entries = po.parse(table.concat({
        'msgid ""',
        'msgstr ""',
        '"Content-Type: text/plain; charset=UTF-8\\n"',
        "",
        'msgid "real.key"',
        'msgstr "value"',
      }, "\n"))
      assert.are.same({ ["real.key"] = "value" }, entries)
    end)

    it("rejects an empty msgid after the first entry", function()
      assert.has_error(function()
        po.parse(table.concat({
          'msgid "first"',
          'msgstr "one"',
          "",
          'msgid ""',
          'msgstr "header out of place"',
        }, "\n"))
      end)
    end)

    it("rejects duplicate msgids", function()
      assert.has_error(function()
        po.parse(table.concat({
          'msgid "dup"',
          'msgstr "one"',
          "",
          'msgid "dup"',
          'msgstr "two"',
        }, "\n"))
      end)
    end)

    it("omits entries with an empty msgstr (untranslated semantics)", function()
      local entries = po.parse(table.concat({
        'msgid "present"',
        'msgstr "here"',
        "",
        'msgid "absent"',
        'msgstr ""',
      }, "\n"))
      assert.are.same({ ["present"] = "here" }, entries)
    end)

    it("skips all comment flavors including obsolete entries", function()
      local entries = po.parse(table.concat({
        "# translator comment",
        "#. extracted comment",
        "#: reference",
        "#, fuzzy",
        '#~ msgid "obsolete"',
        '#~ msgstr "gone"',
        'msgid "live"',
        'msgstr "value"',
      }, "\n"))
      assert.are.same({ ["live"] = "value" }, entries)
    end)

    it("rejects msgctxt with a descriptive error", function()
      local ok, err = pcall(po.parse, 'msgctxt "ctx"\nmsgid "k"\nmsgstr "v"\n')
      assert.is_false(ok)
      assert.truthy(tostring(err):match("msgctxt"))
    end)

    it("rejects plural forms with descriptive errors", function()
      local ok_plural, err_plural = pcall(po.parse, 'msgid "k"\nmsgid_plural "ks"\nmsgstr[0] "v"\n')
      assert.is_false(ok_plural)
      assert.truthy(tostring(err_plural):match("plural"))
    end)

    it("rejects a msgid with no msgstr", function()
      assert.has_error(function()
        po.parse('msgid "k"\n\nmsgid "j"\nmsgstr "v"\n')
      end)
    end)

    it("rejects garbage lines", function()
      assert.has_error(function()
        po.parse('msgid "k"\nmsgstr "v"\nwat is this\n')
      end)
    end)

    it("returns an empty table for empty content", function()
      assert.are.same({}, po.parse(""))
    end)
  end)

  describe("shipped catalogues", function()
    ---@param runtime_path string
    ---@return string path, string content
    local function read_shipped(runtime_path)
      local matches = vim.api.nvim_get_runtime_file(runtime_path, false)
      assert.is_truthy(matches[1], runtime_path .. " not found on runtimepath")
      local file = assert(io.open(matches[1], "r"))
      local content = file:read("*a")
      file:close()
      return matches[1], content
    end

    local function gettext_available()
      return vim.fn.executable("msgfmt") == 1 and vim.fn.executable("msgcat") == 1
    end

    ---Shared validation suite: every shipped catalogue must parse, carry its
    ---expected keys, satisfy GNU gettext, and survive an msgcat round-trip.
    ---@param runtime_path string
    ---@param expected_keys string[]
    local function describe_catalogue(runtime_path, expected_keys)
      describe(runtime_path, function()
        it("parses and contains the expected keys", function()
          local _, content = read_shipped(runtime_path)
          local entries = po.parse(content)
          for _, key in ipairs(expected_keys) do
            assert.is_string(entries[key], "missing catalogue key: " .. key)
          end
        end)

        it("passes msgfmt --check (valid PO by GNU gettext's judgement)", function()
          if not gettext_available() then
            pending("gettext tools not available")
            return
          end
          local path = read_shipped(runtime_path)
          local output_path = vim.fn.tempname()
          vim.fn.system({ "msgfmt", "--check", "--output-file", output_path, path })
          assert.are.equal(0, vim.v.shell_error, "msgfmt --check failed for " .. path)
        end)

        it("survives an msgcat round-trip with an identical key→content map", function()
          if not gettext_available() then
            pending("gettext tools not available")
            return
          end
          local path, content = read_shipped(runtime_path)
          local normalized = vim.fn.system({ "msgcat", path })
          assert.are.equal(0, vim.v.shell_error, "msgcat failed for " .. path)
          local original_entries = po.parse(content)
          local normalized_entries = po.parse(normalized)
          assert.are.same(original_entries, normalized_entries)
        end)
      end)
    end

    describe_catalogue("po/flemma-harness.po", {
      "tool.denied",
      "tool.rejected",
      "tool.rejected.feedback",
      "tool.aborted",
      "tool.error.unknown",
      "tool.output.not_saved",
      "tool.parameter.background",
      "tool.parameter.save_to",
      "job.executing.tracked",
      "job.executing.untracked",
      "job.lost",
      "request.aborted",
      "tool.bash.description",
      "tool.bash.input.label",
      "tool.bash.input.command",
      "tool.bash.input.timeout",
      "tool.edit.description",
      "tool.edit.input.label",
      "tool.edit.input.path",
      "tool.edit.input.oldText",
      "tool.edit.input.newText",
      "tool.find.description",
      "tool.find.input.label",
      "tool.find.input.pattern",
      "tool.find.input.path",
      "tool.find.input.limit",
      "tool.flemma.jobs.status.description",
      "tool.flemma.jobs.status.input.job_id",
      "tool.grep.description",
      "tool.grep.input.label",
      "tool.grep.input.pattern",
      "tool.grep.input.path",
      "tool.grep.input.glob",
      "tool.grep.input.limit",
      "tool.ls.description",
      "tool.ls.input.label",
      "tool.ls.input.path",
      "tool.ls.input.max_depth",
      "tool.ls.input.limit",
      "tool.read.description",
      "tool.read.input.label",
      "tool.read.input.path",
      "tool.read.input.offset",
      "tool.read.input.limit",
      "tool.write.description",
      "tool.write.input.label",
      "tool.write.input.path",
      "tool.write.input.content",
    })

    describe_catalogue("po/flemma.po", {
      "ui.usage.no_data",
    })

    it("keeps keys unique across the shipped catalogues", function()
      local _, harness_content = read_shipped("po/flemma-harness.po")
      local _, ui_content = read_shipped("po/flemma.po")
      local harness_entries = po.parse(harness_content)
      local ui_entries = po.parse(ui_content)
      for key in pairs(ui_entries) do
        assert.is_nil(harness_entries[key], "key defined in both catalogues: " .. key)
      end
    end)

    it("namespaces UI keys under ui.* and keeps harness keys out of it", function()
      local _, harness_content = read_shipped("po/flemma-harness.po")
      local _, ui_content = read_shipped("po/flemma.po")
      for key in pairs(po.parse(ui_content)) do
        assert.truthy(key:match("^ui%."), "UI catalogue key missing the ui. namespace: " .. key)
      end
      for key in pairs(po.parse(harness_content)) do
        assert.is_nil(key:match("^ui%."), "harness catalogue key inside the ui. namespace: " .. key)
      end
    end)
  end)
end)
