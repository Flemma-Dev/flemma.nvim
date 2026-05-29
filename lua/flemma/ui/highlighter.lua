--- TreeSitter-powered syntax highlighter for tool preview chunks.
--- Parses text via string parser, extracts highlight captures, and builds
--- {text, hl_group} chunk arrays suitable for virt_lines.
---@class flemma.ui.Highlighter
local M = {}

local log = require("flemma.logging")

local BASE_HL_GROUP = "FlemmaToolPreview"

---@type table<string, table<string, {[1]: string, [2]: string}[][]>>
local cache = {}

---@param text string Multi-line text to highlight
---@param lang string TreeSitter language name (e.g., "bash", "lua", "python")
---@param callback fun(lines_chunks: {[1]: string, [2]: string}[][]|nil)
function M.highlight(text, lang, callback)
  local lang_cache = cache[lang]
  if lang_cache then
    local cached = lang_cache[text]
    if cached then
      log.trace("highlighter.highlight(): cache hit for lang=" .. lang)
      callback(cached)
      return
    end
  end

  log.debug("highlighter.highlight(): cache miss for lang=" .. lang .. ", scheduling parse")

  vim.schedule(function()
    local lc = cache[lang]
    if lc then
      local cached = lc[text]
      if cached then
        log.trace("highlighter.highlight(): cache hit after schedule for lang=" .. lang)
        callback(cached)
        return
      end
    end

    local ok_parser, parser = pcall(vim.treesitter.get_string_parser, text, lang)
    if not ok_parser then
      log.debug("highlighter.highlight(): no grammar for lang=" .. lang .. " (" .. tostring(parser) .. ")")
      callback(nil)
      return
    end

    local ok_parse, trees = pcall(parser.parse, parser)
    if not ok_parse or not trees or #trees == 0 then
      log.warn("highlighter.highlight(): parse failed for lang=" .. lang .. " (" .. tostring(trees) .. ")")
      callback(nil)
      return
    end

    local ok_query, query = pcall(vim.treesitter.query.get, lang, "highlights")
    if not ok_query or not query then
      log.debug("highlighter.highlight(): no highlights query for lang=" .. lang)
      callback(nil)
      return
    end

    local root = trees[1]:root()

    local lines = vim.split(text, "\n", { plain = true })
    local line_count = #lines

    ---@type {start_col: integer, end_col: integer, hl: string}[][]
    local line_captures = {}
    for i = 1, line_count do
      line_captures[i] = {}
    end

    local ok_iter, err = pcall(function()
      for capture_id, node in query:iter_captures(root, text) do
        local capture_name = query.captures[capture_id]
        if capture_name and capture_name:sub(1, 1) ~= "_" then
          local start_row, start_col, end_row, end_col = node:range()
          local hl_group = "@" .. capture_name .. "." .. lang

          for row = start_row, end_row do
            if row >= 0 and row < line_count then
              local sc = row == start_row and start_col or 0
              local ec = row == end_row and end_col or #lines[row + 1]
              if sc < ec then
                table.insert(line_captures[row + 1], { start_col = sc, end_col = ec, hl = hl_group })
              end
            end
          end
        end
      end
    end)
    if not ok_iter then
      log.warn("highlighter.highlight(): iter_captures failed for lang=" .. lang .. " (" .. tostring(err) .. ")")
      callback(nil)
      return
    end

    ---@type {[1]: string, [2]: string}[][]
    local result = {}
    for i = 1, line_count do
      local line_text = lines[i]
      local captures = line_captures[i]
      local len = #line_text

      if #captures == 0 or len == 0 then
        result[i] = { { line_text, BASE_HL_GROUP } }
      else
        ---@type string[]
        local hl_map = {}
        for byte = 0, len - 1 do
          hl_map[byte] = BASE_HL_GROUP
        end
        for _, cap in ipairs(captures) do
          for byte = cap.start_col, math.min(cap.end_col, len) - 1 do
            hl_map[byte] = cap.hl
          end
        end

        ---@type {[1]: string, [2]: string}[]
        local chunks = {}
        local run_start = 0
        local run_hl = hl_map[0]
        for byte = 1, len - 1 do
          if hl_map[byte] ~= run_hl then
            chunks[#chunks + 1] = { line_text:sub(run_start + 1, byte), run_hl }
            run_start = byte
            run_hl = hl_map[byte]
          end
        end
        chunks[#chunks + 1] = { line_text:sub(run_start + 1), run_hl }

        result[i] = chunks
      end
    end

    if not cache[lang] then
      cache[lang] = {}
    end
    cache[lang][text] = result

    log.debug("highlighter.highlight(): parsed and cached lang=" .. lang .. " (" .. line_count .. " lines)")
    callback(result)
  end)
end

---Clear the highlight cache. Intended for testing only.
function M._clear_cache()
  cache = {}
end

return M
