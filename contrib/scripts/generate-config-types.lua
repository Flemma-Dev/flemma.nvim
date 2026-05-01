--- Generate EmmyLua type annotations from the config schema.
---
--- Usage: nvim --headless --noplugin -u NONE --cmd 'set rtp^=.' -l contrib/scripts/generate-config-types.lua
---
--- Boots the built-in registries, walks the schema tree (lua/flemma/config/schema.lua),
--- and emits lua/flemma/config/types.lua with full EmmyLua annotations.

local schema_types = require("flemma.schema.types")
local navigation = require("flemma.schema.navigation")

---@type fun(path: string, node: flemma.schema.ObjectNode, class_name: string)?
local enqueue_referenced_object

-- ---------------------------------------------------------------------------
-- Schema node type detection helpers
-- ---------------------------------------------------------------------------

---@param node flemma.schema.Node
---@return boolean
local function is_string_node(node)
  return getmetatable(node) == schema_types.StringNode or getmetatable(node) == schema_types.LoadableNode
end

---@param node flemma.schema.Node
---@return boolean
local function is_integer_node(node)
  return getmetatable(node) == schema_types.IntegerNode
end

---@param node flemma.schema.Node
---@return boolean
local function is_number_node(node)
  return getmetatable(node) == schema_types.NumberNode
end

---@param node flemma.schema.Node
---@return boolean
local function is_boolean_node(node)
  return getmetatable(node) == schema_types.BooleanNode
end

---@param node flemma.schema.Node
---@return boolean
local function is_enum_node(node)
  return getmetatable(node) == schema_types.EnumNode
end

---@param node flemma.schema.Node
---@return boolean
local function is_list_node(node)
  return getmetatable(node) == schema_types.ListNode
end

---@param node flemma.schema.Node
---@return boolean
local function is_map_node(node)
  return getmetatable(node) == schema_types.MapNode
end

---@param node flemma.schema.Node
---@return boolean
local function is_object_node(node)
  return getmetatable(node) == schema_types.ObjectNode
end

---@param node flemma.schema.Node
---@return boolean
local function is_optional_node(node)
  return getmetatable(node) == schema_types.OptionalNode
end

---@param node flemma.schema.Node
---@return boolean
local function is_union_node(node)
  return getmetatable(node) == schema_types.UnionNode
end

---@param node flemma.schema.Node
---@return boolean
local function is_literal_node(node)
  return getmetatable(node) == schema_types.LiteralNode
end

---@param node flemma.schema.Node
---@return boolean
local function is_func_node(node)
  return getmetatable(node) == schema_types.FuncNode
end

---@param node flemma.schema.Node
---@return boolean
local function is_nullable_node(node)
  return getmetatable(node) == schema_types.NullableNode
end

-- ---------------------------------------------------------------------------
-- Registry boot — populate built-in entries so DISCOVER caches resolve
-- ---------------------------------------------------------------------------

--- Boot the registries to populate built-in entries.
--- After this, the schema's DISCOVER callbacks can resolve built-in keys
--- and all_known_fields() will include DISCOVER-cached entries.
---@param schema flemma.schema.ObjectNode Root config schema
local function boot_registries(schema)
  -- The config store must be initialized before registries can register
  -- their module defaults. init() materializes schema defaults into L10.
  require("flemma.config").init(schema)

  -- Providers: setup() is safe (just loads and registers built-in modules)
  require("flemma.provider.registry").setup()

  -- Tools: setup() registers built-ins then reads config (defaults = no user modules)
  require("flemma.tools").setup()

  -- Sandbox: setup() registers bwrap then does a simple config validation
  require("flemma.sandbox").setup()

  -- Trigger DISCOVER on schema nodes so caches are populated.
  -- Walk each registry and poke the corresponding schema node.
  local providers = require("flemma.provider.registry").get_all()
  local parameters_node = navigation.unwrap_optional(navigation.navigate_schema(schema, "parameters"))
  for name, entry in pairs(providers) do
    if entry.config_schema then
      parameters_node:get_child_schema(name)
    end
  end

  local tools_registry = require("flemma.tools.registry")
  local all_tools = tools_registry.get_all({ include_disabled = true })
  local tools_node = navigation.unwrap_optional(navigation.navigate_schema(schema, "tools"))
  for name, def in pairs(all_tools) do
    if def.metadata and def.metadata.config_schema then
      tools_node:get_child_schema(name)
    end
  end

  local sandbox = require("flemma.sandbox")
  local all_backends = sandbox.get_all()
  local backends_node = navigation.unwrap_optional(navigation.navigate_schema(schema, "sandbox.backends"))
  for _, entry in ipairs(all_backends) do
    if entry.config_schema then
      backends_node:get_child_schema(entry.name)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Type string generation
