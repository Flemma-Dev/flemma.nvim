package.loaded["flemma.bridge"] = nil
package.loaded["flemma.messages"] = nil
package.loaded["flemma.utilities.glob"] = nil

local bridge = require("flemma.bridge")
local roles = require("flemma.utilities.roles")
local glob = require("flemma.utilities.glob")

describe("flemma.bridge", function()
  before_each(function()
    package.loaded["flemma.bridge"] = nil
    bridge = require("flemma.bridge")
  end)

  it("raises error when calling unregistered callback", function()
    assert.has_error(function()
      bridge.send_or_execute({ bufnr = 1 })
    end)
  end)

  it("dispatches send_or_execute after registration", function()
    local called_with = nil
    bridge.register("send_or_execute", function(opts)
      called_with = opts
    end)
    bridge.send_or_execute({ bufnr = 42 })
    assert.are.same({ bufnr = 42 }, called_with)
  end)

  it("dispatches cancel_request with opts after registration", function()
    local called_opts = nil
    bridge.register("cancel_request", function(opts)
      called_opts = opts
    end)
    bridge.cancel_request({ bufnr = 99 })
    assert.are.same({ bufnr = 99 }, called_opts)
  end)

  it("dispatches update_ui after registration", function()
    local called_bufnr = nil
    bridge.register("update_ui", function(bufnr)
      called_bufnr = bufnr
    end)
    bridge.update_ui(7)
    assert.are.equal(7, called_bufnr)
  end)

  it("dispatches auto_prompt after registration", function()
    local called_bufnr = nil
    bridge.register("auto_prompt", function(bufnr)
      called_bufnr = bufnr
    end)
    bridge.auto_prompt(5)
    assert.are.equal(5, called_bufnr)
  end)
end)

