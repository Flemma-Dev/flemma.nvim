--- In-process LSP server for .chat buffers
--- Provides hover inspection of AST nodes. Experimental feature.
---@class flemma.Lsp
local M = {}

local ast = require("flemma.ast")
local dump = require("flemma.ast.dump")
local log = require("flemma.logging")
local navigation = require("flemma.navigation")
local parser = require("flemma.parser")

---Build a markdown hover string from an AST node using the dump module.
---@param node flemma.ast.DocumentNode|flemma.ast.MessageNode|flemma.ast.Segment|flemma.ast.FrontmatterNode
---@return string markdown
local function node_to_markdown(node)
  local lines = dump.tree(node, { depth = 1 })
  return "```flemma-ast\n" .. table.concat(lines, "\n") .. "\n```"
end

---Extract and validate buffer + position from LSP textDocument params.
---Converts LSP 0-indexed positions to 1-indexed AST coordinates.
---@param params table LSP TextDocumentPositionParams
---@param label string Log label for this request type (e.g. "hover", "definition")
---@return integer|nil bufnr Valid buffer number, or nil on failure
---@return integer lnum 1-indexed line number
---@return integer col 1-indexed column number
local function resolve_params(params, label)
  local uri = params.textDocument.uri
  local bufnr = vim.uri_to_bufnr(uri)

  if not vim.api.nvim_buf_is_valid(bufnr) then
    log.warn("lsp " .. label .. ": buffer " .. bufnr .. " is invalid (uri=" .. uri .. ")")
    return nil, 0, 0
  end

  local lnum = params.position.line + 1
  local col = params.position.character + 1
  log.debug("lsp " .. label .. ": " .. uri .. "#L" .. lnum .. "C" .. col .. " \u{2192} bufnr=" .. bufnr)
  return bufnr, lnum, col
end

---Build an LSP Hover response from a markdown string.
---@param markdown string
---@return table result LSP Hover response
local function hover_response(markdown)
  return {
    contents = {
      kind = "markdown",
      value = markdown,
    },
  }
end

