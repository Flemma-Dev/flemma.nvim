--- Lazy, composable highlight builder system.
--- Replaces the string-based highlight DSL with an OOP builder where every
--- operation is an object that resolves on demand via :get() or :set().
---@class flemma.hl
local M = {}

local color = require("flemma.utilities.color")

-- ---------------------------------------------------------------------------
-- HlOp base class
-- ---------------------------------------------------------------------------

---@class flemma.hl.HlOp
---@field _parent? flemma.hl.HlOp Parent op in the chain
local HlOp = {}
HlOp.__index = HlOp

---@return vim.api.keyset.highlight|nil
function HlOp:get()
  return nil
end

---@param name string
---@param opts? vim.api.keyset.highlight Overrides merged onto the result (e.g., `{ default = false }` to allow re-setting)
function HlOp:set(name, opts)
  assert(name:sub(1, 6) == "Flemma", "hl:set() group name must start with 'Flemma', got: " .. name)
  local result = self:get()
  if result == nil then
    return
  end
  result.default = true
  if opts then
    for k, v in pairs(opts) do
      result[k] = v
    end
  end
  vim.api.nvim_set_hl(0, name, result)
end

-- ---------------------------------------------------------------------------
-- resolve_to_attrs: shared helper for chain ops
-- ---------------------------------------------------------------------------

--- Resolve a parent result to concrete attrs. If the result is a link,
--- follows it via nvim_get_hl and converts integer colors to hex.
---@param result vim.api.keyset.highlight
---@return vim.api.keyset.highlight
local function resolve_to_attrs(result)
  local link_name = result.link
  if not link_name then
    -- Return a shallow copy, never the caller's own table. OmitOp/BlendOp mutate
    -- the returned attrs in place; aliasing the parent op's result would corrupt
    -- it should that op ever hand back a shared or cached table. Highlight attrs
    -- are flat (scalar values), so a shallow copy is sufficient.
    return vim.tbl_extend("force", {}, result)
  end
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, {
    name = link_name --[[@as string]],
    link = false,
  })
  if not ok or not hl then
    return {}
  end
  ---@type vim.api.keyset.highlight
  local attrs = {}
  for k, v in pairs(hl) do
    if k == "fg" or k == "bg" or k == "sp" then
      attrs[k] = string.format("#%06x", v)
    elseif k ~= "link" then
      attrs[k] = v
    end
  end
  return attrs
end

--- Get the default fallback color for an attribute from Normal, or black/white.
---@param attr string "fg" or "bg" or "sp"
---@return string
local function default_color(attr)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = "Normal", link = false })
  if ok and hl then
    local v = hl[attr]
    if v then
      return string.format("#%06x", v)
    end
  end
  local is_dark = vim.o.background == "dark"
  if attr == "bg" then
    return is_dark and "#000000" or "#ffffff"
  end
  return is_dark and "#ffffff" or "#000000"
end

-- ---------------------------------------------------------------------------
-- NilOp singleton
-- ---------------------------------------------------------------------------

---@class flemma.hl.NilOp : flemma.hl.HlOp
local NilOp = {}
NilOp.__index = NilOp

---@return nil
function NilOp:get()
  return nil
end

---@param _name string
---@param _opts? vim.api.keyset.highlight
function NilOp:set(_name, _opts) end

---@param _attr string
---@param _mod string|flemma.hl.DiffOp|flemma.hl.HlOp
---@param _ratio? number
---@return flemma.hl.NilOp
function NilOp:blend(_attr, _mod, _ratio)
  return NilOp
end

---@param _attr string
---@param _mod string|flemma.hl.HlOp
---@param _ratio? number
---@return flemma.hl.NilOp
function NilOp:tint(_attr, _mod, _ratio)
  return NilOp
end

---@param _attr string
---@param _mod string|flemma.hl.HlOp
---@param _ratio? number
---@return flemma.hl.NilOp
function NilOp:mute(_attr, _mod, _ratio)
  return NilOp
end

---@param ... string
---@return flemma.hl.NilOp
function NilOp:omit(...) -- luacheck: no unused args
  return NilOp
end

---@param ... string
---@return flemma.hl.NilOp
function NilOp:pick(...) -- luacheck: no unused args
  return NilOp