describe("flemma.messages", function()
  local messages

  before_each(function()
    package.loaded["flemma.messages"] = nil
    messages = require("flemma.messages")
  end)

  describe("catalogue access", function()
    it("renders with variables via __call", function()
      local result = messages["job.executing.tracked"]{ job_id = "job_test1" }
      assert.is_string(result)
      assert.truthy(result:match("job_test1"))
      assert.truthy(result:match("flemma%.jobs%.status"))
      assert.truthy(result:match("Do not retry"))
    end)

    it("renders without variables via __call", function()
      local result = messages["job.executing.untracked"]{}
      assert.is_string(result)
      assert.truthy(result:match("Do not retry"))
      assert.is_falsy(result:match("job_id"))
    end)

    it("renders via tostring()", function()
      assert.are.equal("The tool was denied by a policy.", tostring(messages["tool.denied"]))
    end)

    it("renders via concatenation on either side", function()
      assert.are.equal("<<The tool was denied by a policy.", "<<" .. messages["tool.denied"])
      assert.are.equal("The tool was denied by a policy.>>", messages["tool.denied"] .. ">>")
    end)

    it("leaves no unrendered expressions", function()
      local result = messages["job.executing.tracked"]{ job_id = "job_expr" }
      assert.truthy(result:match("job_expr"))
      assert.is_falsy(result:match("{{"))
    end)

    it("substitutes different variables per call", function()
      local result_a = messages["job.executing.tracked"]{ job_id = "job_aaa" }
      local result_b = messages["job.executing.tracked"]{ job_id = "job_bbb" }
      assert.truthy(result_a:match("job_aaa"))
      assert.is_falsy(result_a:match("job_bbb"))
      assert.truthy(result_b:match("job_bbb"))
      assert.is_falsy(result_b:match("job_aaa"))
    end)

    it("errors for unknown catalogue keys", function()
      assert.has_error(function()
        return messages["does.not.exist"]
      end)
    end)
  end)

  describe("migration fidelity (framework strings)", function()
    it("renders the exact pre-migration strings", function()
      assert.are.equal("The tool was denied by a policy.", messages["tool.denied"]{})
      assert.are.equal("This tool has been rejected by the user.", messages["tool.rejected"]{})
      assert.are.equal(
        "User feedback: because reasons",
        messages["tool.rejected.feedback"]{ reason = "because reasons" }
      )
      assert.are.equal("User aborted tool execution.", messages["tool.aborted"]{})
      assert.are.equal("Unknown error", messages["tool.error.unknown"]{})
      assert.are.equal("Job lost: session ended before completion.", messages["job.lost"]{})
      assert.are.equal("Response interrupted by the user.", messages["request.aborted"]{})
      assert.are.equal(
        "[Output not saved: disk full. Showing the full output instead.]",
        messages["tool.output.not_saved"]{ reason = "disk full" }
      )
      assert.are.equal(
        "Running as a background job `job_x1`. Use `flemma.jobs.status` with this job ID to check progress."
          .. " Do not retry — the result will be delivered to you automatically when the job completes.",
        messages["job.executing.tracked"]{ job_id = "job_x1" }
      )
      assert.are.equal(
        "Running as a background job. Do not retry or attempt to check progress — the result will be"
          .. " delivered to you automatically when the job completes.",
        messages["job.executing.untracked"]{}
      )
    end)
  end)

  describe("migration fidelity (tool definitions)", function()
    it("registered definitions render the exact pre-migration descriptions", function()
      local expectations = {
        ["flemma.tools.definitions.builtin.bash"] = "Execute a bash command in the current working directory."
          .. " Returns stdout and stderr. Output is truncated to last 2000 lines or 50KB (whichever is hit"
          .. " first). If truncated, full output is saved to a file. $FLEMMA_TOOLS_STORE_PATH is set in the"
          .. " environment and points to a directory where saved tool results for this conversation are stored."
          .. " Optionally provide a timeout in seconds.",
        ["flemma.tools.definitions.builtin.edit"] = "Edit a file by replacing exact text. The oldText must"
          .. " match exactly (including whitespace). Use this for precise, surgical edits.",
        ["flemma.tools.definitions.builtin.read"] = "Read the contents of a file. Output is truncated to 2000"
          .. " lines or 50KB (whichever is hit first). Use offset/limit for large files. When you need the"
          .. " full file, continue with offset until complete.",
        ["flemma.tools.definitions.builtin.write"] = "Write content to a file. Creates the file if it doesn't"
          .. " exist, overwrites if it does. Automatically creates parent directories.",
        ["flemma.tools.definitions.builtin.find"] = "Find files by glob pattern. Uses fd, git ls-files, or GNU"
          .. " find (whichever is available). Output is truncated to 2000 lines or 50KB. Returns sorted"
          .. " relative paths, one per line.",
        ["flemma.tools.definitions.builtin.grep"] = "Search file contents using ripgrep (rg) or grep. Returns"
          .. " matching lines with file paths and line numbers. Output is limited to 100 matches by default."
          .. " Supports regex patterns. When using grep -E fallback, \\d, \\w, \\s are automatically"
          .. " translated to POSIX equivalents.",
        ["flemma.tools.definitions.builtin.ls"] = "List directory contents. Output is truncated to 2000 lines"
          .. " or 50KB. Directories appear first (suffixed with /), then files, both sorted case-insensitively."
          .. " Use max_depth > 1 to recurse into subdirectories (max 10). Use limit to cap the number of"
          .. " entries (default 500).",
        ["flemma.tools.definitions.harness.jobs"] = 'Check the status of a background job. Returns "running"'
          .. ' while the job is executing, "completed (delivery pending)" once it has finished and its result'
          .. " is queued to be injected into the conversation automatically (do not re-run the tool or keep"
          .. ' polling — the result is on its way), or "completed" when the result is already in the'
          .. " conversation. Use this to check on long-running background tasks instead of retrying them.",
      }
      for module_path, expected in pairs(expectations) do
        package.loaded[module_path] = nil
        local module = require(module_path)
        assert.are.equal(expected, module.definitions[1].description, module_path)
      end
    end)
  end)
end)

