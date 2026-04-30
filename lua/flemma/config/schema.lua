--- Global configuration schema definition.
---
--- This is the single source of truth for Flemma's configuration structure,
--- types, and defaults. Replaces the legacy lua/flemma/config.lua defaults.
---
--- Provider, tool, and sandbox backend schemas are all resolved via DISCOVER.
--- Each module owns its own config schema (M.metadata.config_schema).
--- Defaults from discovered schemas materialize into L10 at registration time.

local s = require("flemma.schema")
local symbols = require("flemma.symbols")

-- ---------------------------------------------------------------------------
-- Reusable type helpers
-- ---------------------------------------------------------------------------

--- HighlightValue: string | { dark: string, light: string }
--- String defaults produce a union with the string branch carrying the default.
--- Table defaults produce a union with the object branch carrying the defaults.
---@param default? string|table<string, string>
---@return flemma.schema.Node
local function highlight(default)
  local node
  if type(default) == "table" then
    node = s.union(s.string(), s.object({ dark = s.string(default.dark), light = s.string(default.light) }))
  elseif type(default) == "string" then
    node = s.union(s.string(default), s.object({ dark = s.string(), light = s.string() }))
  else
    node = s.union(s.string(), s.object({ dark = s.string(), light = s.string() }))
  end
  return node:type_as("flemma.config.HighlightValue")
end

--- ThinkingLevel: the set of valid thinking value forms (enum | number | false).
--- Used both for the top-level `thinking` field and for `thinking.level`.
---@param default? string Default enum value
---@return flemma.schema.Node[]
local function thinking_level(default)
  return {
    s.enum({ "minimal", "low", "medium", "high", "max" }, default),
    s.number(),
    s.literal(false),
  }
end

-- ---------------------------------------------------------------------------
-- The config schema
-- ---------------------------------------------------------------------------