end

---@param _attr string
---@param _against flemma.hl.HlOp
---@param _ratio number
---@return flemma.hl.NilOp
function NilOp:contrast(_attr, _against, _ratio)
  return NilOp
end

---@param _attrs table<string, any>
---@return flemma.hl.NilOp
function NilOp:style(_attrs)
  return NilOp
end

---@param _other flemma.hl.HlOp
---@param _strategy? "keep"|"force"
---@return flemma.hl.NilOp
function NilOp:merge(_other, _strategy)
  return NilOp
end

-- ---------------------------------------------------------------------------
-- LinkOp
-- ---------------------------------------------------------------------------

---@class flemma.hl.LinkOp : flemma.hl.HlOp
---@field _name string
local LinkOp = setmetatable({}, { __index = HlOp })
LinkOp.__index = LinkOp

---@param name string
---@return flemma.hl.LinkOp
function LinkOp.new(name)
  return setmetatable({ _name = name }, LinkOp)
end

---@return vim.api.keyset.highlight
function LinkOp:get()
  return { link = self._name }
end

-- ---------------------------------------------------------------------------
-- FromOp
-- ---------------------------------------------------------------------------

---@class flemma.hl.FromOp : flemma.hl.HlOp
---@field _group string
local FromOp = setmetatable({}, { __index = HlOp })
FromOp.__index = FromOp

---@param group string
---@return flemma.hl.FromOp
function FromOp.new(group)
  return setmetatable({ _group = group }, FromOp)
end

---@return vim.api.keyset.highlight|nil
function FromOp:get()
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = self._group, link = false })
  if not ok or not hl or not next(hl) then
    return nil
  end
  local attrs = resolve_to_attrs({ link = self._group })
  return next(attrs) ~= nil and attrs or nil
end

-- ---------------------------------------------------------------------------
-- HexOp
-- ---------------------------------------------------------------------------

---@class flemma.hl.HexOp : flemma.hl.HlOp
---@field _hex string
---@field _attr string
local HexOp = setmetatable({}, { __index = HlOp })
HexOp.__index = HexOp

---@param hex string
---@param attr? string
---@return flemma.hl.HexOp
function HexOp.new(hex, attr)
  return setmetatable({ _hex = hex, _attr = attr or "fg" }, HexOp)
end

---@return vim.api.keyset.highlight
function HexOp:get()
  return { [self._attr] = self._hex }
end

-- ---------------------------------------------------------------------------
-- DefaultOp
-- ---------------------------------------------------------------------------

---@class flemma.hl.DefaultOp : flemma.hl.HlOp
---@field _attr string
local DefaultOp = setmetatable({}, { __index = HlOp })
DefaultOp.__index = DefaultOp

---@param attr string
---@return flemma.hl.DefaultOp
function DefaultOp.new(attr)
  return setmetatable({ _attr = attr }, DefaultOp)
end

---@return vim.api.keyset.highlight
function DefaultOp:get()
  return { [self._attr] = default_color(self._attr) }
end

-- ---------------------------------------------------------------------------
-- AttrsOp
-- ---------------------------------------------------------------------------

---@class flemma.hl.AttrsOp : flemma.hl.HlOp
---@field _attrs table<string, any>
local AttrsOp = setmetatable({}, { __index = HlOp })
AttrsOp.__index = AttrsOp

---@param attrs table<string, any>
---@return flemma.hl.AttrsOp
function AttrsOp.new(attrs)
  return setmetatable({ _attrs = attrs }, AttrsOp)
end

---@return vim.api.keyset.highlight
function AttrsOp:get()
  return vim.tbl_extend("force", {}, self._attrs)
end

-- ---------------------------------------------------------------------------
-- CoalesceOp
-- ---------------------------------------------------------------------------

---@class flemma.hl.CoalesceOp : flemma.hl.HlOp
---@field _children flemma.hl.HlOp[]
local CoalesceOp = setmetatable({}, { __index = HlOp })
CoalesceOp.__index = CoalesceOp

---@param children flemma.hl.HlOp[]
---@return flemma.hl.CoalesceOp
function CoalesceOp.new(children)
  return setmetatable({ _children = children }, CoalesceOp)
end