-- ---------------------------------------------------------------------------

--- Convert a schema node to its EmmyLua type string.
---@param node flemma.schema.Node
---@param class_name_for_objects? string Class name to use if node is an ObjectNode
---@return string
local function node_to_type(node, class_name_for_objects)
  if node._type_as then
    return node._type_as
  end

  if is_optional_node(node) or is_nullable_node(node) then
    return node_to_type(node:get_inner_schema(), class_name_for_objects)
  end

  if is_string_node(node) then
    return "string"
  end
  if is_integer_node(node) then
    return "integer"
  end
  if is_number_node(node) then
    return "number"
  end
  if is_boolean_node(node) then
    return "boolean"
  end

  if is_enum_node(node) then
    local quoted = {}
    for _, v in ipairs(node._values) do
      table.insert(quoted, '"' .. v .. '"')
    end
    return table.concat(quoted, "|")
  end

  if is_literal_node(node) then
    local v = node._value
    if v == false then
      return "false"
    end
    if v == true then
      return "true"
    end
    if v == nil then
      return "nil"
    end
    if type(v) == "string" then
      return '"' .. v .. '"'
    end
    return tostring(v)
  end

  if is_func_node(node) then
    return "fun(...)"
  end

  if is_list_node(node) then
    return node_to_type(node._item_schema) .. "[]"
  end

  if is_map_node(node) then
    return "table<" .. node_to_type(node._key_schema) .. ", " .. node_to_type(node._value_schema) .. ">"
  end

  if is_union_node(node) then
    local parts = {}
    for _, branch in ipairs(node._branches) do
      table.insert(parts, node_to_type(branch))
    end
    return table.concat(parts, "|")
  end

  if is_object_node(node) then
    ---@cast node flemma.schema.ObjectNode
    if node._class_as then
      if enqueue_referenced_object then
        enqueue_referenced_object("", node, node._class_as)
      end
      return node._class_as
    end
    if class_name_for_objects then
      return class_name_for_objects
    end
    local fields = {}
    local sorted_names = {}
    for name in pairs(node._fields) do
      table.insert(sorted_names, name)
    end
    table.sort(sorted_names)
    for _, name in ipairs(sorted_names) do
      table.insert(fields, name .. ": " .. node_to_type(node._fields[name]))
    end
    return "{ " .. table.concat(fields, ", ") .. " }"
  end

  return "any"
end

-- ---------------------------------------------------------------------------
-- Class name derivation
-- ---------------------------------------------------------------------------

---@param path string
---@return string
local function path_to_pascal(path)
  local parts = vim.split(path, ".", { plain = true })
  local result = {}
  for _, part in ipairs(parts) do
    for word in part:gmatch("[^_]+") do
      table.insert(result, word:sub(1, 1):upper() .. word:sub(2))
    end
  end
  return table.concat(result)
end

---@param path string
---@return string
local function derive_class_name(path)
  return "flemma.config." .. path_to_pascal(path)
end

-- ---------------------------------------------------------------------------
-- Alias tracking
-- ---------------------------------------------------------------------------

---@type table<string, string>
local pending_aliases = {}

---@type table<string, boolean>
local emitted_aliases = {}

-- ---------------------------------------------------------------------------
-- Output accumulator
-- ---------------------------------------------------------------------------

---@type string[]
local lines = {}

---@param line string
local function emit(line)
  table.insert(lines, line)
end

local function emit_blank()
  emit("")
end

-- ---------------------------------------------------------------------------
-- Alias collection
-- ---------------------------------------------------------------------------

--- Record an alias for a union node with _type_as, if not already seen.
---@param node flemma.schema.Node
local function collect_alias(node)
  if not node._type_as then
    return
  end
  local name = node._type_as
  if emitted_aliases[name] then
    return
  end
  -- Skip compound type strings (contain |) — inline type refs, not alias names
  if name:find("|", 1, true) then
    return
  end
  -- Only emit aliases for union nodes (not object type_as overrides)
  if not is_union_node(node) then
    return
  end
  local parts = {}
  for _, branch in ipairs(node._branches) do
    table.insert(parts, node_to_type(branch))
  end
  pending_aliases[name] = table.concat(parts, "|")
  emitted_aliases[name] = true
end

-- ---------------------------------------------------------------------------
-- Class emission (BFS)
-- ---------------------------------------------------------------------------

---@type { path: string, node: flemma.schema.ObjectNode, class_name: string }[]
local class_queue = {}

---@type table<string, boolean>
local emitted_classes = {}

---@param path string
---@param node flemma.schema.ObjectNode
---@param class_name string
local function enqueue_class(path, node, class_name)
  if emitted_classes[class_name] then
    return
  end
  emitted_classes[class_name] = true
  table.insert(class_queue, { path = path, node = node, class_name = class_name })
