-- Flemma profiling instrumentation — sourced inside Neovim by the harness.
-- Activates jit.p (LuaJIT sampler), :profile (VimScript), autocmd event counters,
-- and wraps key Flemma functions (when loaded) with call counting + timing.
-- Results written to files under PROFILE_DIR (set by the harness via env var).

local PROFILE_DIR = os.getenv("FLEMMA_PROFILE_DIR") or "/tmp/flemma-profile"
local JITP_OUT = PROFILE_DIR .. "/jit-profile.txt"
local VIMP_OUT = PROFILE_DIR .. "/vim-profile.log"
local REPORT_OUT = PROFILE_DIR .. "/report.txt"
local READY_FLAG = PROFILE_DIR .. "/ready"
local DONE_FLAG = PROFILE_DIR .. "/done"

local jitp_ok, jitp = pcall(require, "jit.p")
if jitp_ok then
  jitp.start("fli1", JITP_OUT)
end

vim.cmd("profile start " .. VIMP_OUT)
vim.cmd("profile func *")
vim.cmd("profile file *")

-- ── Function wrapping (Flemma + other hot-path modules) ──────────────
local function_stats = {}
local originals = {}

local function wrap(mod_path, fn_name, label)
  local ok, mod = pcall(require, mod_path)
  if not ok or type(mod) ~= "table" or not mod[fn_name] then return end
  originals[label] = { mod = mod, fn_name = fn_name, fn = mod[fn_name] }
  function_stats[label] = { total_ns = 0, calls = 0, max_ns = 0 }
  mod[fn_name] = function(...)
    local t0 = vim.uv.hrtime()
    local ret = { originals[label].fn(...) }
    local dt = vim.uv.hrtime() - t0
    local s = function_stats[label]
    s.total_ns = s.total_ns + dt
    s.calls = s.calls + 1
    if dt > s.max_ns then s.max_ns = dt end
    return unpack(ret)
  end
end

-- Flemma core
wrap("flemma.parser", "get_parsed_document", "parser.get_parsed_document")
wrap("flemma.parser", "parse_lines", "parser.parse_lines")
wrap("flemma.processor", "evaluate_frontmatter_if_changed", "processor.eval_fm")
wrap("flemma.ui", "update_ui", "ui.update_ui")
wrap("flemma.ui.folding", "invalidate_folds", "folding.invalidate_folds")
wrap("flemma.ui.folding", "fold_completed_blocks", "folding.fold_completed_blocks")
wrap("flemma.ui.folding", "get_fold_level", "folding.get_fold_level")
wrap("flemma.bridge", "update_ui", "bridge.update_ui")
wrap("flemma.ui", "update_cursorline", "ui.update_cursorline")
wrap("flemma.usage.prefetch", "schedule_fetch", "usage.schedule_fetch")

-- ── Autocmd event tracking ───────────────────────────────────────────
local event_times = {}
local augroup = vim.api.nvim_create_augroup("FlemmaProfile", { clear = true })
for _, ev in ipairs({
  "TextChanged", "TextChangedI", "TextChangedP",
  "CursorMoved", "CursorMovedI",
  "CursorHold", "CursorHoldI",
  "InsertEnter", "InsertLeave", "InsertCharPre",
  "BufModifiedSet",
}) do
  vim.api.nvim_create_autocmd(ev, {
    group = augroup,
    callback = function()
      local t0 = vim.uv.hrtime()
      vim.schedule(function()
        local dt = vim.uv.hrtime() - t0
        local e = event_times[ev]
        if not e then
          e = { total_ns = 0, calls = 0, max_ns = 0 }
          event_times[ev] = e
        end
        e.total_ns = e.total_ns + dt
        e.calls = e.calls + 1
        if dt > e.max_ns then e.max_ns = dt end
      end)
    end,
  })
end

local started = vim.uv.hrtime()