---@return vim.api.keyset.highlight|nil
function CoalesceOp:get()
  for _, child in ipairs(self._children) do
    local result = child:get()
    if result ~= nil then
      return result
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- DiffOp
-- ---------------------------------------------------------------------------

---@class flemma.hl.DiffOp : flemma.hl.HlOp
---@field _group_a string
---@field _group_b string
---@field _attr string
local DiffOp = setmetatable({}, { __index = HlOp })
DiffOp.__index = DiffOp

---@param group_a string
---@param group_b string
---@param attr string
---@return flemma.hl.DiffOp
function DiffOp.new(group_a, group_b, attr)
  return setmetatable({ _group_a = group_a, _group_b = group_b, _attr = attr }, DiffOp)
end

---@return {r: integer, g: integer, b: integer}|nil
function DiffOp:delta()
  local ok_a, hl_a = pcall(vim.api.nvim_get_hl, 0, { name = self._group_a, link = false })
  local ok_b, hl_b = pcall(vim.api.nvim_get_hl, 0, { name = self._group_b, link = false })
  if not ok_a or not ok_b then
    return nil
  end
  local val_a = hl_a and hl_a[self._attr]
  local val_b = hl_b and hl_b[self._attr]
  if not val_b then
    return nil
  end
  local hex_a = val_a and string.format("#%06x", val_a) or default_color(self._attr)
  local hex_b = string.format("#%06x", val_b)
  local rgb_a = color.hex_to_rgb(hex_a)
  local rgb_b = color.hex_to_rgb(hex_b)
  if not rgb_a or not rgb_b then
    return nil
  end
  return {
    r = rgb_b.r - rgb_a.r,
    g = rgb_b.g - rgb_a.g,
    b = rgb_b.b - rgb_a.b,
  }
end

function DiffOp:get()
  error("DiffOp:get() is not valid — DiffOp is only usable as a :blend() operand")
end

---@param _name string
function DiffOp:set(_name)
  error("DiffOp:set() is not valid — DiffOp is only usable as a :blend() operand")
end

-- ---------------------------------------------------------------------------
-- ThemedOp
-- ---------------------------------------------------------------------------

---@class flemma.hl.ThemedOp : flemma.hl.HlOp
---@field _branches {dark?: flemma.hl.HlOp, light?: flemma.hl.HlOp}
local ThemedOp = setmetatable({}, { __index = HlOp })
ThemedOp.__index = ThemedOp

---@param branches {dark?: flemma.hl.HlOp, light?: flemma.hl.HlOp}
---@return flemma.hl.ThemedOp
function ThemedOp.new(branches)
  return setmetatable({ _branches = branches }, ThemedOp)
end

---@return vim.api.keyset.highlight|nil
function ThemedOp:get()
  local branch
  if vim.o.background == "dark" then
    branch = self._branches.dark
  else
    branch = self._branches.light
  end
  if not branch then
    return nil
  end
  return branch:get()
end

-- ---------------------------------------------------------------------------
-- BlendOp
-- ---------------------------------------------------------------------------

---@class flemma.hl.BlendOp : flemma.hl.HlOp
---@field _attr string
---@field _mod string|flemma.hl.DiffOp|flemma.hl.HlOp
---@field _ratio? number
local BlendOp = setmetatable({}, { __index = HlOp })
BlendOp.__index = BlendOp

---@param parent flemma.hl.HlOp
---@param attr string
---@param mod string|flemma.hl.DiffOp|flemma.hl.HlOp
---@param ratio? number
---@return flemma.hl.BlendOp
function BlendOp.new(parent, attr, mod, ratio)
  return setmetatable({ _parent = parent, _attr = attr, _mod = mod, _ratio = ratio }, BlendOp)
end