---@type flemma.schema.ObjectNode
return s.object({
  -- ---------------------------------------------------------------------------
  -- Provider & model — what to talk to and how
  -- ---------------------------------------------------------------------------

  provider = s.string("anthropic"),
  model = s.optional(s.string()),

  parameters = s.object({
    max_tokens = s.union(s.string("50%"), s.integer()),
    temperature = s.optional(s.number()),
    timeout = s.integer(600),
    connect_timeout = s.integer(10),
    cache_retention = s.enum({ "short", "long", "none" }, "short"),
    thinking = s.union(
      s.object({
        level = s.union(unpack(thinking_level("high"))),
        foreign = s.enum({ "preserve", "drop" }, "preserve"),
      }),
      unpack(thinking_level("high"))
    ):coerce(function(value, _ctx)
      if type(value) == "string" or type(value) == "number" or value == false then
        value = { level = value }
      end
      if type(value) == "table" then
        if value.level == nil then
          value.level = "high"
        end
        if value.foreign == nil then
          value.foreign = "preserve"
        end
      end
      return value
    end),
    -- All provider parameter schemas resolved via DISCOVER
    [symbols.DISCOVER] = function(key)
      return require("flemma.provider.registry").get_config_schema(key)
    end,
  }),

  presets = s.map(
    s.string():validate(function(name)
      if not vim.startswith(name, "$") then
        return false, ("preset key '%s' must start with '$'"):format(name)
      end
      return true
    end),
    s.union(
      s.string(),
      s.object({}):passthrough(),
      s.object({
        provider = s.optional(s.string()),
        model = s.optional(s.string()),
        parameters = s.optional(s.object({}):passthrough()),
        auto_approve = s.optional(s.list(s.string())),
      })
    ),
    {}
  ),

  -- ---------------------------------------------------------------------------
  -- Tools & templating — what the model can do and how prompts are built
  -- ---------------------------------------------------------------------------

  tools = s.object({
    require_approval = s.boolean(true),
    auto_approve = s.union(
      s.list(s.string(), { "$standard" }),
      s.func():type_as("flemma.tools.AutoApproveFunction"),
      s.string()
    )
      :type_as("flemma.tools.AutoApprove")
      :coerce(function(value, _ctx)
        -- Expand $-prefixed preset references to their auto_approve list.
        -- At boot time presets may not be registered yet; finalize() re-runs
        -- coerce after presets.setup() so deferred expansion succeeds.
        if type(value) ~= "string" or not vim.startswith(value, "$") then
          return value
        end
        local preset = require("flemma.presets").get(value)
        if not preset or not preset.auto_approve then
          return value
        end
        return preset.auto_approve
      end),
    auto_approve_sandboxed = s.boolean(true),
    autopilot = s.object({
      enabled = s.boolean(true),
      max_turns = s.integer(100),
    }):coerce(function(value, _ctx)
      if type(value) == "boolean" then
        return { enabled = value }
      end
      return value
    end),
    max_concurrent = s.integer(2),
    default_timeout = s.integer(30),
    show_spinner = s.boolean(true),
    cursor_after_result = s.enum({ "result", "stay", "next" }, "result"),
    modules = s.list(s.loadable(), {}),
    mcporter = s.object({
      enabled = s.boolean(false),
      path = s.string("mcporter"),
      timeout = s.integer(60),
      startup = s.object({
        concurrency = s.integer(4),
      }),
      include = s.list(s.string(), {}),
      exclude = s.list(s.string(), {}),
    }),
    truncate = s.object({
      output_path_format = s.string("${TMPDIR:-/tmp}/flemma_{{ source }}_{{ path }}_{{ id }}.txt"),
    }),
    -- Tool-specific config schemas (resolved lazily via tools registry)
    [symbols.DISCOVER] = function(key)
      return require("flemma.tools").get_config_schema(key)
    end,
    [symbols.ALIASES] = {
      approve = "auto_approve",
    },
  }):allow_list(s.string():validate(function(name)
    local tool_registry = require("flemma.tools.registry")
    if not tool_registry.has(name) then
      local suggestion = tool_registry.closest_match(name)
      local message = ("Unknown tool '%s'"):format(name)
      if suggestion then
        message = message .. (" -- did you mean '%s'?"):format(suggestion)
      end
      return false, message
    end
    return true
  end)),

  templating = s.object({
    modules = s.list(s.loadable(), {}),
  }),

  -- ---------------------------------------------------------------------------
  -- Buffer rendering — colors, extmarks, statuscolumn drawn inline with content
  -- ---------------------------------------------------------------------------

  highlights = s.object({
    -- Fallback colors used when highlight groups don't define fg/bg
    defaults = s.object({
      dark = s.object({ bg = s.string("#000000"), fg = s.string("#ffffff") }),
      light = s.object({ bg = s.string("#ffffff"), fg = s.string("#000000") }),
    }),
    system = highlight("Special"),
    user = highlight("Normal"),
    assistant = highlight("Normal"),
    lua_expression = highlight("PreProc"),
    lua_code_block = highlight("PreProc"),
    lua_delimiter = highlight("FlemmaLuaExpression"),
    user_file_reference = highlight("Include"),
    thinking_tag = highlight("Comment"),
    thinking_block = highlight({
      dark = "Comment+bg:#000000-fg:#333333",
      light = "Comment-bg:#000000+fg:#333333",
    }),
    tool_icon = highlight("FlemmaToolUseTitle"),
    tool_name = highlight("Function"),
    tool_use_title = highlight("Function"),
    tool_result_title = highlight("Function"),
    tool_result_error = highlight("DiagnosticError"),
    tool_result_pending = highlight("DiagnosticInfo"),
    tool_result_approved = highlight("DiagnosticOk"),
    tool_result_rejected = highlight("DiagnosticWarn"),
    tool_result_denied = highlight("DiagnosticError"),
    tool_result_aborted = highlight("DiagnosticError"),
    tool_preview = highlight("Comment"),
    fold_preview = highlight("Comment"),
    fold_meta = highlight("Comment"),
    tool_detail = highlight("Comment"),
    busy = highlight("DiagnosticWarn"),
    role_style = s.string("bold"),
  }),

  ruler = s.object({
    enabled = s.boolean(true),
    char = s.string("\u{2500}"),
    hl = highlight({ dark = "Comment-fg:#303030", light = "Comment+fg:#303030" }),
  }),

  turns = s.object({
    enabled = s.boolean(true),
    padding = s.union(
      s.object({
        left = s.integer(0),
        right = s.integer(1),
      }),
      s.integer()
    ):coerce(function(value, _ctx)
      if type(value) == "number" then
        return { left = value, right = 0 }
      end
      if type(value) == "table" and value[1] ~= nil then
        return { left = value[1], right = value[2] or 0 }
      end
      return value
    end),
    hl = s.string("FlemmaTurn"),
  }),

  line_highlights = s.object({
    enabled = s.boolean(true),
    frontmatter = highlight({ dark = "Normal+bg:#18111a", light = "Normal-bg:#18111a" }),
    system = highlight({ dark = "Normal+bg:#101112", light = "Normal-bg:#101112" }),
    user = highlight({ dark = "Normal+bg:#202122", light = "Normal-bg:#202122" }),
    assistant = highlight({ dark = "Normal", light = "Normal" }),
  }),

  -- ---------------------------------------------------------------------------
  -- UI chrome — floating/overlay elements (usage bar, progress, statusline)
  -- ---------------------------------------------------------------------------

  ui = s.object({
    usage = s.object({
      enabled = s.boolean(true),
      timeout = s.integer(10000),
      position = s.enum({
        "top",
        "bottom",
        "top left",
        "top right",
        "bottom left",
        "bottom right",
      }, "top"),
      highlight = s.string("@text.note,PmenuSel"),
    }),
    progress = s.object({
      position = s.enum({
        "top",
        "bottom",
        "top left",
        "top right",
        "bottom left",
        "bottom right",
      }, "bottom left"),
      highlight = s.string("StatusLine"),
    }),
    pricing = s.object({
      enabled = s.boolean(true),
      high_cost_threshold = s.integer(30),
    }),
    statusline = s.object({
      format = s.union(
        s.string([[
          {{ model.name }}
          {%- if thinking.enabled then %} ({{ thinking.level }}){% end %}
          {%- if session.cost then %} %#FlemmaStatusTextMuted#╱%* Σ{{ session.requests }} {{ format.money(session.cost) }}{% end %}
          {%- if buffer.tokens.input and model.max_input_tokens then %} %#FlemmaStatusTextMuted#╱%* {{ format.percent(buffer.tokens.input / model.max_input_tokens, 0) }}{% end %}
          {%- if booting then %} %#FlemmaStatusTextMuted#⧖%*{% end %}
        ]]),
        s.func():type_as("flemma.statusline.FormatFunction")
      ),
    }),
  }),

  -- ---------------------------------------------------------------------------
  -- Editing & keymaps — editor behaviour in .chat buffers
  -- ---------------------------------------------------------------------------

  editing = s.object({
    auto_prompt = s.boolean(true),
    disable_textwidth = s.boolean(true),
    auto_write = s.boolean(false),
    manage_updatetime = s.boolean(true),
    foldlevel = s.integer(1),
    -- Compact `{conceallevel}{concealcursor}` format, e.g. "2nv" = conceallevel 2, concealcursor "nv".
    -- false disables the override and leaves the user's own window settings untouched.
    -- See docs/conceal.md.
    conceal = s.optional(s.union(s.string("2nv"), s.integer(), s.literal(false))),
    auto_close = s.object({
      thinking = s.boolean(true),
      tool_use = s.boolean(true),
      tool_result = s.boolean(true),
      frontmatter = s.boolean(false),
    }),
  }),

  keymaps = s.object({
    normal = s.object({
      send = s.string("<C-]>"),
      cancel = s.string("<C-c>"),
      tool_execute = s.string("<M-CR>"),
      message_next = s.string("]m"),
      message_prev = s.string("[m"),
      fold_toggle = s.union(s.string("<Space>"), s.literal(false)),
      conceal_toggle = s.union(s.string("<Space><Space>"), s.literal(false)),
    }),
    insert = s.object({
      send = s.string("<C-]>"),
    }),
    text_object = s.union(s.string("m"), s.literal(false)),
    enabled = s.boolean(true),
  }),

  -- ---------------------------------------------------------------------------
  -- Infrastructure — sandbox, secrets, logging, diagnostics, integrations
  -- ---------------------------------------------------------------------------

  sandbox = s.object({
    enabled = s.boolean(true),
    backend = s.string("auto"),
    policy = s.object({
      rw_paths = s.list(s.string(), {
        "urn:flemma:cwd",
        "urn:flemma:buffer:path",
        "/tmp",
        "${TMPDIR:-/tmp}",
        "${XDG_CACHE_HOME:-~/.cache}",
        "${XDG_DATA_HOME:-~/.local/share}",
      }),
      network = s.boolean(true),
      allow_privileged = s.boolean(false),
    }),
    backends = s.object({
      -- All backend schemas (including built-in bwrap) resolved via DISCOVER
      [symbols.DISCOVER] = function(key)
        return require("flemma.sandbox").get_config_schema(key)
      end,
    }),
  }),

  secrets = s.object({
    gcloud = s.object({
      path = s.string("gcloud"),
    }),
  }),

  logging = s.object({
    enabled = s.boolean(false),
    path = s.string(vim.fn.stdpath("cache") .. "/flemma.log"),
    level = s.enum({ "TRACE", "DEBUG", "INFO", "WARN", "ERROR" }, "DEBUG"),
  }):type_as("flemma.logging.Config"),

  diagnostics = s.object({
    enabled = s.boolean(false),
  }),

  integrations = s.object({
    devicons = s.object({
      enabled = s.boolean(true),
      icon = s.string("\u{2234}"), -- ∴ U+2234 Therefore
    }),
  }),

  lsp = s.object({
    enabled = s.boolean(vim.lsp ~= nil),
  }),

  experimental = s.object({}),

  [symbols.ALIASES] = {
    timeout = "parameters.timeout",
    thinking = "parameters.thinking",
    max_tokens = "parameters.max_tokens",
    temperature = "parameters.temperature",
  },
})
