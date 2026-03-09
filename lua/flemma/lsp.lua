--- In-process LSP server for .chat buffers
--- Provides hover inspection of AST nodes. Experimental feature.
---@class flemma.Lsp
local M = {}

local ast = require("flemma.ast")
local log = require("flemma.logging")
local parser = require("flemma.parser")
local json = require("flemma.utilities.json")

---Serialize an AST segment to a markdown hover string.
---@param seg flemma.ast.Segment
---@param msg flemma.ast.MessageNode
---@return string markdown
local function segment_to_markdown(seg, msg)
  local lines = {}

  -- Header: segment kind
  local kind_label = seg.kind:sub(1, 1):upper() .. seg.kind:sub(2) .. "Segment"
  table.insert(lines, "### " .. kind_label)
  table.insert(lines, "")
  table.insert(lines, "**Role:** " .. msg.role)

  -- Kind-specific fields
  if seg.kind == "expression" then
    ---@cast seg flemma.ast.ExpressionSegment
    table.insert(lines, "**Code:** `" .. seg.code .. "`")
  elseif seg.kind == "thinking" then
    ---@cast seg flemma.ast.ThinkingSegment
    table.insert(lines, "**Redacted:** " .. tostring(seg.redacted or false))
    if seg.signature then
      table.insert(lines, "**Signature provider:** " .. seg.signature.provider)
    end
    table.insert(lines, "")
    table.insert(lines, "**Content:**")
    table.insert(lines, "")
    table.insert(lines, seg.content)
  elseif seg.kind == "tool_use" then
    ---@cast seg flemma.ast.ToolUseSegment
    table.insert(lines, "**Tool:** `" .. seg.name .. "`")
    table.insert(lines, "**ID:** `" .. seg.id .. "`")
    table.insert(lines, "")
    table.insert(lines, "**Input:**")
    table.insert(lines, "```json")
    table.insert(lines, json.encode(seg.input))
    table.insert(lines, "```")
  elseif seg.kind == "tool_result" then
    ---@cast seg flemma.ast.ToolResultSegment
    table.insert(lines, "**Tool Use ID:** `" .. seg.tool_use_id .. "`")
    table.insert(lines, "**Error:** " .. tostring(seg.is_error))
    if seg.status then
      table.insert(lines, "**Status:** " .. seg.status)
    end
    table.insert(lines, "")
    table.insert(lines, "**Content:**")
    table.insert(lines, "```")
    table.insert(lines, seg.content)
    table.insert(lines, "```")
  elseif seg.kind == "text" then
    ---@cast seg flemma.ast.TextSegment
    local preview = seg.value
    if #preview > 200 then
      preview = preview:sub(1, 200) .. "..."
    end
    table.insert(lines, "**Content:** " .. vim.trim(preview))
  elseif seg.kind == "aborted" then
    ---@cast seg flemma.ast.AbortedSegment
    table.insert(lines, "**Message:** " .. seg.message)
  end

  -- Position info
  if seg.position then
    table.insert(lines, "")
    local pos_parts = { "L" .. seg.position.start_line }
    if seg.position.start_col then
      pos_parts[1] = pos_parts[1] .. ":C" .. seg.position.start_col
    end
    if seg.position.end_line then
      local end_part = "L" .. seg.position.end_line
      if seg.position.end_col then
        end_part = end_part .. ":C" .. seg.position.end_col
      end
      table.insert(pos_parts, end_part)
    end
    table.insert(lines, "**Position:** " .. table.concat(pos_parts, " \u{2192} "))
  end

  return table.concat(lines, "\n")
end

---Handle a textDocument/hover request.
---@param params table LSP HoverParams
---@return table|nil result LSP Hover response or nil
local function handle_hover(params)
  local uri = params.textDocument.uri
  local bufnr = vim.uri_to_bufnr(uri)

  log.debug("lsp hover: uri=" .. uri .. " -> bufnr=" .. bufnr)

  if not vim.api.nvim_buf_is_valid(bufnr) then
    log.warn("lsp hover: buffer " .. bufnr .. " is invalid (uri=" .. uri .. ")")
    return nil
  end

  -- LSP positions are 0-indexed; AST positions are 1-indexed
  local lnum = params.position.line + 1
  local col = params.position.character + 1

  log.debug("lsp hover: position LSP(L" .. params.position.line .. ":C" .. params.position.character .. ") -> AST(L" .. lnum .. ":C" .. col .. ")")

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

  if not seg or not msg then
    log.debug("lsp hover: no segment found at L" .. lnum .. ":C" .. col .. " in buffer " .. bufnr)
    return nil
  end

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

  local markdown = segment_to_markdown(seg, msg)

  log.trace("lsp hover: response markdown (" .. #markdown .. " bytes):\n" .. markdown)

  return {
    contents = {
      kind = "markdown",
      value = markdown,
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
        log.debug("lsp server: initialize — advertising hoverProvider")
        callback(nil, {
          capabilities = {
            hoverProvider = true,
          },
        })
        return true, 1
      elseif method == "shutdown" then
        log.info("lsp server: shutdown requested")
        closing = true
        callback(nil, nil)
        return true, 2
      elseif method == "textDocument/hover" then
        local result = handle_hover(params)
        log.debug("lsp server: hover response " .. (result and "returned" or "nil (no match)"))
        callback(nil, result)
        return true, 3
      else
        log.debug("lsp server: unhandled method " .. method)
        callback(nil, nil)
        return true, 4
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
      log.info("lsp server: terminate called")
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
