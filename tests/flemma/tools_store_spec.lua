describe("tools.store", function()
  local store

  before_each(function()
    package.loaded["flemma.tools.store"] = nil
    store = require("flemma.tools.store")
  end)

  describe("escape_id", function()
    it("passes through alphanumeric IDs", function()
      assert.equals("bash_1", store.escape_id("bash_1"))
    end)

    it("escapes colon to double dash", function()
      assert.equals("bash--8", store.escape_id("bash:8"))
    end)

    it("preserves dots, dashes, underscores", function()
      assert.equals("my_tool.v2-beta", store.escape_id("my_tool.v2-beta"))
    end)

    it("preserves double underscore from wire encoding", function()
      assert.equals("flemma__jobs__status--20", store.escape_id("flemma__jobs__status:20"))
    end)

    it("escapes multiple hostile characters", function()
      assert.equals("tool--a--b", store.escape_id("tool:a:b"))
    end)

    it("escapes spaces", function()
      assert.equals("has--space", store.escape_id("has space"))
    end)

    it("escapes slashes", function()
      assert.equals("path--to--thing", store.escape_id("path/to/thing"))
    end)
  end)

  describe("collapse_namespace", function()
    it("collapses .flemma/flemma/ to .flemma/", function()
      assert.equals("/home/user/.flemma/store/x", store.collapse_namespace("/home/user/.flemma/flemma/store/x"))
    end)

    it("collapses flemma/flemma/ to flemma/", function()
      assert.equals("/opt/flemma/store/x", store.collapse_namespace("/opt/flemma/flemma/store/x"))
    end)

    it("collapses repeated flemma segments to fixed point", function()
      assert.equals("/opt/flemma/x", store.collapse_namespace("/opt/flemma/flemma/flemma/x"))
    end)

    it("does not collapse myflemma/flemma/", function()
      assert.equals("/opt/myflemma/flemma/x", store.collapse_namespace("/opt/myflemma/flemma/x"))
    end)

    it("does not collapse flemma/flemma-lab/", function()
      assert.equals("/opt/flemma/flemma-lab/x", store.collapse_namespace("/opt/flemma/flemma-lab/x"))
    end)

    it("handles paths without flemma segments", function()
      assert.equals("/home/user/docs/file.txt", store.collapse_namespace("/home/user/docs/file.txt"))
    end)

    it("handles .flemma/flemma/flemma/ triple", function()
      assert.equals("/home/.flemma/x", store.collapse_namespace("/home/.flemma/flemma/flemma/x"))
    end)
  end)

  describe("get_store_path", function()
    it("renders $chat preset for saved buffer", function()
      local dir = store.get_store_path({
        __filename = "/home/user/chats/session.chat",
        __dirname = "/home/user/chats",
        source = "tool",
        name = "bash",
        id = "bash_1",
        path_format = "$chat",
      })
      assert.equals("/home/user/chats/.flemma/session.chat", dir)
    end)

    it("renders $state preset", function()
      local dir = store.get_store_path({
        __filename = "/home/user/chats/session.chat",
        __dirname = "/home/user/chats",
        source = "tool",
        name = "bash",
        id = "bash_1",
        path_format = "$state",
      })
      assert.is_truthy(dir:find("/store/"), "expected /store/ in path: " .. dir)
    end)

    it("renders free-form template", function()
      local dir = store.get_store_path({
        __filename = "/home/user/chats/session.chat",
        __dirname = "/home/user/chats",
        source = "tool",
        name = "bash",
        id = "bash_1",
        path_format = "/tmp/store/{{ source }}_{{ name }}_{{ id }}.txt",
      })
      assert.equals("/tmp/store", dir)
    end)

    it("errors on unknown preset", function()
      assert.has_error(function()
        store.get_store_path({
          __filename = "/tmp/x.chat",
          __dirname = "/tmp",
          source = "tool",
          name = "bash",
          id = "1",
          path_format = "$unknown",
        })
      end)
    end)

    it("applies namespace collapse to rendered path", function()
      local home = os.getenv("HOME")
      local dir = store.get_store_path({
        __filename = "/tmp/x.chat",
        __dirname = "/tmp",
        source = "tool",
        name = "bash",
        id = "1",
        path_format = home .. "/.flemma/flemma/store/{{ source }}_{{ name }}_{{ id }}.txt",
      })
      assert.is_truthy(dir:find("/.flemma/store"), "expected collapsed path: " .. dir)
      assert.is_falsy(dir:find("/.flemma/flemma/store"), "double flemma not collapsed: " .. dir)
    end)

    it("exposes flemma.path in template env", function()
      local dir = store.get_store_path({
        __filename = "/home/user/chats/session.chat",
        __dirname = "/home/user/chats",
        source = "tool",
        name = "bash",
        id = "1",
        path_format = "/tmp/{{ flemma.path.basename(__filename) }}/{{ source }}_{{ name }}_{{ id }}.txt",
      })
      assert.equals("/tmp/session.chat", dir)
    end)

    it("does not treat $HOME/... as a preset", function()
      local dir = store.get_store_path({
        __filename = "/tmp/x.chat",
        __dirname = "/tmp",
        source = "tool",
        name = "bash",
        id = "1",
        path_format = "$HOME/store/{{ source }}_{{ name }}_{{ id }}.txt",
      })
      local home = os.getenv("HOME")
      assert.equals(home .. "/store", dir)
    end)
  end)

  describe("get_store_path unnamed buffers", function()
    it("uses unnamed_path_format when __filename is nil", function()
      local dir = store.get_store_path({
        __filename = nil,
        __dirname = nil,
        source = "tool",
        name = "bash",
        id = "bash_1",
        bufnr = 42,
        unnamed_path_format = "${TMPDIR:-/tmp}/flemma/unnamed-{{ bufnr }}/{{ source }}_{{ name }}_{{ id }}.txt",
      })
      assert.is_truthy(dir:find("/flemma/unnamed%-42$"), "unexpected path: " .. dir)
    end)

    it("errors on preset in unnamed_path_format", function()
      assert.has_error(function()
        store.get_store_path({
          __filename = nil,
          __dirname = nil,
          source = "tool",
          name = "bash",
          id = "1",
          bufnr = 1,
          unnamed_path_format = "$chat",
        })
      end)
    end)
  end)

  describe("deduplicate_name_in_segment", function()
    it("collapses name_name_ to name_ (Kimi-style ID)", function()
      assert.equals("tool_bash_1", store.deduplicate_name_in_segment("tool_bash_bash_1", "bash"))
    end)

    it("collapses name-name_ to name_ (dash separator)", function()
      assert.equals("bash_1", store.deduplicate_name_in_segment("bash-bash_1", "bash"))
    end)

    it("does not collapse when second occurrence is a prefix of a longer word", function()
      assert.equals("tool_bash_basher", store.deduplicate_name_in_segment("tool_bash_basher", "bash"))
    end)

    it("collapses when second occurrence is at end of segment", function()
      assert.equals("tool_bash", store.deduplicate_name_in_segment("tool_bash_bash", "bash"))
    end)

    it("collapses repeated occurrences to fixed point", function()
      assert.equals("bash_1", store.deduplicate_name_in_segment("bash_bash_bash_1", "bash"))
    end)

    it("handles wire-encoded names with double underscore", function()
      local segment = "tool_flemma__jobs__status_flemma__jobs__status--20"
      local result = store.deduplicate_name_in_segment(segment, "flemma__jobs__status")
      assert.equals("tool_flemma__jobs__status--20", result)
    end)

    it("preserves double-dash escaping after de-duplication", function()
      local segment = "tool_bash_bash--8"
      local result = store.deduplicate_name_in_segment(segment, "bash")
      assert.equals("tool_bash--8", result)
    end)

    it("returns segment unchanged when name does not repeat", function()
      assert.equals(
        "tool_calculator_toolu_xyz",
        store.deduplicate_name_in_segment("tool_calculator_toolu_xyz", "calculator")
      )
    end)

    it("returns segment unchanged when name is empty", function()
      assert.equals("tool_bash_1", store.deduplicate_name_in_segment("tool_bash_1", ""))
    end)

    it("does not cross path boundaries (operates on single segment)", function()
      assert.equals("bash_1", store.deduplicate_name_in_segment("bash_bash_1", "bash"))
    end)
  end)

  describe("write", function()
    local function temp_dir()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      return dir
    end

    local function read_file(path)
      local f = io.open(path, "r")
      if not f then
        return nil
      end
      local content = f:read("*a")
      f:close()
      return content
    end

    it("writes content to a new file", function()
      local dir = temp_dir()
      local path = dir .. "/result.txt"
      local written_path, err = store.write(path, "hello world")
      assert.is_nil(err)
      assert.equals(path, written_path)
      assert.equals("hello world", read_file(path))
    end)

    it("creates parent directories", function()
      local dir = temp_dir()
      local path = dir .. "/deep/nested/result.txt"
      local written_path, err = store.write(path, "content")
      assert.is_nil(err)
      assert.equals(path, written_path)
      assert.equals("content", read_file(path))
    end)

    it("applies version backup on overwrite", function()
      local dir = temp_dir()
      local path = dir .. "/result.txt"
      store.write(path, "first")
      store.write(path, "second", { backup = "version" })
      assert.equals("second", read_file(path))
      assert.equals("first", read_file(dir .. "/result.1.txt"))
    end)

    it("increments version numbers", function()
      local dir = temp_dir()
      local path = dir .. "/result.txt"
      store.write(path, "v1")
      store.write(path, "v2", { backup = "version" })
      store.write(path, "v3", { backup = "version" })
      assert.equals("v3", read_file(path))
      assert.equals("v1", read_file(dir .. "/result.1.txt"))
      assert.equals("v2", read_file(dir .. "/result.2.txt"))
    end)

    it("overwrites in place when backup is false", function()
      local dir = temp_dir()
      local path = dir .. "/result.txt"
      store.write(path, "first")
      store.write(path, "second", { backup = false })
      assert.equals("second", read_file(path))
      assert.is_nil(read_file(dir .. "/result.1.txt"))
    end)

    it("returns nil and error on write failure", function()
      local written_path, err = store.write("/dev/null/impossible/file.txt", "content")
      assert.is_nil(written_path)
      assert.is_string(err)
    end)
  end)

  describe("backup strategy resolution", function()
    local function temp_dir()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      return dir
    end

    local function read_file(path)
      local f = io.open(path, "r")
      if not f then
        return nil
      end
      local content = f:read("*a")
      f:close()
      return content
    end

    after_each(function()
      package.preload["flemma_spec.custom_backup"] = nil
      package.loaded["flemma_spec.custom_backup"] = nil
      package.preload["flemma_spec.not_a_strategy"] = nil
      package.loaded["flemma_spec.not_a_strategy"] = nil
      package.preload["sneakymod"] = nil
      package.loaded["sneakymod"] = nil
    end)

    it("loads a custom strategy from a module path", function()
      package.preload["flemma_spec.custom_backup"] = function()
        return {
          backup = function(path)
            if vim.fn.filereadable(path) == 0 then
              return true, nil
            end
            local ok = os.rename(path, path .. ".bak")
            return ok ~= nil, nil
          end,
        }
      end
      local dir = temp_dir()
      local path = dir .. "/result.txt"
      store.write(path, "first")
      store.write(path, "second", { backup = "flemma_spec.custom_backup" })
      assert.equals("second", read_file(path))
      assert.equals("first", read_file(path .. ".bak"))
    end)

    it("rejects a module-path strategy without a backup export", function()
      package.preload["flemma_spec.not_a_strategy"] = function()
        return { unrelated = true }
      end
      local dir = temp_dir()
      local ok, err = pcall(store.write, dir .. "/result.txt", "content", { backup = "flemma_spec.not_a_strategy" })
      assert.is_false(ok)
      assert.is_truthy(tostring(err):find("must export a 'backup' function", 1, true))
    end)

    it("does not resolve naked names as bare modules", function()
      package.preload["sneakymod"] = function()
        return {
          backup = function()
            return true, nil
          end,
        }
      end
      local dir = temp_dir()
      local ok, err = pcall(store.write, dir .. "/result.txt", "content", { backup = "sneakymod" })
      assert.is_false(ok)
      assert.is_truthy(tostring(err):find("Unknown backup strategy 'sneakymod'", 1, true))
    end)

    it("lists known strategies in the unknown-strategy error", function()
      local dir = temp_dir()
      local ok, err = pcall(store.write, dir .. "/result.txt", "content", { backup = "versions" })
      assert.is_false(ok)
      assert.is_truthy(tostring(err):find("known: version", 1, true))
    end)
  end)

  describe("materialize", function()
    local function temp_dir()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      return dir
    end

    local function read_file(path)
      local f = io.open(path, "r")
      if not f then
        return nil
      end
      local content = f:read("*a")
      f:close()
      return content
    end

    it("writes full output with tool name in filename", function()
      local dir = temp_dir()
      local path, err = store.materialize({
        __filename = dir .. "/session.chat",
        __dirname = dir,
        source = "tool",
        name = "calculator",
        id = "toolu_xyz",
        path_format = dir .. "/{{ source }}_{{ name }}_{{ id }}.txt",
        content = "full tool output here",
        backup = "version",
      })
      assert.is_nil(err)
      assert.is_truthy(path)
      assert.is_truthy(path:find("tool_calculator_toolu_xyz%.txt$"), "expected name in path: " .. path)
      assert.equals("full tool output here", read_file(path))
    end)

    it("de-duplicates when ID starts with tool name (Kimi-style)", function()
      local dir = temp_dir()
      local path, err = store.materialize({
        __filename = dir .. "/session.chat",
        __dirname = dir,
        source = "tool",
        name = "bash",
        id = "bash_1",
        path_format = dir .. "/{{ source }}_{{ name }}_{{ id }}.txt",
        content = "output",
        backup = false,
      })
      assert.is_nil(err)
      assert.is_truthy(path:find("tool_bash_1%.txt$"), "expected de-duped: " .. path)
      assert.is_falsy(path:find("tool_bash_bash_1"), "name should not repeat: " .. path)
    end)

    it("de-duplicates wire-encoded dotted tool names", function()
      local dir = temp_dir()
      local path, err = store.materialize({
        __filename = dir .. "/session.chat",
        __dirname = dir,
        source = "tool",
        name = "flemma.jobs.status",
        id = "flemma__jobs__status:20",
        path_format = dir .. "/{{ source }}_{{ name }}_{{ id }}.txt",
        content = "output",
        backup = false,
      })
      assert.is_nil(err)
      assert.is_truthy(path:find("tool_flemma__jobs__status%-%-20%.txt$"), "expected de-duped: " .. path)
    end)

    it("escapes hostile characters in ID and de-duplicates name", function()
      local dir = temp_dir()
      local path, err = store.materialize({
        __filename = dir .. "/session.chat",
        __dirname = dir,
        source = "tool",
        name = "bash",
        id = "bash:8",
        path_format = dir .. "/{{ source }}_{{ name }}_{{ id }}.txt",
        content = "output",
        backup = false,
      })
      assert.is_nil(err)
      assert.is_truthy(path:find("tool_bash%-%-8%.txt$"), "expected de-duped + escaped: " .. path)
    end)

    it("skips write when materialize_enabled is false and not truncated", function()
      local dir = temp_dir()
      local path, err = store.materialize({
        __filename = dir .. "/session.chat",
        __dirname = dir,
        source = "tool",
        name = "bash",
        id = "bash_1",
        path_format = dir .. "/{{ source }}_{{ name }}_{{ id }}.txt",
        content = "short output",
        materialize_enabled = false,
        truncated = false,
        backup = "version",
      })
      assert.is_nil(err)
      assert.is_nil(path)
    end)

    it("writes even when materialize_enabled is false if truncated", function()
      local dir = temp_dir()
      local path, err = store.materialize({
        __filename = dir .. "/session.chat",
        __dirname = dir,
        source = "tool",
        id = "bash_1",
        path_format = dir .. "/{{ source }}_{{ id }}.txt",
        content = "truncated output",
        materialize_enabled = false,
        truncated = true,
        backup = "version",
      })
      assert.is_nil(err)
      assert.is_truthy(path)
    end)
  end)

  describe("materialize_for_completion", function()
    local function temp_dir()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      return dir
    end

    local function read_file(path)
      local f = io.open(path, "r")
      if not f then
        return nil
      end
      local content = f:read("*a")
      f:close()
      return content
    end

    it("writes file with tool name in path", function()
      local dir = temp_dir()
      local path, err = store.materialize_for_completion({
        bufnr = 0,
        __filename = dir .. "/test.chat",
        __dirname = dir,
        tool_name = "bash",
        tool_id = "toolu_xyz",
        source = "tool",
        result = { success = true, output = "hello world" },
        store_config = {
          path_format = dir .. "/.flemma/test.chat/{{ source }}_{{ name }}_{{ id }}.txt",
          materialize = true,
          backup = "version",
        },
      })
      assert.is_nil(err)
      assert.is_truthy(path)
      assert.is_truthy(path:find("tool_bash_toolu_xyz%.txt$"), "expected name in path: " .. path)
      assert.equals("hello world", read_file(path))
    end)

    it("skips materialization when materialize is false", function()
      local dir = temp_dir()
      local path, err = store.materialize_for_completion({
        bufnr = 0,
        __filename = dir .. "/test.chat",
        __dirname = dir,
        tool_name = "bash",
        tool_id = "bash_1",
        source = "tool",
        result = { success = true, output = "hello world" },
        store_config = {
          path_format = dir .. "/.flemma/test.chat/{{ source }}_{{ name }}_{{ id }}.txt",
          materialize = false,
          backup = "version",
        },
      })
      assert.is_nil(err)
      assert.is_nil(path)
    end)

    it("materializes table output as JSON", function()
      local dir = temp_dir()
      local json = require("flemma.utilities.json")
      local path, _ = store.materialize_for_completion({
        bufnr = 0,
        __filename = dir .. "/test.chat",
        __dirname = dir,
        tool_name = "bash",
        tool_id = "toolu_1",
        source = "tool",
        result = { success = true, output = { key = "value" } },
        store_config = {
          path_format = dir .. "/{{ source }}_{{ name }}_{{ id }}.txt",
          materialize = true,
          backup = false,
        },
      })
      assert.is_truthy(path)
      local content = read_file(path)
      local decoded = json.decode(content)
      assert.equals("value", decoded.key)
    end)

    it("materializes error output", function()
      local dir = temp_dir()
      local path, _ = store.materialize_for_completion({
        bufnr = 0,
        __filename = dir .. "/test.chat",
        __dirname = dir,
        tool_name = "bash",
        tool_id = "bash_1",
        source = "tool",
        result = { success = false, error = "command not found" },
        store_config = {
          path_format = dir .. "/{{ source }}_{{ name }}_{{ id }}.txt",
          materialize = true,
          backup = false,
        },
      })
      assert.is_truthy(path)
      local content = read_file(path)
      assert.is_truthy(content:find("command not found"))
    end)

    it("materializes job results with source=job", function()
      local dir = temp_dir()
      local path, err = store.materialize_for_completion({
        bufnr = 0,
        __filename = dir .. "/test.chat",
        __dirname = dir,
        tool_name = "bash",
        tool_id = "ab12cd34",
        source = "job",
        result = { success = true, output = "job output" },
        store_config = {
          path_format = dir .. "/{{ source }}_{{ name }}_{{ id }}.txt",
          materialize = true,
          backup = false,
        },
      })
      assert.is_nil(err)
      assert.is_truthy(path)
      assert.is_truthy(path:find("job_bash_ab12cd34%.txt$"), "expected job source in path: " .. path)
      assert.equals("job output", read_file(path))
    end)

    it("materializes job results without tool_name", function()
      local dir = temp_dir()
      local path, err = store.materialize_for_completion({
        bufnr = 0,
        __filename = dir .. "/test.chat",
        __dirname = dir,
        tool_id = "ab12cd34",
        source = "job",
        result = { success = true, output = "job output" },
        store_config = {
          path_format = dir .. "/{{ source }}_{{ name }}_{{ id }}.txt",
          materialize = true,
          backup = false,
        },
      })
      assert.is_nil(err)
      assert.is_truthy(path)
      assert.is_truthy(path:find("job__ab12cd34%.txt$"), "expected empty name: " .. path)
    end)
  end)

  describe("build_redirect_stub", function()
    it("includes preview and output-saved notice", function()
      local content = "line 1\nline 2\nline 3\nline 4\nline 5"
      local stub = store.build_redirect_stub(content, "/tmp/result.txt", { lines = 3, bytes = 2048 })
      assert.is_truthy(stub:find("line 1"), "preview should include first line")
      assert.is_truthy(stub:find("line 2"), "preview should include second line")
      assert.is_truthy(stub:find("line 3"), "preview should include third line")
      assert.is_truthy(stub:find("%[Output saved: /tmp/result%.txt"), "notice should include path")
      assert.is_truthy(stub:find("5 lines%]"), "notice should include line count")
    end)

    it("omits preview when lines = 0", function()
      local content = "line 1\nline 2"
      local stub = store.build_redirect_stub(content, "/tmp/result.txt", { lines = 0, bytes = 2048 })
      assert.is_falsy(stub:find("line 1"), "no preview when lines = 0")
      assert.is_truthy(stub:find("%[Output saved:"), "notice should still be present")
    end)

    it("caps preview by bytes for single-line content", function()
      local content = string.rep("x", 5000)
      local stub = store.build_redirect_stub(content, "/tmp/result.txt", { lines = 10, bytes = 100 })
      assert.is_truthy(#stub < 1000, "stub should be much shorter than content")
      assert.is_truthy(stub:find("%[Output saved:"), "notice should be present")
    end)
  end)

  describe("execute_redirect", function()
    local function temp_dir()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      return dir
    end

    local function read_file(path)
      local f = io.open(path, "r")
      if not f then
        return nil
      end
      local content = f:read("*a")
      f:close()
      return content
    end

    it("writes content and returns stub", function()
      local dir = temp_dir()
      local dest = dir .. "/output.txt"
      local stub, err = store.execute_redirect({
        save_to = dest,
        content = "full output content here",
        chat_dirname = dir,
        bufnr = 0,
        preview = { lines = 5, bytes = 2048 },
        backup = false,
      })
      assert.is_nil(err)
      assert.is_truthy(stub)
      assert.is_truthy(stub:find("%[Output saved:"))
      assert.equals("full output content here", read_file(dest))
    end)

    it("expands $FLEMMA_TOOLS_STORE_PATH in save_to", function()
      local dir = temp_dir()
      local stub, err = store.with_cwd(dir, function()
        return store.execute_redirect({
          save_to = "$FLEMMA_TOOLS_STORE_PATH/transcript.txt",
          content = "transcript content",
          chat_dirname = "/tmp",
          bufnr = 0,
          preview = { lines = 5, bytes = 2048 },
          backup = false,
        })
      end)
      assert.is_nil(err)
      assert.is_truthy(stub)
      assert.equals("transcript content", read_file(dir .. "/transcript.txt"))
    end)

    it("rejects bare $FLEMMA_TOOLS_STORE_PATH before the store directory exists", function()
      local dir = temp_dir()
      local store_dir = dir .. "/.flemma/session.chat"
      local stub, err = store.with_cwd(store_dir, function()
        return store.execute_redirect({
          save_to = "$FLEMMA_TOOLS_STORE_PATH",
          content = "data",
          chat_dirname = dir,
          bufnr = 0,
          preview = { lines = 5, bytes = 2048 },
          backup = false,
        })
      end)
      assert.is_nil(stub)
      assert.is_truthy(err)
      assert.is_truthy(err:find("append a filename", 1, true))
      assert.equals(0, vim.fn.filereadable(store_dir), "no file may occupy the store directory path")
    end)

    it("rejects a destination that is an ancestor of the store directory", function()
      local dir = temp_dir()
      local store_dir = dir .. "/.flemma/session.chat"
      local stub, err = store.with_cwd(store_dir, function()
        return store.execute_redirect({
          save_to = dir .. "/.flemma",
          content = "data",
          chat_dirname = dir,
          bufnr = 0,
          preview = { lines = 5, bytes = 2048 },
          backup = false,
        })
      end)
      assert.is_nil(stub)
      assert.is_truthy(err)
      assert.is_truthy(err:find("append a filename", 1, true))
      assert.equals(0, vim.fn.filereadable(dir .. "/.flemma"), "no file may occupy a store ancestor path")
    end)

    it("backs up an existing destination file outside the store before overwriting", function()
      local dir = temp_dir()
      local dest = dir .. "/report.txt"
      local f = assert(io.open(dest, "w"))
      f:write("precious user data")
      f:close()
      local stub, err = store.execute_redirect({
        save_to = dest,
        content = "new output",
        chat_dirname = dir,
        bufnr = 0,
        preview = { lines = 5, bytes = 2048 },
        backup = "version",
      })
      assert.is_nil(err)
      assert.is_truthy(stub)
      assert.equals("new output", read_file(dest))
      assert.equals("precious user data", read_file(dir .. "/report.1.txt"))
    end)

    it("writes into a not-yet-created store directory when a filename is given", function()
      local dir = temp_dir()
      local store_dir = dir .. "/.flemma/session.chat"
      local stub, err = store.with_cwd(store_dir, function()
        return store.execute_redirect({
          save_to = "$FLEMMA_TOOLS_STORE_PATH/result.txt",
          content = "data",
          chat_dirname = dir,
          bufnr = 0,
          preview = { lines = 5, bytes = 2048 },
          backup = false,
        })
      end)
      assert.is_nil(err)
      assert.is_truthy(stub)
      assert.equals("data", read_file(store_dir .. "/result.txt"))
    end)

    it("resolves relative paths against chat_dirname", function()
      local dir = temp_dir()
      local stub, err = store.execute_redirect({
        save_to = "./output.txt",
        content = "relative content",
        chat_dirname = dir,
        bufnr = 0,
        preview = { lines = 5, bytes = 2048 },
        backup = false,
      })
      assert.is_nil(err)
      assert.is_truthy(stub)
      assert.equals("relative content", read_file(dir .. "/output.txt"))
    end)

    it("errors when save_to is a directory", function()
      local dir = temp_dir()
      local stub, err = store.execute_redirect({
        save_to = dir,
        content = "should not write",
        chat_dirname = "/tmp",
        bufnr = 0,
        preview = { lines = 5, bytes = 2048 },
        backup = false,
      })
      assert.is_nil(stub)
      assert.is_truthy(err)
      assert.is_truthy(err:find("directory"), "error should mention directory: " .. err)
    end)

    it("falls back to nil stub on write failure", function()
      local stub, err = store.execute_redirect({
        save_to = "/dev/null/impossible/file.txt",
        content = "should fail",
        chat_dirname = "/tmp",
        bufnr = 0,
        preview = { lines = 5, bytes = 2048 },
        backup = false,
      })
      assert.is_nil(stub)
      assert.is_truthy(err)
    end)
  end)

  describe("apply_redirect", function()
    local function temp_dir()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      return dir
    end

    local function read_file(path)
      local f = io.open(path, "r")
      if not f then
        return nil
      end
      local content = f:read("*a")
      f:close()
      return content
    end

    it("replaces output with a stub on success", function()
      local dir = temp_dir()
      local result, err = store.apply_redirect({
        save_to = dir .. "/out.txt",
        result = { success = true, output = "full content" },
        bufnr = 0,
        store_config = { preview = { lines = 5, bytes = 2048 }, backup = false },
      })
      assert.is_nil(err)
      assert.is_true(result.success)
      assert.is_truthy(result.output:find("[Output saved:", 1, true))
      assert.equals("full content", read_file(dir .. "/out.txt"))
    end)

    it("keeps the full output and appends a notice on failure", function()
      local dir = temp_dir()
      local result, err = store.apply_redirect({
        save_to = dir, -- existing directory: redirect must fail
        result = { success = true, output = "full content" },
        bufnr = 0,
        store_config = { preview = { lines = 5, bytes = 2048 }, backup = false },
      })
      assert.is_truthy(err)
      assert.is_true(result.success)
      assert.is_truthy(vim.startswith(result.output, "full content"))
      assert.is_truthy(result.output:find("[Output not saved:", 1, true))
      assert.is_truthy(result.output:find("append a filename", 1, true))
      assert.is_truthy(result.output:find("Showing the full output instead", 1, true))
    end)

    it("encodes table output as JSON on the fallback path", function()
      local dir = temp_dir()
      local result = store.apply_redirect({
        save_to = dir, -- existing directory: redirect must fail
        result = { success = true, output = { key = "value" } },
        bufnr = 0,
        store_config = { preview = { lines = 5, bytes = 2048 }, backup = false },
      })
      assert.is_truthy(result.output:find('"key"', 1, true))
      assert.is_truthy(result.output:find("[Output not saved:", 1, true))
    end)
  end)

  describe("ensure_buffer_store_path", function()
    it("creates the directory if it does not exist", function()
      local target = vim.fn.tempname() .. "/nested/store"

      local original = store.get_buffer_store_path
      store.get_buffer_store_path = function()
        return target
      end

      assert.equals(0, vim.fn.isdirectory(target))
      local result = store.ensure_buffer_store_path(0)
      assert.equals(target, result)
      assert.equals(1, vim.fn.isdirectory(target))

      store.get_buffer_store_path = original
    end)

    it("is a no-op when the directory already exists", function()
      local target = vim.fn.tempname()
      vim.fn.mkdir(target, "p")

      local original = store.get_buffer_store_path
      store.get_buffer_store_path = function()
        return target
      end

      local result = store.ensure_buffer_store_path(0)
      assert.equals(target, result)
      assert.equals(1, vim.fn.isdirectory(target))

      store.get_buffer_store_path = original
    end)
  end)

  describe("with_cwd", function()
    it("sets FLEMMA_TOOLS_STORE_PATH during callback", function()
      local variables = require("flemma.utilities.variables")
      local result = store.with_cwd("/tmp/store-test", function()
        return variables.expand_inline("$FLEMMA_TOOLS_STORE_PATH/file.txt")
      end)
      assert.equals("/tmp/store-test/file.txt", result)
    end)

    it("restores previous value after callback", function()
      local variables = require("flemma.utilities.variables")
      store.with_cwd("/tmp/inner", function() end)
      local result = variables.expand_inline("$FLEMMA_TOOLS_STORE_PATH")
      assert.equals("", result)
    end)

    it("propagates multiple return values from the callback", function()
      local first, second = store.with_cwd("/tmp/multi", function()
        return nil, "second value"
      end)
      assert.is_nil(first)
      assert.equals("second value", second)
    end)

    it("restores previous value on error", function()
      local variables = require("flemma.utilities.variables")
      pcall(store.with_cwd, "/tmp/will-error", function()
        error("boom")
      end)
      local result = variables.expand_inline("$FLEMMA_TOOLS_STORE_PATH")
      assert.equals("", result)
    end)
  end)
end)