---Handle a textDocument/hover request.
---@param params table LSP HoverParams
---@return table|nil result LSP Hover response or nil
local function handle_hover(params)
  local bufnr, lnum, col = resolve_params(params, "hover")
  if not bufnr then
    return nil
  end

  local doc = parser.get_parsed_document(bufnr)

  log.debug(
    "lsp hover: parsed document with "
      .. #doc.messages
      .. " messages, "
      .. #doc.errors
      .. " errors"
      .. (doc.frontmatter and ", has frontmatter" or "")
  )

  local seg, msg = ast.find_segment_at_position(doc, lnum, col)

  if seg and msg then
    -- Build a concise segment identity for the log
    local seg_detail = seg.kind
    if seg.kind == "expression" then
      ---@cast seg flemma.ast.ExpressionSegment
      seg_detail = seg_detail .. " code=" .. seg.code:sub(1, 40)
    elseif seg.kind == "tool_use" then
      ---@cast seg flemma.ast.ToolUseSegment
      seg_detail = seg_detail .. " name=" .. seg.name .. " id=" .. seg.id
    elseif seg.kind == "tool_result" then
      ---@cast seg flemma.ast.ToolResultSegment
      seg_detail = seg_detail .. " tool_use_id=" .. seg.tool_use_id .. " error=" .. tostring(seg.is_error)
    elseif seg.kind == "thinking" then
      ---@cast seg flemma.ast.ThinkingSegment
      seg_detail = seg_detail .. " len=" .. #seg.content .. " redacted=" .. tostring(seg.redacted or false)
    elseif seg.kind == "text" then
      ---@cast seg flemma.ast.TextSegment
      seg_detail = seg_detail .. " len=" .. #seg.value
    end

    log.debug("lsp hover: matched " .. seg_detail .. " in @" .. msg.role .. " message")

    local markdown = node_to_markdown(seg)
    log.trace("lsp hover: response markdown (" .. #markdown .. " bytes):\n" .. markdown)
    return hover_response(markdown)
  end

  -- No segment but within a message (e.g., role marker line)
  if msg then
    log.debug("lsp hover: role marker for @" .. msg.role .. " at L" .. lnum)
    return hover_response(node_to_markdown(msg))
  end

  -- Check frontmatter
  local fm = doc.frontmatter
  if fm and fm.position then
    ---@cast fm flemma.ast.FrontmatterNode
    local pos = fm.position --[[@as flemma.ast.Position]]
    local fm_end = pos.end_line or pos.start_line
    if lnum >= pos.start_line and lnum <= fm_end then
      log.debug("lsp hover: frontmatter (" .. fm.language .. ") at L" .. lnum)
      return hover_response(node_to_markdown(fm))
    end
  end

  log.debug("lsp hover: no node at L" .. lnum .. ":C" .. col .. " in buffer " .. bufnr)
  return nil
end

---Handle a textDocument/definition request.
---Resolves include expressions (@./file, {{ include() }}) to file locations.
---@param params table LSP DefinitionParams
---@return table|nil result LSP Location or nil
local function handle_definition(params)
  local bufnr, lnum, col = resolve_params(params, "definition")
  if not bufnr then
    return nil
  end

  local resolved_path = navigation.resolve_include_path(bufnr, lnum, col)
  if not resolved_path then
    log.debug("lsp definition: no include path resolved")
    return nil
  end

  if vim.fn.filereadable(resolved_path) ~= 1 then
    log.debug("lsp definition: resolved path not readable: " .. resolved_path)
    return nil
  end

  log.debug("lsp definition: jumping to " .. resolved_path)
  return {
    uri = vim.uri_from_fname(resolved_path),
    range = {
      start = { line = 0, character = 0 },
      ["end"] = { line = 0, character = 0 },
    },
  }
end

---Create the in-process LSP server dispatch table.
---@param dispatchers vim.lsp.rpc.Dispatchers
---@return vim.lsp.rpc.PublicClient
local function create_server(dispatchers)
  local closing = false
  log.debug("lsp: in-process server created")

  return {
    request = function(method, params, callback)
      log.trace("lsp server: request " .. method)
      if method == "initialize" then
        log.debug("lsp server: initialize — advertising hoverProvider, definitionProvider")
        callback(nil, {
          capabilities = {
            hoverProvider = true,
            definitionProvider = true,
          },
        })
        return true, 1
      elseif method == "shutdown" then
        log.debug("lsp server: shutdown requested")
        closing = true
        callback(nil, nil)
        return true, 2
      elseif method == "textDocument/hover" then
        local result = handle_hover(params)
        log.debug("lsp server: hover response " .. (result and "returned" or "nil (no match)"))
        callback(nil, result)
        return true, 3
      elseif method == "textDocument/definition" then
        local result = handle_definition(params)
        log.debug("lsp server: definition response " .. (result and "returned" or "nil (no match)"))
        callback(nil, result)
        return true, 4
      else
        log.debug("lsp server: unhandled method " .. method)
        callback(nil, nil)
        return true, 5
      end
    end,

    notify = function(method, _params)
      log.trace("lsp server: notify " .. method)
      if method == "exit" then
        log.info("lsp server: exit notification — shutting down")
        dispatchers.on_exit(0, 0)
      end
      return true
    end,

    is_closing = function()
      return closing
    end,

    terminate = function()
      log.debug("lsp server: terminate called")
      closing = true
    end,
  }
end

---Attach the LSP client to a buffer.
---Uses vim.lsp.start() which automatically deduplicates by name + root_dir.
---@param bufnr integer
function M.attach(bufnr)
  local buf_name = vim.api.nvim_buf_get_name(bufnr)
  log.debug("lsp: attaching to buffer " .. bufnr .. " (" .. (buf_name ~= "" and buf_name or "<unnamed>") .. ")")
  if buf_name == "" then
    log.warn("lsp: buffer " .. bufnr .. " has no name — URI resolution may fail for hover requests")
  end
  vim.lsp.start({
    name = "flemma",
    cmd = create_server,
    root_dir = vim.fn.getcwd(),
  }, {
    bufnr = bufnr,
  })
end

---Set up the LSP server. Registers a FileType autocmd for chat buffers.
---Only call this when experimental.lsp is enabled.
function M.setup()
  log.info("lsp: experimental LSP server enabled")
  local augroup = vim.api.nvim_create_augroup("FlemmaLsp", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = "chat",
    callback = function(ev)
      M.attach(ev.buf)
    end,
  })
end

return M
