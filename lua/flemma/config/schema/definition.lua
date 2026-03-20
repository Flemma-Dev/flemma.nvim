--- Global configuration schema definition.
---
--- This is the single source of truth for Flemma's configuration structure,
--- types, and defaults. Replaces the legacy lua/flemma/config.lua defaults.
---
--- Provider-specific parameter schemas are defined inline (will move to
--- provider modules during refactoring). Tool-specific config schemas use
--- DISCOVER resolution via the tools registry.

local s = require("flemma.config.schema")
local symbols = require("flemma.symbols")

-- ---------------------------------------------------------------------------
-- Reusable type helpers
-- ---------------------------------------------------------------------------

--- HighlightValue: string | { dark: string, light: string }
--- String defaults produce a union with the string branch carrying the default.
--- Table defaults produce a union with the object branch carrying the defaults.
---@param default? string|table<string, string>
---@return flemma.config.schema.UnionNode
local function highlight(default)
  if type(default) == "table" then
    return s.union(s.string(), s.object({ dark = s.string(default.dark), light = s.string(default.light) }))
  elseif type(default) == "string" then
    return s.union(s.string(default), s.object({ dark = s.string(), light = s.string() }))
  else
    return s.union(s.string(), s.object({ dark = s.string(), light = s.string() }))
  end
end

--- Sign role hl: boolean | string | { dark: string, light: string }
--- true = inherit from highlights, false = disable, string/table = custom highlight.
---@param default boolean
---@return flemma.config.schema.UnionNode
local function sign_highlight(default)
  return s.union(s.boolean(default), s.string(), s.object({ dark = s.string(), light = s.string() }))
end

-- ---------------------------------------------------------------------------
-- Provider parameter schemas
-- ---------------------------------------------------------------------------

local AnthropicParametersSchema = s.object({
  thinking_budget = s.optional(s.integer()),
})

local OpenAIParametersSchema = s.object({
  reasoning_summary = s.optional(s.string("auto")),
  reasoning = s.optional(s.string()),
})

local VertexParametersSchema = s.object({
  project_id = s.optional(s.string()),
  location = s.optional(s.string("global")),
  thinking_budget = s.optional(s.integer()),
})

-- ---------------------------------------------------------------------------
-- The config schema
-- ---------------------------------------------------------------------------