describe("messages brace-call formatter", function()
  -- Exercises contrib/scripts/format-messages-brace-call.sh, the post-stylua
  -- step that rewrites `messages["key"]({ ... })` to the brace-call house style
  -- `messages["key"]{ ... }`. `f{ ... }` and `f({ ... })` are equivalent Lua, so
  -- the rewrite is cosmetic — the point is that it strips *only* the call
  -- parentheses of a `messages[<string>]` index, tracks paren depth so nested
  -- parentheses survive, and touches nothing else (bare refs, strings, comments,
  -- unrelated calls).
  local formatter = (vim.env.PROJECT_ROOT or vim.fn.getcwd()) .. "/contrib/scripts/format-messages-brace-call.sh"

  local function write_temp(content)
    local path = vim.fn.tempname() .. ".lua"
    local file = assert(io.open(path, "w"))
    file:write(content)
    file:close()
    return path
  end

  local function read_all(path)
    local file = assert(io.open(path, "r"))
    local content = file:read("*a")
    file:close()
    return content
  end

  local function run_formatter(path)
    local result = vim.system({ "bash", formatter, path }, { text = true }):wait()
    assert.are.equal(0, result.code, "formatter exited non-zero: " .. (result.stderr or ""))
  end

  --- Format `source`, assert it becomes `expected`, then format again and
  --- assert the second pass changes nothing (every rewrite must be idempotent).
  local function assert_transforms(source, expected)
    local path = write_temp(source)
    run_formatter(path)
    assert.are.equal(expected, read_all(path), "first pass produced the wrong output")
    run_formatter(path)
    assert.are.equal(expected, read_all(path), "second pass was not idempotent")
  end

  it("strips the parens around an empty-table call", function()
    assert_transforms('local a = messages["job.lost"]({})\n', 'local a = messages["job.lost"]{}\n')
  end)

  it("strips the parens around a single-line table with a variable", function()
    assert_transforms(
      'local b = messages["job.executing.tracked"]({ job_id = id })\n',
      'local b = messages["job.executing.tracked"]{ job_id = id }\n'
    )
  end)

  it("preserves the body of a multi-line table", function()
    local source = table.concat({
      'local c = messages["tool.read.description"]({',
      "  max_lines = 2000,",
      "  max_bytes = 100,",
      "})",
      "",
    }, "\n")
    local expected = table.concat({
      'local c = messages["tool.read.description"]{',
      "  max_lines = 2000,",
      "  max_bytes = 100,",
      "}",
      "",
    }, "\n")
    assert_transforms(source, expected)
  end)

  it("strips only the outer paren when the table nests a parenthesized call", function()
    assert_transforms(
      'local d = messages["tool.bash.description"]({ max_bytes_kb = math.floor(truncate.MAX_BYTES / 1024) })\n',
      'local d = messages["tool.bash.description"]{ max_bytes_kb = math.floor(truncate.MAX_BYTES / 1024) }\n'
    )
  end)

  it("strips only the messages paren when the whole call nests inside another call", function()
    assert_transforms(
      'local e = s.number():nullable():describe(messages["tool.find.input.limit"]({ default_limit = LIMIT }))\n',
      'local e = s.number():nullable():describe(messages["tool.find.input.limit"]{ default_limit = LIMIT })\n'
    )
  end)

  it("leaves a bare (uncalled) proxy reference untouched", function()
    local source = table.concat({
      'local bare = messages["tool.denied"]',
      'local desc = schema:describe(messages["tool.denied"])',
      "",
    }, "\n")
    assert_transforms(source, source)
  end)

  it("leaves messages references inside comments and strings untouched", function()
    local source = table.concat({
      '-- messages["tool.denied"]({ reason = x }) stays put in a comment',
      [[local literal = 'messages["job.lost"]({})']],
      "",
    }, "\n")
    assert_transforms(source, source)
  end)

  it("leaves unrelated single-table calls untouched", function()
    assert_transforms("bridge.send_or_execute({ bufnr = 1 })\n", "bridge.send_or_execute({ bufnr = 1 })\n")
  end)
end)

describe("utilities.tools", function()
  local tool_names

  before_each(function()
    package.loaded["flemma.utilities.tools"] = nil
    tool_names = require("flemma.utilities.tools")
  end)

  describe("encode_tool_name", function()
    it("replaces dot with wire separator", function()
      assert.equals("slack__channels_list", tool_names.encode_tool_name("slack.channels_list"))
    end)

    it("handles multiple dots", function()
      assert.equals("server__group__tool", tool_names.encode_tool_name("server.group.tool"))
    end)

    it("passes through names without dots", function()
      assert.equals("bash", tool_names.encode_tool_name("bash"))
    end)

    it("passes through empty string", function()
      assert.equals("", tool_names.encode_tool_name(""))
    end)
  end)

  describe("decode_tool_name", function()
    it("replaces wire separator with dot", function()
      assert.equals("slack.channels_list", tool_names.decode_tool_name("slack__channels_list"))
    end)

    it("handles multiple wire separators", function()
      assert.equals("server.group.tool", tool_names.decode_tool_name("server__group__tool"))
    end)

    it("passes through names without wire separator", function()
      assert.equals("bash", tool_names.decode_tool_name("bash"))
    end)

    it("passes through empty string", function()
      assert.equals("", tool_names.decode_tool_name(""))
    end)
  end)

  describe("round-trip", function()
    it("encode then decode returns original", function()
      local original = "slack.channels_list"
      assert.equals(original, tool_names.decode_tool_name(tool_names.encode_tool_name(original)))
    end)

    it("decode then encode returns original", function()
      local wire = "slack__channels_list"
      assert.equals(wire, tool_names.encode_tool_name(tool_names.decode_tool_name(wire)))
    end)
  end)
end)

