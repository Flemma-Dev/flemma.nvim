--- Global configuration schema definition.
---
--- This is the single source of truth for Flemma's configuration structure,
--- types, and defaults. Replaces the legacy lua/flemma/config.lua defaults.
---
--- Provider, tool, and sandbox backend schemas are all resolved via DISCOVER.
--- Each module owns its own config schema (M.metadata.config_schema).
--- Defaults from discovered schemas materialize into L10 at registration time.

local h = require("flemma.hl")
local s = require("flemma.schema")
local symbols = require("flemma.symbols")

-- ---------------------------------------------------------------------------
-- Reusable type helpers
-- ---------------------------------------------------------------------------

---@type string[]
local BAR_POSITIONS = { "top", "bottom", "top left", "top right", "bottom left", "bottom right" }

--- Bar position enum with a caller-supplied default.
---@param default string
---@return flemma.schema.Node
local function position(default)
  return s.enum(BAR_POSITIONS, default)
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

--- General parameter schema shared between the top-level `parameters` object,
--- preset parameters, and each provider sub-table (e.g. `parameters.openai`).
--- The DISCOVER callback extends this object with adapter-specific fields.
---@return flemma.schema.ObjectNode
local function general_parameters_schema()
  return s.object({
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
  }):class_as("flemma.config.ParametersBase")
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

  parameters = general_parameters_schema():extend({
    [symbols.DISCOVER] = function(key)
      local registry = require("flemma.provider.registry")
      if not registry.has(key) then
        return nil
      end
      return general_parameters_schema():extend(registry.get_config_schema(key))
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
        parameters = s.optional(general_parameters_schema()),
        auto_approve = s.optional(s.list(s.string())),
        tools = s.optional(s.list(s.string())),
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
    ):type_as("flemma.tools.AutoApprove"),
    auto_approve_sandboxed = s.boolean(true),
    autopilot = s.object({
      enabled = s.boolean(true),
      max_turns = s.integer(100),
      resume_delay = s.integer(2000),
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
  })
    :allow_list(s.string():validate(function(name)
      local glob = require("flemma.utilities.glob")
      if glob.is_glob(name) then
        return false, ("Glob pattern '%s' matched no tools"):format(name)
      end
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
    end))
    :coerce(function(value, _ctx)
      if type(value) ~= "string" then
        return value
      end
      local glob = require("flemma.utilities.glob")
      if not glob.is_glob(value) then
        return value
      end
      local tool_registry = require("flemma.tools.registry")
      local expanded = {}
      for tool_name, _ in pairs(tool_registry.get_all({ include_disabled = true })) do
        if glob.match(tool_name, value) then
          table.insert(expanded, tool_name)
        end
      end
      table.sort(expanded)
      if #expanded == 0 then
        return value
      end
      return expanded
    end),

  templating = s.object({
    modules = s.list(s.loadable(), {}),
  }),

  -- ---------------------------------------------------------------------------
  -- Buffer rendering — colors, extmarks, statuscolumn drawn inline with content
  -- ---------------------------------------------------------------------------

  highlights = s.object({
    system = s.highlight(h.from("Special"):omit("bg")),
    user = s.highlight(h.from("Normal"):omit("bg")),
    assistant = s.highlight(h.from("Normal"):omit("bg")),
    lua_expression = s.highlight(h.link("PreProc")),
    lua_code_block = s.highlight(h.link("PreProc")),
    lua_delimiter = s.highlight(h.link("FlemmaLuaExpression")),
    user_file_reference = s.highlight(h.link("Include")),
    thinking_tag = s.highlight(h.link("Comment")),
    thinking_block = s.highlight(h.from("Comment"):mute("fg", "#333333")),
    tool_icon = s.highlight(h.link("FlemmaToolUseTitle")),
    tool_name = s.highlight(h.link("Function")),
    tool_use_title = s.highlight(h.link("Function")),
    tool_result_title = s.highlight(h.link("Function")),
    tool_result_error = s.highlight(h.link("DiagnosticError")),
    tool_result_pending = s.highlight(h.link("DiagnosticInfo")),
    tool_result_approved = s.highlight(h.link("DiagnosticOk")),
    tool_result_rejected = s.highlight(h.link("DiagnosticWarn")),
    tool_result_denied = s.highlight(h.link("DiagnosticError")),
    tool_result_aborted = s.highlight(h.link("DiagnosticError")),
    tool_preview = s.highlight(h.link("Comment")),
    tool_label = s.highlight(h.attrs({ italic = true })),
    fence_label = s.highlight(h.from("Comment"):mute("fg", "#303030")),
    fence_bar = s.highlight(h.link("FlemmaFenceLabel")),
    fold_preview = s.highlight(h.link("Comment")),
    fold_meta = s.highlight(h.link("Comment")),
    tool_detail = s.highlight(h.link("Comment")),
    busy = s.highlight(h.link("DiagnosticWarn")),
    progress_accent = s.highlight(h.attrs({ bold = true })),
    approval_line = s.highlight(
      h.coalesce(
        h.from("FlemmaLineUser"):tint("bg", h.from("DiagnosticInfo"):pick("fg"), 0.1),
        h.from("Normal"):tint("bg", h.from("DiagnosticInfo"):pick("fg"), 0.1)
      )
    ),
    approval_indicator = s.highlight(h.from("DiagnosticInfo"):omit("bg")),
    approval_label = s.highlight(h.from("DiagnosticInfo"):omit("bg")),
    approval_key = s.highlight(h.link("MoreMsg")),
    approval_action = s.highlight(h.from("ModeMsg"):tint("fg", "#202122")),
    rejection_input = s.highlight(
      h.from("DiagnosticWarn"):merge(h.coalesce(h.from("FlemmaLineUser"):pick("bg"), h.from("Normal"):pick("bg")))
    ),
    rejection_border = s.highlight(h.link("FlemmaRejection")),
    role_name = s.highlight(h.attrs({ bold = true })),
  }),

  ruler = s.object({
    enabled = s.boolean(true),
    char = s.string("─"),
    hl = s.highlight(h.from("Comment"):mute("fg", "#303030")),
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
    frontmatter = s.highlight(h.from("Normal"):tint("bg", "#18111a")),
    system = s.highlight(h.from("Normal"):tint("bg", "#101112")),
    user = s.highlight(h.from("Normal"):tint("bg", "#202122")),
    assistant = s.highlight(h.link("Normal")),
  }),

  -- ---------------------------------------------------------------------------
  -- UI chrome — floating/overlay elements (usage bar, progress, statusline)
  -- ---------------------------------------------------------------------------

  ui = s.object({
    usage = s.object({
      enabled = s.boolean(true),
      timeout = s.integer(10000),
      position = position("top"),
      highlight = s.string("@text.note,PmenuSel"),
    }),
    progress = s.object({
      position = position("bottom left"),
      highlight = s.string("StatusLine"),
    }),
    jobs = s.object({
      position = position("bottom right"),
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
          {%- if buffer.tokens.input and model.max_input_tokens then %} %#FlemmaStatusTextMuted#·%* {{ format.percent(buffer.tokens.input / model.max_input_tokens, 0) }}{% end %}
          {%- if session.cost then %} %#FlemmaStatusTextMuted#·%* Σ{{ session.requests }} {{ format.money(session.cost) }}{% end %}
          {%- if booting then %} %#FlemmaStatusTextMuted#⧖%*{% end %}
        ]]),
        s.func():type_as("flemma.statusline.FormatFunction")
      ),
    }),
    approval = s.object({
      enabled = s.boolean(true),
      layout = s.enum({ "inline", "block" }, "inline"),
      fade = s.integer(10),
      syntax_highlighting = s.boolean(true),
      preview_lines = s.union(
        s.object({
          head = s.integer(6),
          tail = s.integer(6),
        }),
        s.integer()
      ):coerce(function(value, _)
        if type(value) == "number" then
          return { head = value, tail = value }
        end
        if type(value) == "table" and value[1] ~= nil then
          return { head = value[1], tail = value[2] or value[1] }
        end
        return value
      end),
    }),
    rejection = s.object({
      enabled = s.boolean(true),
      completion = s.boolean(false),
      winblend = s.integer(15),
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
    fold = s.object({
      level = s.integer(1),
      gap = s.boolean(false),
    }),
    -- Compact `{conceallevel}{concealcursor}` format, e.g. "2nv" = conceallevel 2, concealcursor "nv".
    -- false disables the override and leaves the user's own window settings untouched.
    -- See docs/conceal.md.
    conceal = s.optional(s.union(s.string("2nv"), s.integer(), s.literal(false))),
    auto_close = s.object({
      thinking = s.boolean(true),
      tool_use = s.boolean(true),
      tool_result = s.boolean(true),
      job_result = s.boolean(true),
      frontmatter = s.boolean(false),
    }),
  }),

  keymaps = s.object({
    normal = s.object({
      send = s.string("<C-]>"),
      cancel = s.string("<C-c>"),
      tool_execute = s.string("<M-CR>"),
      tool_background = s.string("<M-b>"),
      tool_approve = s.string("<M-a>"),
      tool_reject = s.string("<M-r>"),
      tool_approve_all = s.string("<M-A>"),
      message_next = s.string("]m"),
      message_prev = s.string("[m"),
      fold_toggle = s.union(s.string("<Space>"), s.literal(false)),
      fold_turn = s.union(s.string("zy"), s.literal(false)),
      fold_turns = s.union(s.string("zY"), s.literal(false)),
      conceal_toggle = s.union(s.string("yoe"), s.literal(false)),
      conceal_on = s.union(s.string("]oe"), s.literal(false)),
      conceal_off = s.union(s.string("[oe"), s.literal(false)),
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
      icon = s.string("∴"),
    }),
  }),

  lsp = s.object({
    enabled = s.boolean(vim.lsp ~= nil),
  }),

  experimental = s.object({
    -- Patch the global markdown treesitter highlights query to strip
    -- conceal_lines directives from fenced code block delimiters. Without this,
    -- conceallevel>=2 triggers an expensive _on_conceal_line callback on every
    -- keystroke (~30ms overhead on large buffers). The patch is deferred to the
    -- first .chat file open so markdown-only sessions are unaffected. Set to
    -- false if the patch interferes with other markdown plugins.
    patch_markdown_conceal = s.boolean(true),
  }),

  [symbols.ALIASES] = {
    timeout = "parameters.timeout",
    thinking = "parameters.thinking",
    max_tokens = "parameters.max_tokens",
    temperature = "parameters.temperature",
  },
})