---@type flemma.config.schema.ObjectNode
return s.object({

  -- Fallback colors used when highlight groups don't define fg/bg
  defaults = s.object({
    dark = s.object({ bg = s.string("#000000"), fg = s.string("#ffffff") }),
    light = s.object({ bg = s.string("#ffffff"), fg = s.string("#000000") }),
  }),

  highlights = s.object({
    system = highlight("Special"),
    user = highlight("Normal"),
    assistant = highlight("Normal"),
    lua_expression = highlight("PreProc"),
    lua_code_block = highlight("PreProc"),
    lua_delimiter = highlight("FlemmaLuaExpression"),
    user_file_reference = highlight("Include"),
    thinking_tag = highlight("Comment"),
    thinking_block = highlight({
      dark = "Comment+bg:#102020-fg:#111111",
      light = "Comment-bg:#102020+fg:#111111",
    }),
    tool_icon = highlight("FlemmaToolUseTitle"),
    tool_name = highlight("Function"),
    tool_use_title = highlight("Function"),
    tool_result_title = highlight("Function"),
    tool_result_error = highlight("DiagnosticError"),
    tool_preview = highlight("Comment"),
    fold_preview = highlight("Comment"),
    fold_meta = highlight("Comment"),
    tool_detail = highlight("Comment"),
    busy = highlight("DiagnosticWarn"),
  }),

  role_style = s.string("bold"),

  ruler = s.object({
    enabled = s.boolean(true),
    char = s.string("\u{2500}"),
    hl = highlight({ dark = "Comment-fg:#303030", light = "Comment+fg:#303030" }),
  }),

  signs = s.object({
    enabled = s.boolean(false),
    char = s.string("\u{258c}"),
    system = s.object({
      char = s.optional(s.string()),
      hl = sign_highlight(true),
    }),
    user = s.object({
      char = s.optional(s.string("\u{258f}")),
      hl = sign_highlight(true),
    }),
    assistant = s.object({
      char = s.optional(s.string()),
      hl = sign_highlight(true),
    }),
  }),

  line_highlights = s.object({
    enabled = s.boolean(true),
    frontmatter = highlight({ dark = "Normal+bg:#201020", light = "Normal-bg:#201020" }),
    system = highlight({ dark = "Normal+bg:#201000", light = "Normal-bg:#201000" }),
    user = highlight({ dark = "Normal", light = "Normal" }),
    assistant = highlight({ dark = "Normal+bg:#102020", light = "Normal-bg:#102020" }),
  }),

  notifications = s.object({
    enabled = s.boolean(true),
    timeout = s.integer(10000),
    limit = s.integer(1),
    position = s.enum({ "overlay" }, "overlay"),
    zindex = s.integer(30),
    highlight = s.string("@text.note,PmenuSel"),
    border = s.union(
      s.literal(false),
      s.enum({ "underline", "underdouble", "undercurl", "underdotted", "underdashed" })
    ),
  }),

  progress = s.object({
    highlight = s.string("StatusLine"),
    zindex = s.integer(50),
  }),

  pricing = s.object({
    enabled = s.boolean(true),
  }),

  statusline = s.object({
    format = s.string("#{model}#{?#{thinking}, (#{thinking}),}#{?#{booting}, \u{23f3},}"),
  }),

  provider = s.string("anthropic"),
  model = s.optional(s.string()),

  parameters = s.object({
    max_tokens = s.union(s.string("50%"), s.integer()),
    temperature = s.number(0.7),
    timeout = s.integer(600),
    connect_timeout = s.integer(10),
    cache_retention = s.enum({ "short", "long", "none" }, "short"),
    thinking = s.union(s.enum({ "minimal", "low", "medium", "high", "max" }, "high"), s.number(), s.literal(false)),
    -- Built-in provider parameter schemas (statically referenced)
    anthropic = AnthropicParametersSchema,
    openai = OpenAIParametersSchema,
    vertex = VertexParametersSchema,
    -- Dynamic provider parameter schemas (resolved lazily)
    [symbols.DISCOVER] = function(key)
      return require("flemma.provider.registry").get_config_schema(key)
    end,
  }),

  tools = s.object({
    require_approval = s.boolean(true),
    auto_approve = s.union(s.list(s.string(), { "$default" }), s.func(), s.string()),
    auto_approve_sandboxed = s.boolean(true),
    presets = s.map(
      s.string(),
      s.object({
        approve = s.optional(s.list(s.string())),
        deny = s.optional(s.list(s.string())),
      }),
      {}
    ),
    autopilot = s.object({
      enabled = s.boolean(true),
      max_turns = s.integer(100),
    }),
    max_concurrent = s.integer(2),
    default_timeout = s.integer(30),
    show_spinner = s.boolean(true),
    cursor_after_result = s.enum({ "result", "stay", "next" }, "result"),
    modules = s.list(s.loadable(), {}),
    -- Tool-specific config schemas (resolved lazily via tools registry)
    [symbols.DISCOVER] = function(key)
      return require("flemma.tools").get_config_schema(key)
    end,
    [symbols.ALIASES] = {
      approve = "auto_approve",
    },
  }),

  templating = s.object({
    modules = s.list(s.loadable(), {}),
  }),

  presets = s.map(s.string(), s.object({}):passthrough(), {}),

  text_object = s.union(s.string("m"), s.literal(false)),

  editing = s.object({
    auto_prompt = s.boolean(true),
    disable_textwidth = s.boolean(true),
    auto_write = s.boolean(false),
    manage_updatetime = s.boolean(true),
    foldlevel = s.integer(1),
    auto_close = s.object({
      thinking = s.boolean(true),
      tool_use = s.boolean(true),
      tool_result = s.boolean(true),
      frontmatter = s.boolean(false),
    }),
  }),

  logging = s.object({
    enabled = s.boolean(false),
    path = s.string(vim.fn.stdpath("cache") .. "/flemma.log"),
    level = s.enum({ "TRACE", "DEBUG", "INFO", "WARN", "ERROR" }, "DEBUG"),
  }),

  keymaps = s.object({
    normal = s.object({
      send = s.string("<C-]>"),
      cancel = s.string("<C-c>"),
      tool_execute = s.string("<M-CR>"),
      message_next = s.string("]m"),
      message_prev = s.string("[m"),
      fold_toggle = s.union(s.string("<Space>"), s.literal(false)),
    }),
    insert = s.object({
      send = s.string("<C-]>"),
    }),
    enabled = s.boolean(true),
  }),

  diagnostics = s.object({
    enabled = s.boolean(false),
  }),

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

  experimental = s.object({
    lsp = s.boolean(vim.lsp ~= nil),
    tools = s.boolean(false),
  }),

  [symbols.ALIASES] = {
    timeout = "parameters.timeout",
    thinking = "parameters.thinking",
    max_tokens = "parameters.max_tokens",
    temperature = "parameters.temperature",
  },
})