describe("flemma.utilities.roles", function()
  describe("constants", function()
    it("exposes buffer-format role names", function()
      assert.equals("You", roles.YOU)
      assert.equals("Assistant", roles.ASSISTANT)
      assert.equals("System", roles.SYSTEM)
    end)
  end)

  describe("to_key()", function()
    it("maps 'You' to 'user'", function()
      assert.equals("user", roles.to_key("You"))
    end)

    it("maps 'Assistant' to 'assistant'", function()
      assert.equals("assistant", roles.to_key("Assistant"))
    end)

    it("maps 'System' to 'system'", function()
      assert.equals("system", roles.to_key("System"))
    end)

    it("lowercases unknown roles as fallback", function()
      assert.equals("custom", roles.to_key("Custom"))
    end)
  end)

  describe("is_user()", function()
    it("returns true for 'You'", function()
      assert.is_true(roles.is_user("You"))
    end)

    it("returns false for 'Assistant'", function()
      assert.is_false(roles.is_user("Assistant"))
    end)

    it("returns false for 'System'", function()
      assert.is_false(roles.is_user("System"))
    end)
  end)

  describe("capitalize()", function()
    it("capitalizes 'user' to 'User'", function()
      assert.equals("User", roles.capitalize("user"))
    end)

    it("capitalizes 'assistant' to 'Assistant'", function()
      assert.equals("Assistant", roles.capitalize("assistant"))
    end)

    it("capitalizes single character", function()
      assert.equals("A", roles.capitalize("a"))
    end)
  end)

  describe("highlight_group()", function()
    it("builds FlemmaRoleUser from prefix and 'You'", function()
      assert.equals("FlemmaRoleUser", roles.highlight_group("FlemmaRole", "You"))
    end)

    it("builds FlemmaLineAssistant from prefix and 'Assistant'", function()
      assert.equals("FlemmaLineAssistant", roles.highlight_group("FlemmaLine", "Assistant"))
    end)

    it("builds FlemmaRulerSystem from prefix and 'System'", function()
      assert.equals("FlemmaRulerSystem", roles.highlight_group("FlemmaRuler", "System"))
    end)

    it("builds FlemmaUser from 'Flemma' prefix and 'You'", function()
      assert.equals("FlemmaUser", roles.highlight_group("Flemma", "You"))
    end)
  end)
end)

describe("flemma.templating.renderer", function()
  local renderer

  before_each(function()
    package.loaded["flemma.templating.renderer"] = nil
    renderer = require("flemma.templating.renderer")
  end)

  local function render_text(template, env)
    return renderer.parts_to_text(renderer.render(template, env))
  end

  describe("template rendering", function()
    it("renders expression variables", function()
      assert.are.equal("hello", render_text("{{ greeting }}", { greeting = "hello" }))
    end)

    it("renders code block conditionals", function()
      local template = "{% if active then %}yes{% else %}no{% end %}"
      assert.are.equal("yes", render_text(template, { active = true }))
      assert.are.equal("no", render_text(template, { active = false }))
    end)

    it("supports whitespace trimming for multiline strings", function()
      local template = [[
{{ model.name }}
{%- if thinking.enabled then %} ({{ thinking.level }}){% end -%}
]]
      local env = {
        model = { name = "claude-sonnet-4-5" },
        thinking = { enabled = true, level = "high" },
      }
      assert.are.equal("claude-sonnet-4-5 (high)", render_text(template, env))
    end)
  end)

  describe("lazy evaluation and explicit compilation", function()
    it("only resolves accessed nested values", function()
      local token_accesses = 0
      local env = {
        model = { name = "o3" },
        buffer = {
          tokens = setmetatable({}, {
            __index = function(_, key)
              if key == "input" then
                token_accesses = token_accesses + 1
                return 123
              end
              return nil
            end,
          }),
        },
      }

      assert.are.equal("o3", render_text("{{ model.name }}", env))
      assert.are.equal(0, token_accesses)
    end)

    it("returns reusable render functions without global caching", function()
      local render = renderer.compile("{{ value }}")

      assert.are.equal("one", renderer.parts_to_text(render({ value = "one" })))
      assert.are.equal("two", renderer.parts_to_text(render({ value = "two" })))
    end)
  end)
end)

describe("flemma.templating.builtins.format", function()
  local format

  before_each(function()
    package.loaded["flemma.templating.builtins.format"] = nil
    format = require("flemma.templating.builtins.format")
  end)

  it("exports display formatting functions", function()
    assert.are.equal("12,345", format.exports.number(12345))
    assert.are.equal("15K", format.exports.tokens(15000))
    assert.are.equal("$0.375", format.exports.money(0.375))
    assert.are.equal("17%", format.exports.percent(0.17, 0))
    assert.are.equal("17.3%", format.exports.percent(0.1734, 1))
  end)

  it("populates the template environment as format", function()
    local env = {}
    format.populate(env)

    assert.are.equal(format.exports, env.format)
  end)
end)

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