end

enqueue_referenced_object = enqueue_class

---@param node flemma.schema.ObjectNode
---@return string?
local function enqueue_parent_class(node)
  if not node._extends or not node._extends._class_as then
    return nil
  end
  enqueue_class("", node._extends, node._extends._class_as)
  return node._extends._class_as
end

---@param parent_path string
---@param field_name string
---@param child_node flemma.schema.ObjectNode
---@return string class_name
local function resolve_child_class(parent_path, field_name, child_node)
  if child_node._type_as then
    return child_node._type_as
  end
  if child_node._class_as then
    enqueue_class("", child_node, child_node._class_as)
    return child_node._class_as
  end
  local child_path = parent_path ~= "" and (parent_path .. "." .. field_name) or field_name
  local class_name = derive_class_name(child_path)
  enqueue_parent_class(child_node)
  enqueue_class(child_path, child_node, class_name)
  return class_name
end

--- Emit a single @class block. Uses all_known_fields() which includes
--- both static fields and DISCOVER-cached entries from registry boot.
---@param path string
---@param node flemma.schema.ObjectNode
---@param class_name string
local function emit_class(path, node, class_name)
  local parent_class_name = enqueue_parent_class(node)
  if parent_class_name then
    emit("---@class " .. class_name .. " : " .. parent_class_name)
  else
    emit("---@class " .. class_name)
  end

  -- Collect all fields: static + DISCOVER-cached
  local field_names = {}
  local field_schemas = {}
  for name, schema in node:all_known_fields() do
    field_names[#field_names + 1] = name
    field_schemas[name] = schema
  end
  table.sort(field_names)

  for _, name in ipairs(field_names) do
    local child = field_schemas[name]
    local is_optional = is_optional_node(child)
    -- DISCOVER-resolved fields are always optional
    if not node:has_field(name) then
      is_optional = true
    end
    local unwrapped = navigation.unwrap_optional(child)
    local suffix = is_optional and "?" or ""

    collect_alias(unwrapped)
    if is_union_node(unwrapped) then
      for _, branch in ipairs(unwrapped._branches) do
        collect_alias(branch)
      end
    end

    local type_str
    if is_object_node(unwrapped) then
      type_str = resolve_child_class(path, name, unwrapped)
    else
      type_str = node_to_type(unwrapped)
    end

    local is_inherited_field = parent_class_name
      and node._extends
      and node._extends:has_field(name)
      and not (node._extension_fields and node._extension_fields[name])
    if not is_inherited_field then
      emit("---@field " .. name .. suffix .. " " .. type_str)
    end
  end

  -- Open-ended indexer for objects with DISCOVER
  if node:has_discover() then
    emit("---@field [string] table|nil")
  end
end

-- ---------------------------------------------------------------------------
-- Main generation
-- ---------------------------------------------------------------------------

local function generate()
  local schema = require("flemma.config.schema")

  boot_registries(schema)

  -- Seed the root object into the queue
  enqueue_class("", schema, "flemma.Config")

  -- Phase 1: walk the tree, collecting classes and aliases
  while #class_queue > 0 do
    local entry = table.remove(class_queue, 1)
    emit_class(entry.path, entry.node, entry.class_name)
    emit_blank()
  end
  local class_lines = lines
  lines = {}

  -- Phase 2: assemble final output

  -- Header
  emit("--- EmmyLua type definitions for Flemma configuration.")
  emit("--- AUTO-GENERATED from config/schema.lua — do not edit by hand.")
  emit("--- Regenerate with: make types")
  emit_blank()

  -- Aliases (sorted for determinism)
  local alias_names = {}
  for name in pairs(pending_aliases) do
    alias_names[#alias_names + 1] = name
  end
  table.sort(alias_names)
  for _, name in ipairs(alias_names) do
    emit("---@alias " .. name .. " " .. pending_aliases[name])
  end
  emit_blank()

  -- ConfigAware generic class (not derivable from schema)
  emit("---@class flemma.config.ConfigAware<T>")
  emit("---@field get_config fun(self): T|nil")
  emit_blank()

  -- Classes
  for _, line in ipairs(class_lines) do
    emit(line)
  end

  -- Opts alias
  emit("---User-facing setup options — alias for flemma.Config.")
  emit("---@alias flemma.Config.Opts flemma.Config")
end

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------

generate()

local output = table.concat(lines, "\n") .. "\n"
local output_path = "lua/flemma/config/types.lua"

local file = io.open(output_path, "w")
if not file then
  io.stderr:write("ERROR: cannot open " .. output_path .. " for writing\n")
  vim.cmd("cquit 1")
  return
end
file:write(output)
file:close()

io.stdout:write("Generated " .. output_path .. " (" .. #lines .. " lines)\n")
vim.cmd("qall!")