vim.api.nvim_create_user_command("FlemmaProfileDump", function()
  if jitp_ok then jitp.stop() end
  vim.cmd("profile stop")

  local elapsed_s = (vim.uv.hrtime() - started) / 1e9
  local lines = {}
  lines[#lines + 1] = string.format("=== COMBINED PROFILE REPORT (%.1fs) ===", elapsed_s)
  lines[#lines + 1] = string.format("Buffer: %s", vim.api.nvim_buf_get_name(0))
  lines[#lines + 1] = string.format("Lines: %d", vim.api.nvim_buf_line_count(0))
  lines[#lines + 1] = ""

  -- Window/buffer options
  lines[#lines + 1] = "--- Buffer/Window Options ---"
  lines[#lines + 1] = string.format("  foldmethod: %s", vim.wo.foldmethod)
  lines[#lines + 1] = string.format("  foldexpr: %s", vim.wo.foldexpr)
  lines[#lines + 1] = string.format("  indentexpr: %s", vim.bo.indentexpr)
  lines[#lines + 1] = string.format("  syntax: %s", vim.bo.syntax)
  lines[#lines + 1] = string.format("  filetype: %s", vim.bo.filetype)
  lines[#lines + 1] = string.format("  conceallevel: %d", vim.wo.conceallevel)
  lines[#lines + 1] = ""

  -- Function timings
  lines[#lines + 1] = "--- Function Timings ---"
  lines[#lines + 1] = string.format("%-45s %8s %10s %10s %10s", "Function", "Calls", "Total ms", "Avg ms", "Max ms")
  lines[#lines + 1] = string.rep("-", 87)
  local function_sorted = {}
  for label, data in pairs(function_stats) do
    function_sorted[#function_sorted + 1] = { label = label, total_ns = data.total_ns, calls = data.calls, max_ns = data.max_ns }
  end
  table.sort(function_sorted, function(a, b) return a.total_ns > b.total_ns end)
  for _, e in ipairs(function_sorted) do
    lines[#lines + 1] = string.format("%-45s %8d %10.2f %10.3f %10.2f",
      e.label, e.calls, e.total_ns / 1e6, e.total_ns / e.calls / 1e6, e.max_ns / 1e6)
  end
  lines[#lines + 1] = ""

  -- Event summary
  lines[#lines + 1] = "--- Autocmd Event Totals ---"
  lines[#lines + 1] = string.format("%-25s %8s %10s %10s %10s", "Event", "Calls", "Total ms", "Avg ms", "Max ms")
  lines[#lines + 1] = string.rep("-", 67)
  local sorted = {}
  for ev, data in pairs(event_times) do
    sorted[#sorted + 1] = { ev = ev, total_ns = data.total_ns, calls = data.calls, max_ns = data.max_ns }
  end
  table.sort(sorted, function(a, b) return a.total_ns > b.total_ns end)
  for _, e in ipairs(sorted) do
    lines[#lines + 1] = string.format("%-25s %8d %10.2f %10.3f %10.2f",
      e.ev, e.calls, e.total_ns / 1e6, e.total_ns / e.calls / 1e6, e.max_ns / 1e6)
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "--- LuaJIT Sampling Profile (top entries) ---"
  lines[#lines + 1] = "Full: " .. JITP_OUT
  local f = io.open(JITP_OUT, "r")
  if f then
    local n = 0
    for line in f:lines() do
      lines[#lines + 1] = "  " .. line
      n = n + 1
      if n >= 80 then
        lines[#lines + 1] = "  ... (see full file)"
        break
      end
    end
    f:close()
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "--- VimScript Profile (top functions) ---"
  lines[#lines + 1] = "Full: " .. VIMP_OUT
  local f2 = io.open(VIMP_OUT, "r")
  if f2 then
    local content = f2:read("*a")
    f2:close()
    local section = content:match("FUNCTIONS SORTED ON TOTAL TIME(.-)FUNCTIONS SORTED ON SELF TIME")
    if not section then section = content end
    local n = 0
    for line in section:gmatch("[^\n]+") do
      lines[#lines + 1] = "  " .. line
      n = n + 1
      if n >= 60 then
        lines[#lines + 1] = "  ... (see full file)"
        break
      end
    end
  end

  local report = table.concat(lines, "\n")
  local rf = io.open(REPORT_OUT, "w")
  if rf then rf:write(report .. "\n"); rf:close() end

  local df = io.open(DONE_FLAG, "w")
  if df then df:write("done\n"); df:close() end

  vim.cmd("qa!")
end, {})

local rf = io.open(READY_FLAG, "w")
if rf then rf:write("ready\n"); rf:close() end
