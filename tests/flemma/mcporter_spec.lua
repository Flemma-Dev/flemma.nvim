-- tests/flemma/mcporter_spec.lua
local tools_truncate = require("flemma.tools.truncate")

describe("mcporter", function()
  local mcporter

  before_each(function()
    package.loaded["flemma.tools.definitions.mcporter"] = nil
    mcporter = require("flemma.tools.definitions.mcporter")
  end)

  describe("_glob_match", function()
    it("matches exact names", function()
      assert.is_true(mcporter._glob_match("slack:channels_list", "slack:channels_list"))
    end)

    it("matches wildcard suffix", function()
      assert.is_true(mcporter._glob_match("slack:channels_list", "slack:*"))
    end)

    it("matches wildcard prefix", function()
      assert.is_true(mcporter._glob_match("slack:channels_list", "*:channels_list"))
    end)

    it("matches standalone wildcard", function()
      assert.is_true(mcporter._glob_match("anything", "*"))
    end)

    it("rejects non-matching pattern", function()
      assert.is_false(mcporter._glob_match("slack:channels_list", "github:*"))
    end)

    it("rejects partial mismatch", function()
      assert.is_false(mcporter._glob_match("slack:channels_list", "slack:users_*"))
    end)
  end)

  describe("_filter_tools", function()
    local tools = {
      { name = "slack:channels_list" },
      { name = "slack:users_search" },
      { name = "slack:usergroups_create" },
      { name = "github:search_code" },
      { name = "github:create_pull_request" },
    }

    it("returns all disabled when include is empty", function()
      local result = mcporter._filter_tools(tools, {}, {})
      for _, tool in ipairs(result) do
        assert.is_false(tool.enabled)
      end
      assert.equals(5, #result)
    end)

    it("enables matching include patterns", function()
      local result = mcporter._filter_tools(tools, { "slack:*" }, {})
      local enabled = vim.tbl_filter(function(t)
        return t.enabled
      end, result)
      local disabled = vim.tbl_filter(function(t)
        return not t.enabled
      end, result)
      assert.equals(3, #enabled)
      assert.equals(2, #disabled)
    end)

    it("excludes matching exclude patterns", function()
      local result = mcporter._filter_tools(tools, { "slack:*" }, { "slack:usergroups_*" })
      local names = vim.tbl_map(function(t)
        return t.name
      end, result)
      assert.is_false(vim.tbl_contains(names, "slack:usergroups_create"))
      assert.equals(4, #result)
    end)

    it("include * enables everything", function()
      local result = mcporter._filter_tools(tools, { "*" }, {})
      for _, tool in ipairs(result) do
        assert.is_true(tool.enabled)
      end
    end)

    it("exclude removes before include sees them", function()
      local result = mcporter._filter_tools(tools, { "*" }, { "github:*" })
      local names = vim.tbl_map(function(t)
        return t.name
      end, result)
      assert.equals(3, #result)
      for _, name in ipairs(names) do
        assert.is_falsy(name:find("^github"))
      end
    end)
  end)

  describe("_parse_server_list", function()
    local fixture_dir = "tests/fixtures/mcporter"

    it("extracts healthy servers with tool stubs", function()
      local f = io.open(fixture_dir .. "/list.json", "r")
      assert.is_truthy(f)
      local json_str = f:read("*a")
      f:close()
      local servers = mcporter._parse_server_list(json_str)
      assert.is_truthy(#servers > 0)
      for _, server in ipairs(servers) do
        assert.equals("ok", server.status)
        assert.is_truthy(#server.tools > 0)
      end
    end)

    it("returns empty for no healthy servers", function()
      local f = io.open(fixture_dir .. "/list-empty.json", "r")
      assert.is_truthy(f)
      local json_str = f:read("*a")
      f:close()
      local servers = mcporter._parse_server_list(json_str)
      assert.equals(0, #servers)
    end)

    it("filters to only healthy servers", function()
      local f = io.open(fixture_dir .. "/list-partial.json", "r")
      assert.is_truthy(f)
      local json_str = f:read("*a")
      f:close()
      local servers = mcporter._parse_server_list(json_str)
      assert.equals(1, #servers)
      assert.equals("slack", servers[1].name)
    end)

    it("returns nil for malformed JSON", function()
      local servers = mcporter._parse_server_list("not json{{{")
      assert.is_nil(servers)
    end)
  end)

  describe("_parse_call_response", function()
    it("extracts single text block", function()
      local text = mcporter._parse_call_response('{"content":[{"type":"text","text":"hello"}]}')
      assert.equals("hello", text)
    end)

    it("joins multiple text blocks with double newline", function()
      local text =
        mcporter._parse_call_response('{"content":[{"type":"text","text":"first"},{"type":"text","text":"second"}]}')
      assert.equals("first\n\nsecond", text)
    end)

    it("silently drops non-text content blocks", function()
      local text =
        mcporter._parse_call_response('{"content":[{"type":"image","data":"base64"},{"type":"text","text":"kept"}]}')
      assert.equals("kept", text)
    end)

    it("falls back to raw text for empty content array", function()
      local text = mcporter._parse_call_response('{"content":[]}')
      assert.equals('{"content":[]}', text)
    end)

    it("falls back to raw text for missing content field", function()
      local text = mcporter._parse_call_response('{"other":"data"}')
      assert.equals('{"other":"data"}', text)
    end)

    it("falls back to raw text for non-JSON output", function()
      local text = mcporter._parse_call_response("plain text result")
      assert.equals("plain text result", text)
    end)

    it("returns nil for empty output", function()
      local text, err = mcporter._parse_call_response("")
      assert.is_nil(text)
      assert.is_string(err)
    end)

    it("returns is_error true when isError is set", function()
      local text, err, is_error =
        mcporter._parse_call_response('{"content":[{"type":"text","text":"something went wrong"}],"isError":true}')
      assert.equals("something went wrong", text)
      assert.is_nil(err)
      assert.is_true(is_error)
    end)

    it("returns is_error false for normal responses", function()
      local _, _, is_error = mcporter._parse_call_response('{"content":[{"type":"text","text":"ok"}]}')
      assert.is_false(is_error)
    end)

    it("returns is_error false for raw text passthrough", function()
      local _, _, is_error = mcporter._parse_call_response("plain text")
      assert.is_false(is_error)
    end)
  end)

  describe("_build_tool_definition", function()
    local json = require("flemma.utilities.json")
    local fixture_dir = "tests/fixtures/mcporter"

    it("builds a valid ToolDefinition from schema data", function()
      local f = io.open(fixture_dir .. "/list-slack.json", "r")
      assert.is_truthy(f)
      local json_str = f:read("*a")
      f:close()
      local data = json.decode(json_str)
      local tool_data = data.tools[1]

      local def = mcporter._build_tool_definition("slack", tool_data, {
        path = "mcporter",
        timeout = 60,
      })

      assert.equals("slack:" .. tool_data.name, def.name)
      assert.equals(tool_data.description, def.description)
      assert.is_true(def.async)
      assert.is_function(def.execute)
      assert.is_table(def.input_schema)
      assert.equals("object", def.input_schema.type)
    end)

    it("uses colon separator in name", function()
      local def = mcporter._build_tool_definition("my-server", {
        name = "my_tool",
        description = "test",
        inputSchema = { type = "object", properties = {} },
      }, { path = "mcporter", timeout = 60 })

      assert.equals("my-server:my_tool", def.name)
    end)

    it("sanitizes dots in server names to hyphens", function()
      local def = mcporter._build_tool_definition("my.dotted.server", {
        name = "my_tool",
        description = "test",
        inputSchema = { type = "object", properties = {} },
      }, { path = "mcporter", timeout = 60 })

      assert.equals("my-dotted-server:my_tool", def.name)
    end)
  end)

  describe("_fanout_schema_fetches", function()
    before_each(function()
      vim.env.MCPORTER_FIXTURE_DIR = vim.fn.fnamemodify("tests/fixtures/mcporter", ":p")
    end)

    after_each(function()
      vim.env.MCPORTER_FIXTURE_DIR = nil
    end)

    it("calls callback with parsed tool definitions for each server", function()
      local mock_path = vim.fn.fnamemodify("tests/fixtures/mcporter/mock-mcporter.sh", ":p")
      local servers = { { name = "slack" } }
      local collected = {}
      local done_called = false

      mcporter._fanout_schema_fetches(servers, {
        path = mock_path,
        timeout = 10,
        concurrency = 2,
      }, function(server_name, tool_defs)
        collected[server_name] = tool_defs
      end, function()
        done_called = true
      end)

      vim.wait(5000, function()
        return done_called
      end)
      assert.is_true(done_called)
      assert.is_truthy(collected.slack)
      assert.is_truthy(#collected.slack > 0)
      for _, def in ipairs(collected.slack) do
        assert.is_string(def.name)
        assert.is_table(def.inputSchema)
      end
    end)
  end)

  describe("_resolve_with_config", function()
    local tools = require("flemma.tools")

    before_each(function()
      package.loaded["flemma.tools.definitions.mcporter"] = nil
      mcporter = require("flemma.tools.definitions.mcporter")
      tools.clear()
      vim.env.MCPORTER_FIXTURE_DIR = vim.fn.fnamemodify("tests/fixtures/mcporter", ":p")
    end)

    after_each(function()
      vim.env.MCPORTER_FIXTURE_DIR = nil
    end)

    it("registers tools from mock mcporter with include filter", function()
      local mock_path = vim.fn.fnamemodify("tests/fixtures/mcporter/mock-mcporter.sh", ":p")
      local registered = {}
      local done_called = false

      mcporter._resolve_with_config({
        enabled = true,
        path = mock_path,
        timeout = 10,
        startup = { concurrency = 2 },
        include = { "slack:*" },
        exclude = {},
      }, function(name, def)
        registered[name] = def
      end, function()
        done_called = true
      end)

      vim.wait(10000, function()
        return done_called
      end)
      assert.is_true(done_called)

      local has_slack = false
      for name, def in pairs(registered) do
        if name:find("^slack:") then
          has_slack = true
          assert.is_true(def.enabled)
        end
      end
      assert.is_true(has_slack)

      for name, def in pairs(registered) do
        if name:find("^github:") then
          assert.is_false(def.enabled)
        end
      end
    end)

    it("registers nothing when disabled", function()
      local registered = {}
      local done_called = false

      mcporter._resolve_with_config({ enabled = false }, function(name, def)
        registered[name] = def
      end, function()
        done_called = true
      end)

      vim.wait(1000, function()
        return done_called
      end)
      assert.is_true(done_called)
      assert.equals(0, vim.tbl_count(registered))
    end)

    it("registers nothing when binary not found", function()
      local registered = {}
      local done_called = false

      mcporter._resolve_with_config({
        enabled = true,
        path = "/nonexistent/mcporter",
        timeout = 10,
        startup = { concurrency = 2 },
        include = {},
        exclude = {},
      }, function(name, def)
        registered[name] = def
      end, function()
        done_called = true
      end)

      vim.wait(1000, function()
        return done_called
      end)
      assert.is_true(done_called)
      assert.equals(0, vim.tbl_count(registered))
    end)
  end)

  describe("E2E", function()
    before_each(function()
      vim.env.MCPORTER_FIXTURE_DIR = vim.fn.fnamemodify("tests/fixtures/mcporter", ":p")
    end)

    after_each(function()
      vim.env.MCPORTER_FIXTURE_DIR = nil
    end)

    it("executes a tool via mock mcporter and returns content", function()
      local mock_path = vim.fn.fnamemodify("tests/fixtures/mcporter/mock-mcporter.sh", ":p")

      local def = mcporter._build_tool_definition("slack", {
        name = "channels_list",
        description = "Get list of channels",
        inputSchema = {
          type = "object",
          properties = { channel_types = { type = "string" } },
          required = { "channel_types" },
        },
      }, { path = mock_path, timeout = 10 })

      local result = nil
      local ctx = {
        cwd = vim.fn.getcwd(),
        timeout = 10,
        get_config = function()
          return nil
        end,
        truncate = setmetatable({
          truncate_with_overflow = function(text, opts)
            opts.bufnr = 0
            return tools_truncate.truncate_with_overflow(text, opts)
          end,
        }, { __index = tools_truncate }),
      }

      def.execute({ channel_types = "public_channel" }, ctx, function(r)
        result = r
      end)

      vim.wait(5000, function()
        return result ~= nil
      end)
      assert.is_not_nil(result)
      assert.is_true(result.success)
      assert.is_string(result.output)
    end)

    it("handles non-zero exit from mock", function()
      local mock_path = vim.fn.fnamemodify("tests/fixtures/mcporter/mock-mcporter.sh", ":p")

      local def = mcporter._build_tool_definition("nonexistent", {
        name = "no_tool",
        description = "test",
        inputSchema = { type = "object", properties = {} },
      }, { path = mock_path, timeout = 10 })

      local result = nil
      local ctx = {
        cwd = vim.fn.getcwd(),
        timeout = 10,
        get_config = function()
          return nil
        end,
        truncate = setmetatable({
          truncate_with_overflow = function(text, opts)
            opts.bufnr = 0
            return tools_truncate.truncate_with_overflow(text, opts)
          end,
        }, { __index = tools_truncate }),
      }

      def.execute({}, ctx, function(r)
        result = r
      end)

      vim.wait(5000, function()
        return result ~= nil
      end)
      assert.is_not_nil(result)
      assert.is_false(result.success)
    end)
  end)
end)
