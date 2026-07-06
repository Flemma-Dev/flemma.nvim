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
      assert.are.same({ "The tool was denied by a policy." }, entries["tool.denied"].forms)
    end)

    it("parses multiple entries separated by blank lines", function()
      local entries = po.parse(table.concat({
        'msgid "a.one"',
        'msgstr "first"',
        "",
        'msgid "a.two"',
        'msgstr "second"',
      }, "\n"))
      assert.are.same({ "first" }, entries["a.one"].forms)
      assert.are.same({ "second" }, entries["a.two"].forms)
    end)

    it("concatenates continuation strings exactly, without implicit whitespace", function()
      local entries = po.parse(table.concat({
        'msgid "key"',
        'msgstr ""',
        '"Hello "',
        '"world"',
        '", exactly"',
      }, "\n"))
      assert.are.equal("Hello world, exactly", entries["key"].forms[1])
    end)

    it("supports continuation strings on msgid too", function()
      local entries = po.parse(table.concat({
        'msgid "tool.bash"',
        '".description"',
        'msgstr "text"',
      }, "\n"))
      assert.are.equal("text", entries["tool.bash.description"].forms[1])
    end)

    it("decodes the supported escape sequences", function()
      local entries = po.parse('msgid "k"\nmsgstr "line1\\nline2\\ttabbed \\"quoted\\" back\\\\slash"\n')
      assert.are.equal('line1\nline2\ttabbed "quoted" back\\slash', entries["k"].forms[1])
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
      assert.are.same({ "value" }, entries["real.key"].forms)
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
      assert.are.same({ "here" }, entries["present"].forms)
      assert.is_nil(entries["absent"])
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
      assert.are.same({ "value" }, entries["live"].forms)
    end)

    it("rejects msgctxt with a descriptive error", function()
      local ok, err = pcall(po.parse, 'msgctxt "ctx"\nmsgid "k"\nmsgstr "v"\n')
      assert.is_false(ok)
      assert.truthy(tostring(err):match("msgctxt"))
    end)

    it("parses a plural entry with msgid_plural and msgstr[N]", function()
      local entries = po.parse(table.concat({
        'msgid ""',
        'msgstr ""',
        '"Plural-Forms: nplurals=2; plural=(n != 1);\\n"',
        "",
        'msgid "item.count"',
        'msgid_plural "item.count"',
        'msgstr[0] "one item"',
        'msgstr[1] "many items"',
      }, "\n"))
      local entry = entries["item.count"]
      assert.are.same({ "one item", "many items" }, entry.forms)
      assert.are.equal(0, entry.plural(1))
      assert.are.equal(1, entry.plural(0))
      assert.are.equal(1, entry.plural(5))
    end)

    it("parses plural entries with continuation strings", function()
      local entries = po.parse(table.concat({
        'msgid ""',
        'msgstr ""',
        '"Plural-Forms: nplurals=2; plural=(n != 1);\\n"',
        "",
        'msgid "long.plural"',
        'msgid_plural "long.plural"',
        'msgstr[0] ""',
        '"one "',
        '"thing"',
        'msgstr[1] ""',
        '"many "',
        '"things"',
      }, "\n"))
      assert.are.same({ "one thing", "many things" }, entries["long.plural"].forms)
    end)

    it("defaults to English plural rule when no Plural-Forms header", function()
      local entries = po.parse(table.concat({
        'msgid "k"',
        'msgid_plural "k"',
        'msgstr[0] "singular"',
        'msgstr[1] "plural"',
      }, "\n"))
      local entry = entries["k"]
      assert.are.equal(0, entry.plural(1))
      assert.are.equal(1, entry.plural(2))
    end)

    it("mixes simple and plural entries in the same catalogue", function()
      local entries = po.parse(table.concat({
        'msgid ""',
        'msgstr ""',
        '"Plural-Forms: nplurals=2; plural=(n != 1);\\n"',
        "",
        'msgid "simple.key"',
        'msgstr "hello"',
        "",
        'msgid "plural.key"',
        'msgid_plural "plural.key"',
        'msgstr[0] "one"',
        'msgstr[1] "many"',
      }, "\n"))
      assert.are.same({ "hello" }, entries["simple.key"].forms)
      assert.is_nil(entries["simple.key"].plural)
      assert.are.same({ "one", "many" }, entries["plural.key"].forms)
      assert.is_function(entries["plural.key"].plural)
    end)

    it("applies the Russian 3-form plural rule from the header", function()
      local entries = po.parse(table.concat({
        'msgid ""',
        'msgstr ""',
        '"Plural-Forms: nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);\\n"',
        "",
        'msgid "file.count"',
        'msgid_plural "file.count"',
        'msgstr[0] "{{ count }} файл"',
        'msgstr[1] "{{ count }} файла"',
        'msgstr[2] "{{ count }} файлов"',
      }, "\n"))
      local p = entries["file.count"].plural
      -- singular: 1, 21, 31, 101, 121
      assert.are.equal(0, p(1))
      assert.are.equal(0, p(21))
      assert.are.equal(0, p(101))
      -- few: 2-4, 22-24, 32-34
      assert.are.equal(1, p(2))
      assert.are.equal(1, p(3))
      assert.are.equal(1, p(22))
      -- many: 0, 5-20, 25-30, 11-14, 111-114
      assert.are.equal(2, p(0))
      assert.are.equal(2, p(5))
      assert.are.equal(2, p(11))
      assert.are.equal(2, p(12))
      assert.are.equal(2, p(20))
      assert.are.equal(2, p(111))
      -- verify all 3 forms are stored
      assert.are.same({
        "{{ count }} файл",
        "{{ count }} файла",
        "{{ count }} файлов",
      }, entries["file.count"].forms)
    end)

    it("applies the French 2-form plural rule from the header", function()
      local entries = po.parse(table.concat({
        'msgid ""',
        'msgstr ""',
        '"Plural-Forms: nplurals=2; plural=(n > 1);\\n"',
        "",
        'msgid "item.count"',
        'msgid_plural "item.count"',
        'msgstr[0] "{{ count }} élément"',
        'msgstr[1] "{{ count }} éléments"',
      }, "\n"))
      local p = entries["item.count"].plural
      -- French: 0 and 1 are singular, 2+ are plural
      assert.are.equal(0, p(0))
      assert.are.equal(0, p(1))
      assert.are.equal(1, p(2))
      assert.are.equal(1, p(100))
      assert.are.same({
        "{{ count }} élément",
        "{{ count }} éléments",
      }, entries["item.count"].forms)
    end)

    it("rejects msgid_plural without a preceding msgid", function()
      assert.has_error(function()
        po.parse('msgid_plural "ks"\nmsgstr[0] "v"\n')
      end)
    end)

    it("rejects msgstr[N] without msgid_plural", function()
      assert.has_error(function()
        po.parse('msgid "k"\nmsgstr[0] "v"\n')
      end)
    end)

    it("rejects non-sequential msgstr[N] indices", function()
      assert.has_error(function()
        po.parse(table.concat({
          'msgid "k"',
          'msgid_plural "k"',
          'msgstr[0] "a"',
          'msgstr[2] "c"',
        }, "\n"))
      end)
    end)

    it("rejects msgid_plural with no msgstr[0]", function()
      assert.has_error(function()
        po.parse('msgid "k"\nmsgid_plural "ks"\n\nmsgid "j"\nmsgstr "v"\n')
      end)
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
            assert.is_table(entries[key], "missing catalogue key: " .. key)
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
          -- Compare forms arrays (the compiled plural function can't be
          -- compared, but forms are the data content).
          for key, original in pairs(original_entries) do
            local normalized_val = normalized_entries[key]
            assert.is_truthy(normalized_val, "key missing after round-trip: " .. key)
            assert.are.same(original.forms, normalized_val.forms)
          end
          for key in pairs(normalized_entries) do
            assert.is_truthy(original_entries[key], "extra key after round-trip: " .. key)
          end
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
      "ui.rejection.prompt",
      "ui.rejection.reject_failed",
      "ui.rejection.no_tool_call",
      "ui.rejection.no_result_placeholder",
      "ui.rejection.already_completed",
      "ui.rejection.no_fence",
      "ui.tool.execute_failed",
      "ui.tool.background_failed",
      "ui.tool.backgrounded",
      "ui.tool.approve_failed",
      "ui.tool.no_pending_approve",
      "ui.tool.nothing_to_cancel_retry",
      "ui.migration.orphaned_jobs_resolved",
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