--- Resolve the mod operand to an RGB triplet and a blend direction.
---@return flemma.utilities.color.RGB|nil mod_rgb
---@return "+"|"-"|nil direction
---@private
function BlendOp:_resolve_mod()
  local mod = self._mod
  local ratio = self._ratio

  if getmetatable(mod) == DiffOp then
    local delta = (mod --[[@as flemma.hl.DiffOp]]):delta()
    if not delta then
      return nil, nil
    end
    return delta, "+"
  end

  if ratio ~= nil then
    local mod_rgb ---@type flemma.utilities.color.RGB|nil
    if type(mod) == "string" then
      mod_rgb = color.hex_to_rgb(mod --[[@as string]])
    else
      local mod_result = (mod --[[@as flemma.hl.HlOp]]):get()
      if mod_result then
        local mod_attrs = resolve_to_attrs(mod_result)
        local first_color = mod_attrs.fg or mod_attrs.bg or mod_attrs.sp --[[@as string|nil]]
        if first_color then
          mod_rgb = color.hex_to_rgb(first_color)
        end
      end
    end
    if not mod_rgb then
      return nil, nil
    end
    local magnitude = math.abs(ratio)
    return {
      r = mod_rgb.r * magnitude,
      g = mod_rgb.g * magnitude,
      b = mod_rgb.b * magnitude,
    },
      ratio >= 0 and "+" or "-"
  end

  local mod_str = mod --[[@as string]]
  local direction = mod_str:sub(1, 1) --[[@as "+"|"-"]]
  local mod_rgb = color.hex_to_rgb(mod_str:sub(2))
  if not mod_rgb then
    return nil, nil
  end
  return mod_rgb, direction
end

---@return vim.api.keyset.highlight|nil
function BlendOp:get()
  local parent_result = self._parent:get()
  if parent_result == nil then
    return nil
  end
  local attrs = resolve_to_attrs(parent_result)

  local base_hex = attrs[self._attr]
  if not base_hex then
    base_hex = default_color(self._attr)
  end

  local base_rgb = color.hex_to_rgb(base_hex)
  if not base_rgb then
    return attrs
  end

  local mod_rgb, direction = self:_resolve_mod()
  if not mod_rgb or not direction then
    return attrs
  end

  attrs[self._attr] = color.rgb_to_hex(color.blend(base_rgb, mod_rgb, direction))
  return attrs
end

-- ---------------------------------------------------------------------------
-- TintOp
-- ---------------------------------------------------------------------------

---@class flemma.hl.TintOp : flemma.hl.HlOp
---@field _attr string
---@field _mod string|flemma.hl.HlOp
---@field _dark_sign 1|-1
---@field _ratio number
local TintOp = setmetatable({}, { __index = HlOp })
TintOp.__index = TintOp

---@param parent flemma.hl.HlOp
---@param attr string
---@param mod string|flemma.hl.HlOp
---@param dark_sign 1|-1
---@param ratio? number
---@return flemma.hl.TintOp
function TintOp.new(parent, attr, mod, dark_sign, ratio)
  return setmetatable(
    { _parent = parent, _attr = attr, _mod = mod, _dark_sign = dark_sign, _ratio = ratio or 1.0 },
    TintOp
  )
end

---@return vim.api.keyset.highlight|nil
function TintOp:get()
  local sign = vim.o.background == "dark" and self._dark_sign or -self._dark_sign
  return BlendOp.new(self._parent, self._attr, self._mod, sign * self._ratio):get()
end

-- ---------------------------------------------------------------------------
-- OmitOp
-- ---------------------------------------------------------------------------

---@class flemma.hl.OmitOp : flemma.hl.HlOp
---@field _keys string[]
local OmitOp = setmetatable({}, { __index = HlOp })
OmitOp.__index = OmitOp

---@param parent flemma.hl.HlOp
---@param keys string[]
---@return flemma.hl.OmitOp
function OmitOp.new(parent, keys)
  return setmetatable({ _parent = parent, _keys = keys }, OmitOp)
end

---@return vim.api.keyset.highlight|nil
function OmitOp:get()
  local parent_result = self._parent:get()
  if parent_result == nil then
    return nil
  end
  local attrs = resolve_to_attrs(parent_result)
  for _, key in ipairs(self._keys) do
    attrs[key] = nil
  end
  return attrs
end

-- ---------------------------------------------------------------------------
-- PickOp
-- ---------------------------------------------------------------------------

---@class flemma.hl.PickOp : flemma.hl.HlOp
---@field _keys string[]
---@field _strict boolean
local PickOp = setmetatable({}, { __index = HlOp })
PickOp.__index = PickOp

