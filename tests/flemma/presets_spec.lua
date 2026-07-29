local notify = require("flemma.notify")
local presets = require("flemma.presets")

local function flush_schedule()
  vim.wait(10, function()
    return false
  end)
end

describe("flemma.presets", function()
  local notifications = {}

  before_each(function()
    notifications = {}
    notify._set_impl(function(notification)
      table.insert(notifications, notification)
      return notification
    end)
    presets.clear()
  end)

  after_each(function()
    notify._reset_impl()
    presets.clear()
  end)

  describe("setup()", function()
    it("registers built-in presets when called with nil", function()
      presets.setup(nil)
      assert.is_not_nil(presets.get("$standard"))
      assert.is_not_nil(presets.get("$readonly"))
    end)

    it("built-in $standard approves read, write, edit, find, grep, ls, flemma:*", function()
      presets.setup(nil)
      local preset = presets.get("$standard")
      local approve = vim.deepcopy(preset.auto_approve)
      table.sort(approve)
      assert.are.same({ "edit", "find", "flemma.*", "grep", "ls", "read", "write" }, approve)
    end)

    it("built-in $readonly approves read, find, grep, ls", function()
      presets.setup(nil)
      local preset = presets.get("$readonly")
      local approve = vim.deepcopy(preset.auto_approve)
      table.sort(approve)
      assert.are.same({ "find", "grep", "ls", "read" }, approve)
    end)

    it("built-in presets have no provider or model", function()
      presets.setup(nil)
      local standard = presets.get("$standard")
      local readonly = presets.get("$readonly")
      assert.is_nil(standard.provider)
      assert.is_nil(standard.model)
      assert.is_nil(readonly.provider)
      assert.is_nil(readonly.model)
    end)

    it("user presets override built-ins by name", function()
      presets.setup({ ["$standard"] = { auto_approve = { "bash" } } })
      local preset = presets.get("$standard")
      assert.are.same({ "bash" }, preset.auto_approve)
    end)

    it("user presets are added alongside built-ins", function()
      presets.setup({ ["$yolo"] = { auto_approve = { "bash" } } })
      assert.is_not_nil(presets.get("$yolo"))
      assert.is_not_nil(presets.get("$standard"))
      assert.is_not_nil(presets.get("$readonly"))
    end)
  end)

  it("normalizes table definitions into provider, model, and parameters", function()
    presets.setup({
      ["$o3"] = {
        provider = "openai",
        model = "o3",
        temperature = 1,
        reasoning = "high",
      },
    })

    local preset = presets.get("$o3")
    assert.is_not_nil(preset, "preset should be available after setup")
    assert.are.equal("openai", preset.provider)
    assert.are.equal("o3", preset.model)
    -- General keys stay flat; provider-specific keys nest under the provider
    -- (preset.parameters is isomorphic to config.parameters).
    assert.are.same({
      temperature = 1,
      openai = { reasoning = "high" },
    }, preset.parameters)
  end)

  it("parses string definitions using modeline parsing", function()
    presets.setup({
      ["$gemini"] = "vertex gemini-2.5-pro project_id=demo",
    })

    local preset = presets.get("$gemini")
    assert.is_not_nil(preset, "string-based preset should be parsed")
    assert.are.equal("vertex", preset.provider)
    assert.are.equal("gemini-2.5-pro", preset.model)
    assert.are.same({
      vertex = { project_id = "demo" },
    }, preset.parameters)
  end)

  it("supports positional provider/model tables", function()
    presets.setup({
      ["$o3"] = { "openai", "o3", temperature = 1 },
    })

    local preset = presets.get("$o3")
    assert.is_not_nil(preset, "positional preset table should be parsed")
    assert.are.equal("openai", preset.provider)
    assert.are.equal("o3", preset.model)
    assert.are.same({
      temperature = 1,
    }, preset.parameters)
  end)

  it("supports keyed provider/model tables", function()
    presets.setup({
      ["$o4"] = {
        provider = "openai",
        model = "o4",
        temperature = 0.5,
      },
    })

    local preset = presets.get("$o4")
    assert.is_not_nil(preset, "keyed preset table should be parsed")
    assert.are.equal("openai", preset.provider)
    assert.are.equal("o4", preset.model)
    assert.are.same({
      temperature = 0.5,
    }, preset.parameters)
  end)

  it("splits provider/model in a table-form preset model", function()
    presets.setup({ ["$g"] = { model = "vertex/gemini-3.1-pro-preview" } })
    local preset = presets.get("$g")
    assert.equals("vertex", preset.provider)
    assert.equals("gemini-3.1-pro-preview", preset.model)
  end)

  it("decomposes matrix parameters from a table-form preset model", function()
    presets.setup({ ["$kimi"] = { model = "moonshot/kimi-k2.6;opt=value" } })
    local preset = presets.get("$kimi")
    assert.equals("moonshot", preset.provider)
    assert.equals("kimi-k2.6", preset.model)
    assert.are.same({ moonshot = { opt = "value" } }, preset.parameters)
  end)

  it("accepts slash-form string presets", function()
    presets.setup({ ["$kimi"] = "moonshot/kimi-k2.6;opt=value" })
    local preset = presets.get("$kimi")
    assert.equals("moonshot", preset.provider)
    assert.equals("kimi-k2.6", preset.model)
    assert.are.same({ moonshot = { opt = "value" } }, preset.parameters)
  end)

  it("scopes matrix parameters off an explicit provider field", function()
    presets.setup({ ["$kimi"] = { provider = "moonshot", model = "kimi-k2.6;opt=value" } })
    local preset = presets.get("$kimi")
    assert.are.same({ moonshot = { opt = "value" } }, preset.parameters)
  end)

  it("rejects a model provider that conflicts with the provider field", function()
    presets.setup({ ["$bad"] = { provider = "openai", model = "moonshot/kimi-k2.6" } })
    assert.is_nil(presets.get("$bad"))
    flush_schedule()
    assert.is_true(#notifications > 0)
  end)

  it("drops matrix parameters when no provider is resolvable", function()
    presets.setup({ ["$loose"] = { model = "kimi-k2.6;opt=value" } })
    local preset = presets.get("$loose")
    assert.equals("kimi-k2.6", preset.model)
    assert.are.same({}, preset.parameters)
    flush_schedule()
    assert.is_true(#notifications > 0)
  end)

  it("nests provider-specific space parameters under the provider", function()
    presets.setup({ ["$k"] = "moonshot kimi-k2.6 opt=1 max_tokens=100" })
    local preset = presets.get("$k")
    assert.are.same({ max_tokens = 100, moonshot = { opt = 1 } }, preset.parameters)
  end)

  it("merges space and matrix parameters into one provider namespace", function()
    presets.setup({ ["$k"] = "moonshot/kimi-k2.6;opt=1 other=2" })
    local preset = presets.get("$k")
    assert.are.same({ moonshot = { opt = 1, other = 2 } }, preset.parameters)
  end)

  describe("route_parameters()", function()
    local function fake_writer()
      return { parameters = {} }
    end

    it("writes a provider-bearing preset's config-shaped parameters structurally", function()
      presets.setup({ ["$kimi"] = { provider = "moonshot", model = "kimi-k2.6;opt=value" } })
      local writer = fake_writer()
      local overrides = presets.route_parameters(presets.get("$kimi"), writer)
      assert.are.same({ moonshot = { opt = "value" } }, writer.parameters)
      assert.are.same({}, overrides)
    end)

    it("returns a provider-less preset's flat parameters for the explicit channel", function()
      presets.setup({ ["$tweak"] = { temperature = 0.5, custom_knob = 7 } })
      local writer = fake_writer()
      local overrides = presets.route_parameters(presets.get("$tweak"), writer)
      assert.are.same({}, writer.parameters)
      assert.are.same({ temperature = 0.5, custom_knob = 7 }, overrides)
    end)

    it("returns a fresh copy the caller can mutate without touching the preset", function()
      presets.setup({ ["$tweak"] = { temperature = 0.5 } })
      local preset = presets.get("$tweak")
      local overrides = presets.route_parameters(preset, fake_writer())
      overrides.temperature = 0.9
      assert.equals(0.5, preset.parameters.temperature)
    end)

    it("is a no-op returning {} when the preset has no parameters", function()
      presets.setup({ ["$plain"] = { provider = "openai", model = "o3" } })
      local writer = fake_writer()
      local overrides = presets.route_parameters(presets.get("$plain"), writer)
      assert.are.same({}, writer.parameters)
      assert.are.same({}, overrides)
    end)
  end)

  it("keeps parameters flat when the preset has no provider", function()
    presets.setup({ ["$tweak"] = { temperature = 0.5, custom_knob = 7 } })
    local preset = presets.get("$tweak")
    assert.are.same({ temperature = 0.5, custom_knob = 7 }, preset.parameters)
  end)

  it("warns about ignored matrix segments in a preset model", function()
    presets.setup({ ["$weird"] = { model = "moonshot/kimi-k2.6;api-key=1" } })
    local preset = presets.get("$weird")
    assert.are.same({}, preset.parameters)
    flush_schedule()
    assert.is_true(#notifications > 0)
  end)

  it("supports auto_approve in strict table format", function()
    presets.setup({
      ["$explore"] = {
        provider = "openai",
        model = "gpt-4o-mini",
        auto_approve = { "read", "write", "edit", "bash" },
      },
    })

    local preset = presets.get("$explore")
    assert.is_not_nil(preset, "preset with auto_approve should be available")
    assert.are.equal("openai", preset.provider)
    assert.are.equal("gpt-4o-mini", preset.model)
    assert.are.same({ "read", "write", "edit", "bash" }, preset.auto_approve)
  end)

  it("does not include auto_approve in parameters", function()
    presets.setup({
      ["$explore"] = {
        provider = "openai",
        model = "gpt-4o-mini",
        auto_approve = { "read", "bash" },
      },
    })

    local preset = presets.get("$explore")
    assert.is_nil(preset.parameters.auto_approve)
  end)

  it("ignores auto_approve in string definitions", function()
    presets.setup({
      ["$gemini"] = "vertex gemini-2.5-pro project_id=demo",
    })

    local preset = presets.get("$gemini")
    assert.is_nil(preset.auto_approve)
  end)

  it("ignores auto_approve in positional table definitions", function()
    presets.setup({
      ["$o3"] = { "openai", "o3", temperature = 1 },
    })

    local preset = presets.get("$o3")
    assert.is_nil(preset.auto_approve)
  end)

  it("allows approval-only presets without provider", function()
    presets.setup({
      ["$safe"] = { auto_approve = { "read" } },
    })

    local preset = presets.get("$safe")
    assert.is_not_nil(preset)
    assert.is_nil(preset.provider)
    assert.is_nil(preset.model)
    assert.are.same({ "read" }, preset.auto_approve)
  end)

  it("rejects auto_approve that is not a table", function()
    presets.setup({
      ["$bad"] = { provider = "openai", auto_approve = "read" },
    })

    assert.is_nil(presets.get("$bad"))

    flush_schedule()
    local found = false
    for _, note in ipairs(notifications) do
      if note.message:find("auto_approve must be a string") then
        found = true
        break
      end
    end
    assert.is_true(found, "expected warning about invalid auto_approve")
  end)

  it("rejects string definitions that use assignments for provider/model", function()
    presets.setup({
      ["$bad"] = "provider=vertex model=gemini-2.5-pro",
    })

    assert.is_nil(presets.get("$bad"))

    flush_schedule()
    local found = false
    for _, note in ipairs(notifications) do
      if note.message:find("string definitions must start") then
        found = true
        break
      end
    end
    assert.is_true(found, "expected warning about invalid string preset definition")
  end)

  it("supports tools in strict table format", function()
    presets.setup({
      ["$blank"] = { tools = {} },
    })
    local preset = presets.get("$blank")
    assert.is_not_nil(preset)
    assert.are.same({}, preset.tools)
  end)

  it("stores tools with op prefixes as-is", function()
    presets.setup({
      ["$basics"] = { tools = { "!bash" } },
    })
    local preset = presets.get("$basics")
    assert.are.same({ "!bash" }, preset.tools)
  end)

  it("does not include tools in parameters", function()
    presets.setup({
      ["$custom"] = { provider = "openai", model = "o3", tools = { "read" } },
    })
    local preset = presets.get("$custom")
    assert.is_nil(preset.parameters.tools)
  end)

  it("allows presets with both tools and auto_approve", function()
    presets.setup({
      ["$safe"] = { tools = { "!bash" }, auto_approve = { "read" } },
    })
    local preset = presets.get("$safe")
    assert.are.same({ "!bash" }, preset.tools)
    assert.are.same({ "read" }, preset.auto_approve)
  end)

  it("rejects tools that is not a table", function()
    presets.setup({ ["$bad"] = { tools = "bash" } })
    assert.is_nil(presets.get("$bad"))
  end)

  it("rejects preset names that don't start with $lowercase", function()
    presets.setup({
      ["$MyPreset"] = { provider = "openai", model = "gpt-4o" },
      ["$123"] = { provider = "openai", model = "gpt-4o" },
    })

    assert.is_nil(presets.get("$MyPreset"))
    assert.is_nil(presets.get("$123"))

    flush_schedule()
    local found_warning = false
    for _, note in ipairs(notifications) do
      if note.message:find("lowercase") then
        found_warning = true
        break
      end
    end
    assert.is_true(found_warning, "expected warning about lowercase convention")
  end)

  it("ignores unknown fields on preset definitions (passthrough format)", function()
    presets.setup({
      ["$custom"] = { provider = "openai", model = "o3", deny = { "write" } },
    })
    local preset = presets.get("$custom")
    assert.is_not_nil(preset)
    assert.are.equal("openai", preset.provider)
    -- deny is not a known preset field — it falls into parameters via passthrough
    assert.is_nil(preset.auto_approve)
  end)

  it("clears all presets including built-ins", function()
    presets.setup(nil)
    assert.is_not_nil(presets.get("$standard"))
    presets.clear()
    assert.is_nil(presets.get("$standard"))
    assert.are.same({}, presets.list())
  end)

  it("silently ignores presets without a leading '$'", function()
    presets.setup({
      gemini = { provider = "vertex" },
    })

    assert.is_nil(presets.get("gemini"))
  end)

  it("lists preset names in sorted order including built-ins", function()
    presets.setup({
      ["$beta"] = { provider = "openai" },
      ["$alpha"] = { provider = "vertex" },
    })

    local names = presets.list()
    assert.are.same({ "$alpha", "$beta", "$readonly", "$standard" }, names)
  end)

  it("returns a deep copy from get()", function()
    presets.setup(nil)
    local a = presets.get("$standard")
    local b = presets.get("$standard")
    assert.are.same(a, b)
    table.insert(a.auto_approve, "bash")
    assert.are_not.same(a, presets.get("$standard"))
  end)

  describe("finalize()", function()
    it("warns when auto_approve references an unknown tool name", function()
      package.loaded["flemma.tools.registry"] = nil
      local tools_registry = require("flemma.tools.registry")
      tools_registry.clear()
      tools_registry.register("read", {
        name = "read",
        description = "Read files",
        input_schema = { type = "object" },
      })

      presets.setup({
        ["$custom"] = { auto_approve = { "read", "nonexistent_tool" } },
      })
      presets.finalize()

      flush_schedule()
      local found = false
      for _, note in ipairs(notifications) do
        if note.message:find("unknown tool 'nonexistent_tool'") then
          found = true
          break
        end
      end
      assert.is_true(found, "expected warning about unknown tool in auto_approve")
    end)

    it("does not warn for known tool names", function()
      package.loaded["flemma.tools.registry"] = nil
      local tools_registry = require("flemma.tools.registry")
      tools_registry.clear()
      tools_registry.register("read", {
        name = "read",
        description = "Read files",
        input_schema = { type = "object" },
      })
      tools_registry.register("write", {
        name = "write",
        description = "Write files",
        input_schema = { type = "object" },
      })

      presets.setup({
        ["$custom"] = { auto_approve = { "read", "write" } },
      })
      presets.finalize()

      flush_schedule()
      local found = false
      for _, note in ipairs(notifications) do
        if note.message:find("unknown tool") then
          found = true
          break
        end
      end
      assert.is_false(found, "should not warn when all tools are known")
    end)

    it("strips op prefixes before tool registry lookup", function()
      package.loaded["flemma.tools.registry"] = nil
      local tools_registry = require("flemma.tools.registry")
      tools_registry.clear()
      tools_registry.register("bash", {
        name = "bash",
        description = "Run bash",
        input_schema = { type = "object" },
      })
      tools_registry.register("read", {
        name = "read",
        description = "Read files",
        input_schema = { type = "object" },
      })

      presets.setup({
        ["$safe"] = {
          auto_approve = { "+read", "!bash" },
          tools = { "^read", "!bash" },
        },
      })
      presets.finalize()

      flush_schedule()
      local found_unknown = false
      for _, note in ipairs(notifications) do
        if note.message:find("unknown tool") then
          found_unknown = true
          break
        end
      end
      assert.is_false(found_unknown, "should not warn for known tools behind op prefixes")
    end)

    it("skips $-prefixed entries in finalize validation", function()
      package.loaded["flemma.tools.registry"] = nil
      local tools_registry = require("flemma.tools.registry")
      tools_registry.clear()

      presets.setup({
        ["$composed"] = { tools = { "$standard", "!bash" } },
      })
      presets.finalize()

      flush_schedule()
      local found_standard_warning = false
      for _, note in ipairs(notifications) do
        if note.message:find("'%$standard'") then
          found_standard_warning = true
          break
        end
      end
      assert.is_false(found_standard_warning, "should skip $-prefixed entries, not validate them as tool names")
    end)
  end)

  describe("resolve_default", function()
    it("returns nil for non-preset model fields", function()
      presets.setup(nil)
      local preset, err = presets.resolve_default("gpt-4o", nil)
      assert.is_nil(preset)
      assert.is_nil(err)
    end)

    it("returns nil for nil model field", function()
      presets.setup(nil)
      local preset, err = presets.resolve_default(nil, nil)
      assert.is_nil(preset)
      assert.is_nil(err)
    end)

    it("resolves a known preset", function()
      presets.setup({
        ["$fast"] = { provider = "openai", model = "gpt-4o" },
      })

      local preset, err = presets.resolve_default("$fast", nil)
      assert.is_nil(err)
      assert.is_not_nil(preset)
      assert.are.equal("openai", preset.provider)
      assert.are.equal("gpt-4o", preset.model)
    end)

    it("returns error for unknown preset", function()
      presets.setup(nil)
      local preset, err = presets.resolve_default("$missing", nil)
      assert.is_nil(preset)
      assert.is_not_nil(err)
      assert.truthy(err:find("not found"))
    end)

    it("returns error when explicit provider conflicts with preset", function()
      presets.setup({
        ["$fast"] = { provider = "openai", model = "gpt-4o" },
      })

      local preset, err = presets.resolve_default("$fast", "anthropic")
      assert.is_nil(preset)
      assert.is_not_nil(err)
      assert.truthy(err:find("conflicts"))
    end)

    it("succeeds when explicit provider matches preset", function()
      presets.setup({
        ["$fast"] = { provider = "openai", model = "gpt-4o" },
      })

      local preset, err = presets.resolve_default("$fast", "openai")
      assert.is_nil(err)
      assert.is_not_nil(preset)
      assert.are.equal("openai", preset.provider)
    end)

    it("skips conflict check for approval-only presets", function()
      presets.setup(nil)
      -- $standard has no provider, so conflict check is skipped
      local preset, err = presets.resolve_default("$standard", "anthropic")
      assert.is_nil(err)
      assert.is_not_nil(preset)
    end)
  end)
end)

describe(":Flemma switch completion ordering", function()
  local notifications = {}
  local stub_core

  local modules_to_reset = {
    "flemma",
    "flemma.commands",
    "flemma.core",
    "flemma.keymaps",
    "flemma.highlight",
    "flemma.ui",
  }

  local function reset_commands()
    local commands = vim.api.nvim_get_commands({ builtin = false })
    for name, _ in pairs(commands) do
      if name:match("^Flemma") then
        pcall(vim.api.nvim_del_user_command, name)
      end
    end
  end

  local function reset_modules()
    for _, name in ipairs(modules_to_reset) do
      package.loaded[name] = nil
    end
  end

  before_each(function()
    notifications = {}
    notify._set_impl(function(notification)
      table.insert(notifications, notification)
      return notification
    end)
    presets.clear()
    reset_commands()
    reset_modules()

    stub_core = {
      initialize_provider = function() end,
      send_to_provider = function() end,
      cancel_request = function() end,
      setup = function() end,
    }

    package.preload["flemma.core"] = function()
      return stub_core
    end
  end)

  after_each(function()
    notify._reset_impl()
    presets.clear()
    reset_commands()
    reset_modules()
    package.preload["flemma.core"] = nil
    package.loaded["flemma.core"] = nil
    require("flemma.config").init(require("flemma.config.schema"))
    stub_core = nil
  end)

  it("lists presets first and providers afterwards when completing the provider argument", function()
    local flemma = require("flemma")
    flemma.setup({
      presets = {
        ["$zulu"] = { provider = "vertex" },
        ["$alpha"] = { provider = "openai" },
      },
    })

    local completions = vim.fn.getcompletion("Flemma switch ", "cmdline")

    -- Only presets with a provider appear; $readonly/$standard are approval-only
    assert.are.same({
      "$alpha",
      "$zulu",
      "anthropic",
      "moonshot",
      "openai",
      "vertex",
    }, completions, "completion order should list switchable presets first followed by providers")
  end)
end)

describe(":Flemma switch with presets", function()
  local notifications = {}
  local stub_core

  local modules_to_reset = {
    "flemma",
    "flemma.commands",
    "flemma.core",
    "flemma.keymaps",
    "flemma.highlight",
    "flemma.ui",
  }

  local function reset_commands()
    local commands = vim.api.nvim_get_commands({ builtin = false })
    for name, _ in pairs(commands) do
      if name:match("^Flemma") then
        pcall(vim.api.nvim_del_user_command, name)
      end
    end
  end

  local function reset_modules()
    for _, name in ipairs(modules_to_reset) do
      package.loaded[name] = nil
    end
  end

  before_each(function()
    notifications = {}
    notify._set_impl(function(notification)
      table.insert(notifications, notification)
      return notification
    end)
    presets.clear()
    reset_commands()
    reset_modules()

    stub_core = {
      last_switch = nil,
      initialize_provider = function() end,
      send_to_provider = function() end,
      cancel_request = function() end,
      setup = function() end,
    }
    function stub_core.switch_provider(provider, model, parameters)
      stub_core.last_switch = {
        provider = provider,
        model = model,
        parameters = parameters,
      }
    end

    package.preload["flemma.core"] = function()
      return stub_core
    end
  end)

  after_each(function()
    notify._reset_impl()
    presets.clear()
    reset_commands()
    reset_modules()
    package.preload["flemma.core"] = nil
    package.loaded["flemma.core"] = nil
    require("flemma.config").init(require("flemma.config.schema"))
    stub_core = nil
  end)

  it("expands preset definitions into provider, model, and structural parameter writes", function()
    local flemma = require("flemma")
    flemma.setup({
      presets = {
        ["$o3"] = {
          provider = "openai",
          model = "o3",
          reasoning = "high",
          temperature = 1,
        },
      },
    })

    vim.cmd("Flemma switch $o3")

    assert.is_not_nil(stub_core.last_switch, "switch should be invoked for preset")
    assert.are.equal("openai", stub_core.last_switch.provider)
    assert.are.equal("o3", stub_core.last_switch.model)
    -- Preset parameters no longer travel through the switch-arguments
    -- channel — they are written structurally to the store before the
    -- switch, so command-line overrides win on store order.
    assert.are.same({}, stub_core.last_switch.parameters)
    local resolved = require("flemma.config").materialize()
    assert.equals(1, resolved.parameters.temperature)
    assert.equals("high", resolved.parameters.openai.reasoning)
  end)

  it("allows overriding preset model and parameters", function()
    local flemma = require("flemma")
    flemma.setup({
      presets = {
        ["$o3"] = {
          provider = "openai",
          model = "o3",
          temperature = 1,
        },
      },
    })

    vim.cmd("Flemma switch $o3 gpt-4o temperature=0.25")

    assert.is_not_nil(stub_core.last_switch, "switch should be invoked for preset override")
    assert.are.equal("openai", stub_core.last_switch.provider)
    assert.are.equal("gpt-4o", stub_core.last_switch.model)
    assert.are.same({
      temperature = 0.25,
    }, stub_core.last_switch.parameters)
  end)

  it("writes auto_approve to RUNTIME layer when preset has it", function()
    local flemma = require("flemma")
    flemma.setup({
      presets = {
        ["$explore"] = {
          provider = "openai",
          model = "gpt-4o-mini",
          auto_approve = { "read", "write", "edit", "bash" },
        },
      },
    })

    vim.cmd("Flemma switch $explore")

    local config_facade = require("flemma.config")
    local resolved = config_facade.inspect(nil, "tools.auto_approve")
    assert.is_not_nil(resolved, "auto_approve should be set after switch")
    local approve = resolved.value
    assert.is_table(approve)
    assert.truthy(vim.tbl_contains(approve, "bash"), "bash should be in auto_approve after switch")
  end)

  it("does not write auto_approve when preset lacks it", function()
    local flemma = require("flemma")
    flemma.setup({
      presets = {
        ["$fast"] = {
          provider = "openai",
          model = "gpt-4o",
        },
      },
    })

    -- Capture the auto_approve state before switch
    local config_facade = require("flemma.config")
    local before = config_facade.inspect(nil, "tools.auto_approve")

    vim.cmd("Flemma switch $fast")

    local after = config_facade.inspect(nil, "tools.auto_approve")
    assert.are.same(before.value, after.value, "auto_approve should not change for provider-only preset")
  end)

  it("notifies when a preset is unknown", function()
    local flemma = require("flemma")
    flemma.setup({
      presets = {},
    })

    vim.cmd("Flemma switch $missing")

    assert.is_nil(stub_core.last_switch, "switch should not run for unknown preset")

    flush_schedule()
    local found = false
    for _, note in ipairs(notifications) do
      if note.message:find("Unknown preset") then
        found = true
        break
      end
    end
    assert.is_true(found, "expected warning about unknown preset")
  end)

  it("writes tools with remove ops to RUNTIME layer", function()
    local flemma = require("flemma")
    flemma.setup({
      presets = {
        ["$nobash"] = { tools = { "!bash" } },
      },
    })

    vim.cmd("Flemma switch $nobash")

    local config_facade = require("flemma.config")
    local store = require("flemma.config.store")
    local ops = store.dump_layer(config_facade.LAYERS.RUNTIME)
    local remove_ops = vim.tbl_filter(function(op)
      return op.op == "remove" and op.path == "tools" and op.value == "bash"
    end, ops)
    assert.are.equal(1, #remove_ops, "should record a remove op for bash on the tools path")
  end)

  it("writes empty tools set to RUNTIME layer", function()
    local flemma = require("flemma")
    flemma.setup({
      presets = {
        ["$blank"] = { tools = {} },
      },
    })

    vim.cmd("Flemma switch $blank")

    local config_facade = require("flemma.config")
    local store = require("flemma.config.store")
    local ops = store.dump_layer(config_facade.LAYERS.RUNTIME)
    local set_ops = vim.tbl_filter(function(op)
      return op.op == "set" and op.path == "tools"
    end, ops)
    assert.are.equal(1, #set_ops, "should record a set op for empty tools list")
    assert.are.same({}, set_ops[1].value)
  end)
end)
