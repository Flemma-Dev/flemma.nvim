-- Generate a synthetic .chat fixture for profiling.
-- Produces ~5000 lines exercising all Flemma fold-relevant structures:
-- frontmatter, role markers, tool use/result blocks, thinking blocks,
-- markdown formatting, and long prose.
--
-- Usage: nvim --headless --noplugin -u NONE --cmd 'set rtp^=.' -l contrib/profile/generate-fixture.lua

math.randomseed(42)

local SCRIPT_DIR = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
local OUTPUT = SCRIPT_DIR .. "fixture.chat"

local VOCAB = {
  "the", "system", "process", "should", "handle", "request", "data", "from",
  "server", "client", "function", "returns", "value", "after", "each", "call",
  "with", "error", "check", "before", "running", "next", "step", "when",
  "buffer", "line", "content", "parsing", "token", "stream", "response",
  "model", "provider", "config", "setup", "plugin", "module", "require",
  "local", "table", "string", "number", "boolean", "field", "method",
  "async", "callback", "event", "trigger", "handler", "queue", "batch",
  "file", "path", "directory", "cache", "state", "update", "render",
  "window", "cursor", "fold", "highlight", "extmark", "namespace",
  "parameter", "argument", "option", "default", "override", "merge",
  "validate", "transform", "normalize", "resolve", "inject", "extract",
  "pipeline", "stage", "phase", "output", "input", "result", "status",
  "pending", "complete", "running", "failed", "timeout", "retry",
  "connect", "disconnect", "session", "context", "scope", "boundary",
  "message", "payload", "header", "body", "format", "encode", "decode",
  "search", "filter", "match", "pattern", "replace", "insert", "remove",
  "create", "delete", "modify", "append", "prepend", "truncate", "split",
}

local LANGUAGES = { "lua", "bash", "json", "python", "javascript", "go" }

