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

  describe("resolve_path", function()
    it("renders $chat preset for saved buffer", function()
      local path = store.resolve_path({
        __filename = "/home/user/chats/session.chat",
        __dirname = "/home/user/chats",
        source = "tool",
        id = "bash_1",
        path_format = "$chat",
      })
      assert.equals("/home/user/chats/.flemma/session.chat/tool_bash_1.txt", path)
    end)

    it("renders $state preset", function()
      local path = store.resolve_path({
        __filename = "/home/user/chats/session.chat",
        __dirname = "/home/user/chats",
        source = "tool",
        id = "bash_1",
        path_format = "$state",
      })
      assert.is_truthy(path:find("/store/"), "expected /store/ in path: " .. path)
      assert.is_truthy(path:find("tool_bash_1%.txt$"), "expected tool_bash_1.txt suffix: " .. path)
    end)

    it("renders free-form template", function()
      local path = store.resolve_path({
        __filename = "/home/user/chats/session.chat",
        __dirname = "/home/user/chats",
        source = "tool",
        id = "bash_1",
        path_format = "/tmp/store/{{ source }}_{{ id }}.txt",
      })
      assert.equals("/tmp/store/tool_bash_1.txt", path)
    end)

    it("escapes hostile characters in ID", function()
      local path = store.resolve_path({
        __filename = "/home/user/chats/session.chat",
        __dirname = "/home/user/chats",
        source = "tool",
        id = "bash:8",
        path_format = "$chat",
      })
      assert.is_truthy(path:find("tool_bash%-%-8%.txt$"), "expected escaped ID: " .. path)
    end)

    it("errors on unknown preset", function()
      assert.has_error(function()
        store.resolve_path({
          __filename = "/tmp/x.chat",
          __dirname = "/tmp",
          source = "tool",
          id = "1",
          path_format = "$unknown",
        })
      end)
    end)

    it("applies namespace collapse to rendered path", function()
      local home = os.getenv("HOME")
      local path = store.resolve_path({
        __filename = "/tmp/x.chat",
        __dirname = "/tmp",
        source = "tool",
        id = "1",
        path_format = home .. "/.flemma/flemma/store/{{ source }}_{{ id }}.txt",
      })
      assert.is_truthy(path:find("/.flemma/store/"), "expected collapsed path: " .. path)
      assert.is_falsy(path:find("/.flemma/flemma/store/"), "double flemma not collapsed: " .. path)
    end)

    it("exposes flemma.path in template env", function()
      local path = store.resolve_path({
        __filename = "/home/user/chats/session.chat",
        __dirname = "/home/user/chats",
        source = "tool",
        id = "1",
        path_format = "/tmp/{{ flemma.path.basename(__filename) }}/{{ source }}_{{ id }}.txt",
      })
      assert.equals("/tmp/session.chat/tool_1.txt", path)
    end)

    it("does not treat $chat/extra as a preset", function()
      local path = store.resolve_path({
        __filename = "/tmp/x.chat",
        __dirname = "/tmp",
        source = "tool",
        id = "1",
        path_format = "$HOME/store/{{ source }}_{{ id }}.txt",
      })
      local home = os.getenv("HOME")
      assert.equals(home .. "/store/tool_1.txt", path)
    end)
  end)

  describe("resolve_path unnamed buffers", function()
    it("uses unnamed_path_format when __filename is nil", function()
      local path = store.resolve_path({
        __filename = nil,
        __dirname = nil,
        source = "tool",
        id = "bash_1",
        bufnr = 42,
        unnamed_path_format = "${TMPDIR:-/tmp}/flemma/unsaved-{{ bufnr }}/{{ source }}_{{ id }}.txt",
      })
      assert.is_truthy(path:find("/flemma/unsaved%-42/tool_bash_1%.txt$"), "unexpected path: " .. path)
    end)

    it("errors on preset in unnamed_path_format", function()
      assert.has_error(function()
        store.resolve_path({
          __filename = nil,
          __dirname = nil,
          source = "tool",
          id = "1",
          bufnr = 1,
          unnamed_path_format = "$chat",
        })
      end)
    end)
  end)

  describe("resolve_dir", function()
    it("returns parent directory of resolved path", function()
      local dir = store.resolve_dir({
        __filename = "/home/user/chats/session.chat",
        __dirname = "/home/user/chats",
        source = "tool",
        id = "bash_1",
        path_format = "$chat",
      })
      assert.equals("/home/user/chats/.flemma/session.chat", dir)
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

    it("writes full output and returns path", function()
      local dir = temp_dir()
      local path, err = store.materialize({
        __filename = dir .. "/session.chat",
        __dirname = dir,
        source = "tool",
        id = "bash_1",
        path_format = dir .. "/.flemma/{{ flemma.path.basename(__filename) }}/{{ source }}_{{ id }}.txt",
        content = "full tool output here",
        backup = "version",
      })
      assert.is_nil(err)
      assert.is_truthy(path)
      assert.equals("full tool output here", read_file(path))
    end)

    it("skips write when materialize_enabled is false and not truncated", function()
      local dir = temp_dir()
      local path, err = store.materialize({
        __filename = dir .. "/session.chat",
        __dirname = dir,
        source = "tool",
        id = "bash_1",
        path_format = dir .. "/{{ source }}_{{ id }}.txt",
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
end)