---@param parent flemma.hl.HlOp
---@param keys string[]
---@param strict? boolean
---@return flemma.hl.PickOp
function PickOp.new(parent, keys, strict)
  return setmetatable({ _parent = parent, _keys = keys, _strict = strict or false }, PickOp)
end

---@return vim.api.keyset.highlight|nil
function PickOp:get()
  local parent_result = self._parent:get()
  if parent_result == nil then
    return nil
  end
  local attrs = resolve_to_attrs(parent_result)
  ---@type vim.api.keyset.highlight
  local result = {}
  for _, key in ipairs(self._keys) do
    if attrs[key] ~= nil then
      result[key] = attrs[key]
    elseif self._strict then
      return nil
    end
  end
  if next(result) == nil then
    return nil
  end
  return result
end

-- ---------------------------------------------------------------------------
-- ContrastOp
-- ---------------------------------------------------------------------------

---@class flemma.hl.ContrastOp : flemma.hl.HlOp
---@field _attr string
---@field _against flemma.hl.HlOp
---@field _ratio number
local ContrastOp = setmetatable({}, { __index = HlOp })
ContrastOp.__index = ContrastOp

---@type table<string, string>
local CONTRAST_COMPLEMENT = {
  fg = "bg",
  bg = "fg",
}

---@param parent flemma.hl.HlOp
---@param attr string
---@param against flemma.hl.HlOp
---@param ratio number
---@return flemma.hl.ContrastOp
function ContrastOp.new(parent, attr, against, ratio)
  if not CONTRAST_COMPLEMENT[attr] then
    local valid = vim.tbl_keys(CONTRAST_COMPLEMENT)
    table.sort(valid)
    error("contrast: unsupported attr '" .. tostring(attr) .. "', expected " .. table.concat(valid, "/"))
  end
  return setmetatable({ _parent = parent, _attr = attr, _against = against, _ratio = ratio }, ContrastOp)
end

---@return vim.api.keyset.highlight|nil
function ContrastOp:get()
  local parent_result = self._parent:get()
  if parent_result == nil then
    return nil
  end
  local against_result = self._against:get()
  if against_result == nil then
    return nil
  end
  local attrs = resolve_to_attrs(parent_result)
  local against_attrs = resolve_to_attrs(against_result)

  local fg_hex = attrs[self._attr] --[[@as string|nil]]
  if not fg_hex then
    return nil
  end

  local ref_hex = against_attrs[CONTRAST_COMPLEMENT[self._attr]] --[[@as string|nil]]
  if not ref_hex then
    return nil
  end

  local adjusted = color.ensure_contrast(fg_hex, ref_hex, self._ratio)
  return vim.tbl_extend("force", attrs, { [self._attr] = adjusted })
end

-- ---------------------------------------------------------------------------
-- StyleOp
-- ---------------------------------------------------------------------------

---@class flemma.hl.StyleOp : flemma.hl.HlOp
---@field _style table<string, any>
local StyleOp = setmetatable({}, { __index = HlOp })
StyleOp.__index = StyleOp

---@param parent flemma.hl.HlOp
---@param style table<string, any>
---@return flemma.hl.StyleOp
function StyleOp.new(parent, style)
  return setmetatable({ _parent = parent, _style = style }, StyleOp)
end

---@return vim.api.keyset.highlight|nil
function StyleOp:get()
  local parent_result = self._parent:get()
  if parent_result == nil then
    return nil
  end
  local attrs = resolve_to_attrs(parent_result)
  return vim.tbl_extend("force", attrs, self._style)
end

-- ---------------------------------------------------------------------------
-- MergeOp
-- ---------------------------------------------------------------------------

---@class flemma.hl.MergeOp : flemma.hl.HlOp
---@field _other flemma.hl.HlOp
---@field _strategy "keep"|"force"
local MergeOp = setmetatable({}, { __index = HlOp })
MergeOp.__index = MergeOp

---@param parent flemma.hl.HlOp
---@param other flemma.hl.HlOp
---@param strategy? "keep"|"force"
---@return flemma.hl.MergeOp
function MergeOp.new(parent, other, strategy)
  return setmetatable({ _parent = parent, _other = other, _strategy = strategy or "keep" }, MergeOp)
end