local function random_word()
  return VOCAB[math.random(#VOCAB)]
end

local function random_sentence()
  local n = math.random(8, 15)
  local words = {}
  for i = 1, n do
    words[i] = random_word()
  end
  words[1] = words[1]:sub(1, 1):upper() .. words[1]:sub(2)
  return table.concat(words, " ") .. "."
end

local function random_paragraph(min_lines, max_lines)
  local lines = {}
  for _ = 1, math.random(min_lines or 3, max_lines or 8) do
    lines[#lines + 1] = random_sentence() .. " " .. random_sentence()
  end
  return lines
end

local function random_tool_id()
  local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  local parts = {}
  for _ = 1, 20 do
    local i = math.random(#chars)
    parts[#parts + 1] = chars:sub(i, i)
  end
  return "toolu_" .. table.concat(parts)
end

local function random_path()
  return string.format("src/%s/%s.%s", random_word(), random_word(),
    ({ "lua", "py", "js", "go", "rs" })[math.random(5)])
end

local function random_language()
  return LANGUAGES[math.random(#LANGUAGES)]
end

-- Tool-specific JSON generators matching each tool's expected input schema.
-- The fold text preview formatter for each tool reads specific fields; missing
-- fields cause crashes (caught by the pcall wrapper, but we want clean previews).
local TOOL_INPUT_GENERATORS = {
  bash = function()
    return string.format('{\n  "command": "%s",\n  "label": "%s"\n}',
      random_word() .. " " .. random_word() .. " " .. random_word(),
      random_sentence():sub(1, -2))
  end,
  read = function()
    local fields = { string.format('"path": "%s"', random_path()) }
    if math.random() < 0.5 then
      fields[#fields + 1] = string.format('"offset": %d', math.random(0, 500))
      fields[#fields + 1] = string.format('"limit": %d', math.random(20, 200))
    end
    local inner = {}
    for _, field in ipairs(fields) do
      inner[#inner + 1] = "  " .. field
    end
    return "{\n" .. table.concat(inner, ",\n") .. "\n}"
  end,
  write = function()
    local content_lines = {}
    for _ = 1, math.random(3, 10) do
      content_lines[#content_lines + 1] = random_sentence()
    end
    return string.format('{\n  "path": "%s",\n  "content": "%s",\n  "label": "%s"\n}',
      random_path(),
      table.concat(content_lines, "\\n"):gsub('"', '\\"'),
      random_sentence():sub(1, -2))
  end,
  edit = function()
    return string.format(
      '{\n  "path": "%s",\n  "old_string": "%s",\n  "new_string": "%s",\n  "label": "%s"\n}',
      random_path(),
      random_sentence():sub(1, -2):gsub('"', '\\"'),
      random_sentence():sub(1, -2):gsub('"', '\\"'),
      random_sentence():sub(1, -2))
  end,
  grep = function()
    return string.format('{\n  "pattern": "%s",\n  "path": "%s"\n}',
      random_word() .. ".*" .. random_word(),
      "src/" .. random_word())
  end,
  find = function()
    return string.format('{\n  "pattern": "*.%s",\n  "path": "%s"\n}',
      ({ "lua", "py", "js", "go" })[math.random(4)],
      "src/" .. random_word())
  end,
  ls = function()
    return string.format('{\n  "path": "%s",\n  "max_depth": %d\n}',
      "src/" .. random_word(), math.random(1, 3))
  end,
}

local TOOL_NAMES = {}
for name in pairs(TOOL_INPUT_GENERATORS) do
  TOOL_NAMES[#TOOL_NAMES + 1] = name
end
table.sort(TOOL_NAMES)

local function random_tool_name()
  return TOOL_NAMES[math.random(#TOOL_NAMES)]
end

-- Generators for each block type. Each returns a list of lines.

local function generate_frontmatter()
  return {
    "```lua",
    "-- Model and provider configuration for this conversation.",
    '--flemma.opt.provider = "anthropic"',
    '--flemma.opt.model = "claude-sonnet-4-6"',
    '--flemma.opt.thinking = "medium"',
    "```",
  }
end

local function generate_you_message(long)
  local lines = { "@You:" }
  local paragraph_count = long and math.random(3, 6) or math.random(1, 2)
  for p = 1, paragraph_count do
    for _, l in ipairs(random_paragraph()) do
      lines[#lines + 1] = l
    end
    if p < paragraph_count then
      lines[#lines + 1] = ""
    end
  end
  return lines
end

local function generate_thinking(size)
  local lines = { "<thinking>" }
  local paragraph_count = size or math.random(2, 5)
  for p = 1, paragraph_count do
    for _, l in ipairs(random_paragraph(2, 6)) do
      lines[#lines + 1] = l
    end
    if p < paragraph_count then
      lines[#lines + 1] = ""
    end
  end
  lines[#lines + 1] = "</thinking>"
  return lines
end

local function generate_tool_use()
  local id = random_tool_id()
  local name = random_tool_name()
  local json_body = TOOL_INPUT_GENERATORS[name]()
  local lines = {
    string.format("**Tool Use:** `%s` (`%s`)", name, id),
    "",
    "```json",
  }
  for json_line in json_body:gmatch("[^\n]+") do
    lines[#lines + 1] = json_line
  end
  lines[#lines + 1] = "```"
  return lines, id, name
end

local function generate_tool_result(id, output_lines)
  local lines = {
    "@You:",
    string.format("**Tool Result:** `%s`", id),
    "",
    "```",
  }
  local n = output_lines or math.random(5, 20)
  for _ = 1, n do
    if math.random() < 0.3 then
      -- fake file path output
      lines[#lines + 1] = string.format(
        "  %s/%s/%s.%s",
        random_word(), random_word(), random_word(),
        ({ "lua", "py", "js", "go", "rs", "sh" })[math.random(6)]
      )
    elseif math.random() < 0.5 then
      -- fake log line
      lines[#lines + 1] = string.format(
        "[%02d:%02d:%02d] %s: %s",
        math.random(0, 23), math.random(0, 59), math.random(0, 59),
        ({ "INFO", "WARN", "DEBUG", "ERROR" })[math.random(4)],
        random_sentence()
      )
    else
      lines[#lines + 1] = random_sentence()
    end
  end
  lines[#lines + 1] = "```"
  return lines
end

local function generate_assistant_prose(long)
  local lines = { "@Assistant:" }
  -- Sometimes start with a heading
  if math.random() < 0.5 then
    lines[#lines + 1] = "## " .. random_word():sub(1, 1):upper() .. random_word():sub(2) .. " " .. random_word()
    lines[#lines + 1] = ""
  end
  local section_count = long and math.random(3, 5) or math.random(1, 3)
  for s = 1, section_count do
    if math.random() < 0.3 and s > 1 then
      -- Sub-heading
      lines[#lines + 1] = "### " .. random_word():sub(1, 1):upper() .. random_word():sub(2) .. " " .. random_word()
      lines[#lines + 1] = ""
    end
    -- Paragraph
    for _, l in ipairs(random_paragraph()) do
      lines[#lines + 1] = l
    end
    lines[#lines + 1] = ""
    -- Sometimes a bullet list
    if math.random() < 0.4 then
      for _ = 1, math.random(3, 7) do
        lines[#lines + 1] = "- " .. random_sentence()
      end
      lines[#lines + 1] = ""
    end
    -- Sometimes a code fence
    if math.random() < 0.3 then
      lines[#lines + 1] = "```" .. random_language()
      for _ = 1, math.random(5, 15) do
        lines[#lines + 1] = "  " .. random_sentence()
      end
      lines[#lines + 1] = "```"
      lines[#lines + 1] = ""
    end
  end
  return lines
end

local function generate_assistant_with_thinking()
  local lines = { "@Assistant:" }
  -- Prose before thinking
  for _, l in ipairs(random_paragraph(3, 8)) do
    lines[#lines + 1] = l
  end
  -- Thinking is always last in assistant messages
  lines[#lines + 1] = ""
  for _, l in ipairs(generate_thinking()) do
    lines[#lines + 1] = l
  end
  return lines
end

local function generate_tool_exchange(large)
  local all_lines = { "@Assistant:" }
  -- Brief prose before tool use
  if math.random() < 0.5 then
    all_lines[#all_lines + 1] = random_sentence() .. " " .. random_sentence()
    all_lines[#all_lines + 1] = ""
  end
  -- Tool use
  local tool_lines, id = generate_tool_use()
  for _, l in ipairs(tool_lines) do
    all_lines[#all_lines + 1] = l
  end
  -- Thinking AFTER tool use (thinking is always last in assistant messages)
  if math.random() < 0.6 then
    all_lines[#all_lines + 1] = ""
    for _, l in ipairs(generate_thinking(large and math.random(4, 8) or nil)) do
      all_lines[#all_lines + 1] = l
    end
  end
  -- Tool result (separate @You message)
  local result_lines = generate_tool_result(id, large and math.random(50, 100) or nil)
  return all_lines, result_lines
end

local function generate_multi_tool_exchange()
  local assistant_lines = { "@Assistant:" }
  assistant_lines[#assistant_lines + 1] = random_sentence()
  assistant_lines[#assistant_lines + 1] = ""
  local result_messages = {}
  local tool_count = math.random(2, 4)
  for t = 1, tool_count do
    local tool_lines, id = generate_tool_use()
    for _, l in ipairs(tool_lines) do
      assistant_lines[#assistant_lines + 1] = l
    end
    if t < tool_count then
      assistant_lines[#assistant_lines + 1] = ""
    end
    result_messages[#result_messages + 1] = generate_tool_result(id, math.random(10, 30))
  end
  -- Thinking is always last in assistant messages
  assistant_lines[#assistant_lines + 1] = ""
  for _, l in ipairs(generate_thinking(math.random(3, 6))) do
    assistant_lines[#assistant_lines + 1] = l
  end
  return assistant_lines, result_messages
end

-- ── Assemble the document ────────────────────────────────────────

local doc = {}

local function emit(lines)
  for _, l in ipairs(lines) do
    doc[#doc + 1] = l
  end
end

local function blank()
  doc[#doc + 1] = ""
end

-- Frontmatter
emit(generate_frontmatter())

-- Build conversation with a mix of patterns
local patterns = {
  -- Phase 1: Opening exchanges (prose-heavy)
  { type = "prose_exchange", count = 3 },
  -- Phase 2: Dense tool region (many tool calls clustered together)
  { type = "tool_exchange", count = 4 },
  { type = "multi_tool", count = 1 },
  { type = "tool_exchange_large", count = 2 },
  -- Phase 3: More prose
  { type = "prose_exchange_long", count = 2 },
  { type = "thinking_response", count = 2 },
  -- Phase 4: Another dense tool region
  { type = "multi_tool", count = 2 },
  { type = "tool_exchange_large", count = 3 },
  { type = "tool_exchange", count = 3 },
  -- Phase 5: Mixed
  { type = "prose_exchange", count = 2 },
  { type = "thinking_response", count = 1 },
  { type = "tool_exchange", count = 2 },
  { type = "prose_exchange_long", count = 2 },
  -- Phase 6: Final dense region
  { type = "multi_tool", count = 1 },
  { type = "tool_exchange_large", count = 2 },
  { type = "tool_exchange", count = 2 },
  { type = "thinking_response", count = 1 },
  { type = "prose_exchange_long", count = 1 },
}

for _, phase in ipairs(patterns) do
  for _ = 1, phase.count do
    blank()
    if phase.type == "prose_exchange" then
      emit(generate_you_message(false))
      blank()
      emit(generate_assistant_prose(false))
    elseif phase.type == "prose_exchange_long" then
      emit(generate_you_message(true))
      blank()
      emit(generate_assistant_prose(true))
    elseif phase.type == "thinking_response" then
      emit(generate_you_message(false))
      blank()
      emit(generate_assistant_with_thinking())
    elseif phase.type == "tool_exchange" then
      emit(generate_you_message(false))
      blank()
      local asst, result = generate_tool_exchange(false)
      emit(asst)
      blank()
      emit(result)
    elseif phase.type == "tool_exchange_large" then
      emit(generate_you_message(false))
      blank()
      local asst, result = generate_tool_exchange(true)
      emit(asst)
      blank()
      emit(result)
    elseif phase.type == "multi_tool" then
      emit(generate_you_message(false))
      blank()
      local asst, results = generate_multi_tool_exchange()
      emit(asst)
      for _, result in ipairs(results) do
        blank()
        emit(result)
      end
    end
  end
end

-- Pad if under 5000 lines by adding more prose exchanges
while #doc < 4800 do
  blank()
  emit(generate_you_message(true))
  blank()
  emit(generate_assistant_prose(true))
end

-- ── Write output ─────────────────────────────────────────────────

local f = assert(io.open(OUTPUT, "w"))
for _, line in ipairs(doc) do
  f:write(line, "\n")
end
f:close()

print(string.format("Generated %d lines -> %s", #doc, OUTPUT))

-- ── Self-verification ───────────────────────────────────────────
-- Re-read the file through Flemma's parser and verify that the AST
-- sees the same structural elements we intended to generate. Catches
-- format bugs that would produce broken folds.

local has_flemma, parser = pcall(require, "flemma.parser")
if not has_flemma then
  print("(skipping verification — flemma.parser not in rtp)")
  return
end

require("flemma").setup({})

local bufnr = vim.api.nvim_create_buf(false, false)
vim.api.nvim_set_current_buf(bufnr)

local verify_lines = {}
for line in io.lines(OUTPUT) do
  verify_lines[#verify_lines + 1] = line
end
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, verify_lines)
vim.bo[bufnr].filetype = "chat"

local doc_ast = parser.get_parsed_document(bufnr)

local counts = { tool_use = 0, tool_result = 0, thinking = 0, text = 0, job_result = 0 }
for _, msg in ipairs(doc_ast.messages) do
  for _, seg in ipairs(msg.segments) do
    counts[seg.kind] = (counts[seg.kind] or 0) + 1
  end
end

local has_fm = doc_ast.frontmatter ~= nil

print(string.format(
  "Verified:  messages=%d  tool_use=%d  tool_result=%d  thinking=%d  text=%d  frontmatter=%s",
  #doc_ast.messages, counts.tool_use, counts.tool_result, counts.thinking, counts.text,
  has_fm and "yes" or "NO"
))

local errors = {}
if counts.tool_use == 0 then errors[#errors + 1] = "no tool_use segments parsed" end
if counts.tool_result == 0 then errors[#errors + 1] = "no tool_result segments parsed" end
if counts.thinking == 0 then errors[#errors + 1] = "no thinking segments parsed" end
if not has_fm then errors[#errors + 1] = "no frontmatter detected" end
if counts.tool_use ~= counts.tool_result then
  errors[#errors + 1] = string.format(
    "tool_use/tool_result mismatch: %d vs %d", counts.tool_use, counts.tool_result
  )
end

if #errors > 0 then
  for _, e in ipairs(errors) do
    io.stderr:write("ERROR: " .. e .. "\n")
  end
  os.exit(1)
end

print("All structural checks passed.")
