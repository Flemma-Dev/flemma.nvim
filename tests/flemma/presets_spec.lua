local presets = require("flemma.presets")

local function collect_notification(notifications, message, level)
  notifications[#notifications + 1] = {
    message = message,
    level = level,
  }
end

describe("flemma.presets", function()
  local notifications = {}
  local original_notify

  before_each(function()
    notifications = {}
    original_notify = vim.notify
    vim.notify = function(message, level)
      collect_notification(notifications, message, level)
    end
    presets.refresh({})
  end)

  after_each(function()
    vim.notify = original_notify
    presets.refresh({})
  end)

  it("normalizes table definitions into provider, model, and parameters", function()
    presets.refresh({
      ["$o3"] = {
        provider = "openai",
        model = "o3",
        temperature = 1,
        reasoning = "high",
      },
    })

    local preset = presets.get("$o3")
    assert.is_not_nil(preset, "preset should be available after refresh")
    assert.are.equal("openai", preset.provider)
    assert.are.equal("o3", preset.model)
    assert.are.same({
      temperature = 1,
      reasoning = "high",
    }, preset.parameters)
  end)

  it("parses string definitions using modeline parsing", function()
    presets.refresh({
      ["$gemini"] = "vertex gemini-2.5-pro project_id=demo",
    })

    local preset = presets.get("$gemini")
    assert.is_not_nil(preset, "string-based preset should be parsed")
    assert.are.equal("vertex", preset.provider)
    assert.are.equal("gemini-2.5-pro", preset.model)
    assert.are.same({
      project_id = "demo",
    }, preset.parameters)
  end)

  it("supports positional provider/model tables", function()
    presets.refresh({
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
    presets.refresh({
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

  it("rejects string definitions that use assignments for provider/model", function()
    presets.refresh({
      ["$bad"] = "provider=vertex model=gemini-2.5-pro",
    })

    assert.is_nil(presets.get("$bad"))

    local found = false
    for _, note in ipairs(notifications) do
      if note.message:find("string definitions must start") then
        found = true
        break
      end
    end
    assert.is_true(found, "expected warning about invalid string preset definition")
  end)

  it("warns and ignores presets without a leading '$'", function()
    presets.refresh({
      gemini = { provider = "vertex" },
    })

    assert.is_nil(presets.get("gemini"))

    local found = false
    for _, note in ipairs(notifications) do
      if note.message:find("Preset 'gemini' ignored") then
        found = true
        break
      end
    end
    assert.is_true(found, "expected warning about missing '$' prefix")
  end)

  it("warns and ignores presets without a provider", function()
    presets.refresh({
      ["$broken"] = { model = "o3" },
    })

    assert.is_nil(presets.get("$broken"))

    local found = false
    for _, note in ipairs(notifications) do
      if note.message:find("missing a provider") then
        found = true
        break
      end
    end
    assert.is_true(found, "expected warning about missing provider")
  end)

  it("lists preset names in sorted order", function()
    presets.refresh({
      ["$beta"] = { provider = "openai" },
      ["$alpha"] = { provider = "vertex" },
    })

    local names = presets.list()
    assert.are.same({ "$alpha", "$beta" }, names)
  end)
end)

describe(":Flemma switch completion ordering", function()
  local notifications = {}
  local original_notify
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
    original_notify = vim.notify
    vim.notify = function(message, level)
      collect_notification(notifications, message, level)
    end
    presets.refresh({})
    reset_commands()
    reset_modules()

    stub_core = {
      initialize_provider = function() end,
      send_to_provider = function() end,
      cancel_request = function() end,
    }

    package.preload["flemma.core"] = function()
      return stub_core
    end
  end)

  after_each(function()
    vim.notify = original_notify
    presets.refresh({})
    reset_commands()
    reset_modules()
    package.preload["flemma.core"] = nil
    package.loaded["flemma.core"] = nil
    require("flemma.state").set_config({})
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

    assert.are.same({
      "$alpha",
      "$zulu",
      "anthropic",
      "openai",
      "vertex",
    }, completions, "completion order should list presets first followed by providers")
  end)
end)

describe(":Flemma switch with presets", function()
  local notifications = {}
  local original_notify
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
    original_notify = vim.notify
    vim.notify = function(message, level)
      collect_notification(notifications, message, level)
    end
    presets.refresh({})
    reset_commands()
    reset_modules()

    stub_core = {
      last_switch = nil,
      initialize_provider = function() end,
      send_to_provider = function() end,
      cancel_request = function() end,
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
    vim.notify = original_notify
    presets.refresh({})
    reset_commands()
    reset_modules()
    package.preload["flemma.core"] = nil
    package.loaded["flemma.core"] = nil
    require("flemma.state").set_config({})
    stub_core = nil
  end)

  it("expands preset definitions into switch arguments", function()
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
    assert.are.same({
      reasoning = "high",
      temperature = 1,
    }, stub_core.last_switch.parameters)
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

  it("notifies when a preset is unknown", function()
    local flemma = require("flemma")
    flemma.setup({
      presets = {},
    })

    vim.cmd("Flemma switch $missing")

    assert.is_nil(stub_core.last_switch, "switch should not run for unknown preset")

    local found = false
    for _, note in ipairs(notifications) do
      if note.message:find("Unknown preset") then
        found = true
        break
      end
    end
    assert.is_true(found, "expected warning about unknown preset")
  end)
end)