---@return vim.api.keyset.highlight|nil
function MergeOp:get()
  local parent_result = self._parent:get()
  if parent_result == nil then
    return nil
  end
  local attrs = resolve_to_attrs(parent_result)
  local other_result = self._other:get()
  if other_result == nil then
    return attrs
  end
  local other_attrs = resolve_to_attrs(other_result)
  return vim.tbl_extend(self._strategy, attrs, other_attrs)
end

-- ---------------------------------------------------------------------------
-- HlOp chainable methods (defined after all op classes)
-- ---------------------------------------------------------------------------

---@param attr string
---@param mod string|flemma.hl.DiffOp|flemma.hl.HlOp
---@param ratio? number
---@return flemma.hl.BlendOp
function HlOp:blend(attr, mod, ratio)
  return BlendOp.new(self, attr, mod, ratio)
end

---@param attr string
---@param mod string|flemma.hl.HlOp
---@param ratio? number
---@return flemma.hl.TintOp
function HlOp:tint(attr, mod, ratio)
  return TintOp.new(self, attr, mod, 1, ratio)
end

---@param attr string
---@param mod string|flemma.hl.HlOp
---@param ratio? number
---@return flemma.hl.TintOp
function HlOp:mute(attr, mod, ratio)
  return TintOp.new(self, attr, mod, -1, ratio)
end

---@param ... string
---@return flemma.hl.OmitOp
function HlOp:omit(...)
  return OmitOp.new(self, { ... })
end

---@param ... string|{strict?: boolean}
---@return flemma.hl.PickOp
function HlOp:pick(...)
  local args = { ... }
  local last = args[#args]
  if type(last) == "table" then
    table.remove(args, #args)
    return PickOp.new(self, args, last.strict)
  end
  return PickOp.new(self, args)
end

---@param attr string
---@param against flemma.hl.HlOp
---@param ratio number
---@return flemma.hl.ContrastOp
function HlOp:contrast(attr, against, ratio)
  return ContrastOp.new(self, attr, against, ratio)
end

---@param attrs table<string, any>
---@return flemma.hl.StyleOp
function HlOp:style(attrs)
  return StyleOp.new(self, attrs)
end

---@param other flemma.hl.HlOp
---@param strategy? "keep"|"force"
---@return flemma.hl.MergeOp
function HlOp:merge(other, strategy)
  return MergeOp.new(self, other, strategy)
end

-- ---------------------------------------------------------------------------
-- Constructors (public API)
-- ---------------------------------------------------------------------------

---@param name string
---@return flemma.hl.LinkOp
function M.link(name)
  return LinkOp.new(name)
end

---@param group string
---@return flemma.hl.FromOp
function M.from(group)
  return FromOp.new(group)
end

---@param hex string
---@param attr? string
---@return flemma.hl.HexOp
function M.hex(hex, attr)
  return HexOp.new(hex, attr)
end

---@param attrs table<string, any>
---@return flemma.hl.AttrsOp
function M.attrs(attrs)
  return AttrsOp.new(attrs)
end

--- A no-op highlight: `:get()` resolves to nil and `:set()` does nothing.
--- Use as a config value to leave a group unmanaged by Flemma (e.g.
--- `highlights = { thinking_tag = h.none() }`), so the colorscheme or the
--- user's own definition stands. Being a regular HlOp, it needs no special
--- handling in the schema — it validates and chains like any other op.
---@return flemma.hl.NilOp
function M.none()
  return NilOp
end

---@param attr string
---@return flemma.hl.DefaultOp
function M.default(attr)
  return DefaultOp.new(attr)
end

---@param ... flemma.hl.HlOp
---@return flemma.hl.CoalesceOp
function M.coalesce(...)
  return CoalesceOp.new({ ... })
end

---@param group_a string
---@param group_b string
---@param attr string
---@return flemma.hl.DiffOp
function M.diff(group_a, group_b, attr)
  return DiffOp.new(group_a, group_b, attr)
end

---@param branches {dark?: flemma.hl.HlOp, light?: flemma.hl.HlOp}
---@return flemma.hl.ThemedOp
function M.themed(branches)
  return ThemedOp.new(branches)
end

-- ---------------------------------------------------------------------------
-- Exports (for schema validation and testing)
-- ---------------------------------------------------------------------------

M.HlOp = HlOp
M.NilOp = NilOp

return M
