--- Schema tree navigation utilities shared by the store and proxy modules.
---
--- Both modules need to traverse the schema tree to locate the node at a given
--- dot-delimited path, unwrapping OptionalNode wrappers at intermediate steps so
--- that optional sub-objects are navigable. Whether the final node is also unwrapped
--- is caller-specific and controlled via `opts.unwrap_leaf`.
---@class flemma.schema.navigation
local M = {}

local MAX_UNWRAP_DEPTH = 100

--- Walk a node through any OptionalNode wrappers to reach the concrete node.
--- Errors if unwrapping exceeds MAX_UNWRAP_DEPTH, which would indicate a cycle
--- in the schema graph (impossible with the current DSL, but guarded defensively).
---@param node flemma.schema.Node
---@return flemma.schema.Node
function M.unwrap_optional(node)
  local depth = 0
  local inner = node:get_inner_schema()
  while inner do
    depth = depth + 1
    if depth > MAX_UNWRAP_DEPTH then
      error("schema cycle detected: unwrap_optional exceeded " .. MAX_UNWRAP_DEPTH .. " iterations")
    end
    node = inner
    inner = node:get_inner_schema()
  end
  return node
end

---@class flemma.schema.NavigateOpts
---@field unwrap_leaf? boolean Unwrap OptionalNode on the returned leaf node (default: false)

--- Navigate the schema tree from root to the given dot-delimited path.
---
--- At each step, the current parent node is unwrapped through any OptionalNode
--- wrappers before calling get_child_schema, so that optional objects are
--- traversable. Whether the final (leaf) node itself is also unwrapped is
--- controlled by opts.unwrap_leaf:
---
---   { unwrap_leaf = true }  — strip any trailing OptionalNode from the result
---                             (used by the store, which performs type detection
---                             on the unwrapped node via is_list())
---   { unwrap_leaf = false } — return the leaf as-is, preserving OptionalNode
---   (default)                 (used by the proxy, so that optional fields
---                             accept nil writes via OptionalNode.validate_value)
---
---@param root flemma.schema.Node Root schema node
---@param path string Dot-delimited path, e.g. "tools.auto_approve"
---@param opts? flemma.schema.NavigateOpts
---@return flemma.schema.Node?
function M.navigate_schema(root, path, opts)
  local parts = vim.split(path, ".", { plain = true })
  local node = root
  for _, part in ipairs(parts) do
    local parent = M.unwrap_optional(node)
    local child = parent:get_child_schema(part)
    if not child then
      return nil
    end
    node = child
  end
  if opts and opts.unwrap_leaf then
    return M.unwrap_optional(node)
  end
  return node
end

return M
