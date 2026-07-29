--- Compile gettext Plural-Forms expressions into Lua functions.
--- The expression language is a strict subset of C: integer arithmetic,
--- comparisons, logical operators, ternary conditional, and the single
--- variable `n`. The compiler produces a closure tree — each node is a
--- function `fun(n: integer): integer` — so no `load()` or string eval
--- is involved.
---@class flemma.utilities.PluralForms
local M = {}

---@alias flemma.utilities.plural_forms.Fn fun(n: integer): integer

---@class flemma.utilities.plural_forms.Token
---@field type string
---@field value? integer

---@type table<string, boolean>
local TWO_CHAR = {
  ["=="] = true,
  ["!="] = true,
  ["<="] = true,
  [">="] = true,
  ["&&"] = true,
  ["||"] = true,
}

---@type table<string, boolean>
local ONE_CHAR = {
  ["("] = true,
  [")"] = true,
  ["?"] = true,
  [":"] = true,
  ["%"] = true,
  ["+"] = true,
  ["-"] = true,
  ["*"] = true,
  ["/"] = true,
  ["!"] = true,
  ["<"] = true,
  [">"] = true,
}

---@param expression string
---@return flemma.utilities.plural_forms.Token[]
local function tokenize(expression)
  ---@type flemma.utilities.plural_forms.Token[]
  local tokens = {}
  local i = 1
  local len = #expression
  while i <= len do
    local c = expression:sub(i, i)
    if c:match("%s") then
      i = i + 1
    elseif c:match("%d") then
      local num_str = expression:match("^%d+", i)
      tokens[#tokens + 1] = { type = "num", value = tonumber(num_str) }
      i = i + #num_str
    elseif c == "n" and not expression:sub(i + 1, i + 1):match("[%w_]") then
      tokens[#tokens + 1] = { type = "n" }
      i = i + 1
    else
      local cc = expression:sub(i, i + 1)
      if TWO_CHAR[cc] then
        tokens[#tokens + 1] = { type = cc }
        i = i + 2
      elseif ONE_CHAR[c] then
        tokens[#tokens + 1] = { type = c }
        i = i + 1
      else
        error(("plural_forms: unexpected character %q at position %d"):format(c, i), 0)
      end
    end
  end
  tokens[#tokens + 1] = { type = "eof" }
  return tokens
end

---@type table<string, fun(a: integer, b: integer): integer>
local MUL_OPS = {
  ["*"] = function(a, b)
    return a * b
  end,
  ["/"] = function(a, b)
    if b == 0 then
      return 0
    end
    return math.floor(a / b)
  end,
  ["%"] = function(a, b)
    if b == 0 then
      return 0
    end
    return a % b
  end,
}

---@type table<string, fun(a: integer, b: integer): integer>
local ADD_OPS = {
  ["+"] = function(a, b)
    return a + b
  end,
  ["-"] = function(a, b)
    return a - b
  end,
}

---@type table<string, fun(a: integer, b: integer): integer>
local REL_OPS = {
  ["<"] = function(a, b)
    return a < b and 1 or 0
  end,
  [">"] = function(a, b)
    return a > b and 1 or 0
  end,
  ["<="] = function(a, b)
    return a <= b and 1 or 0
  end,
  [">="] = function(a, b)
    return a >= b and 1 or 0
  end,
}

---@type table<string, fun(a: integer, b: integer): integer>
local EQ_OPS = {
  ["=="] = function(a, b)
    return a == b and 1 or 0
  end,
  ["!="] = function(a, b)
    return a ~= b and 1 or 0
  end,
}

---Compile a Plural-Forms expression string into a callable function.
---The expression uses a strict C subset: `n` is the only variable,
---operators follow C precedence, and the result is the 0-based index
---into `msgstr[N]` forms.
---@param expression string
---@return flemma.utilities.plural_forms.Fn
function M.compile(expression)
  local tokens = tokenize(expression)
  local pos = 1

  local function peek()
    return tokens[pos].type
  end

  local function advance()
    local token = tokens[pos]
    pos = pos + 1
    return token
  end

  local parse_ternary

  local function parse_primary()
    local tt = peek()
    if tt == "num" then
      local v = advance().value --[[@as integer]]
      return function()
        return v
      end
    elseif tt == "n" then
      advance()
      ---@param n integer
      return function(n)
        return n
      end
    elseif tt == "(" then
      advance()
      local expr = parse_ternary()
      if peek() ~= ")" then
        error("plural_forms: expected ')' in expression", 0)
      end
      advance()
      return expr
    elseif tt == "!" then
      advance()
      local operand = parse_primary()
      return function(n)
        return operand(n) == 0 and 1 or 0
      end
    else
      error(("plural_forms: unexpected token %q in expression"):format(tt), 0)
    end
  end

  ---@param inner fun(): flemma.utilities.plural_forms.Fn
  ---@param ops table<string, fun(a: integer, b: integer): integer>
  ---@return flemma.utilities.plural_forms.Fn
  local function parse_left_assoc(inner, ops)
    local left = inner()
    while ops[peek()] do
      local op = ops[advance().type]
      local right = inner()
      local prev = left
      left = function(n)
        return op(prev(n), right(n))
      end
    end
    return left
  end

  local function parse_multiplicative()
    return parse_left_assoc(parse_primary, MUL_OPS)
  end

  local function parse_additive()
    return parse_left_assoc(parse_multiplicative, ADD_OPS)
  end

  local function parse_relational()
    return parse_left_assoc(parse_additive, REL_OPS)
  end

  local function parse_equality()
    return parse_left_assoc(parse_relational, EQ_OPS)
  end

  local function parse_logical_and()
    local left = parse_equality()
    while peek() == "&&" do
      advance()
      local right = parse_equality()
      local prev = left
      left = function(n)
        if prev(n) == 0 then
          return 0
        end
        return right(n) ~= 0 and 1 or 0
      end
    end
    return left
  end

  local function parse_logical_or()
    local left = parse_logical_and()
    while peek() == "||" do
      advance()
      local right = parse_logical_and()
      local prev = left
      left = function(n)
        if prev(n) ~= 0 then
          return 1
        end
        return right(n) ~= 0 and 1 or 0
      end
    end
    return left
  end

  parse_ternary = function()
    local condition = parse_logical_or()
    if peek() ~= "?" then
      return condition
    end
    advance()
    local then_branch = parse_ternary()
    if peek() ~= ":" then
      error("plural_forms: expected ':' in ternary expression", 0)
    end
    advance()
    local else_branch = parse_ternary()
    return function(n)
      if condition(n) ~= 0 then
        return then_branch(n)
      else
        return else_branch(n)
      end
    end
  end

  local result = parse_ternary()
  if peek() ~= "eof" then
    error(("plural_forms: unexpected token %q after expression"):format(peek()), 0)
  end
  return result
end

---Parse a Plural-Forms header value into nplurals and a compiled selector.
---Input format: `"nplurals=N; plural=EXPRESSION;"`.
---@param value string
---@return integer nplurals
---@return flemma.utilities.plural_forms.Fn plural
function M.parse_header(value)
  local nplurals_str = value:match("nplurals%s*=%s*(%d+)")
  if not nplurals_str then
    error("plural_forms: Plural-Forms header missing nplurals", 0)
  end
  local expression = value:match("plural%s*=%s*(.+)")
  if not expression then
    error("plural_forms: Plural-Forms header missing plural expression", 0)
  end
  expression = expression:gsub(";%s*$", "")
  local nplurals = tonumber(nplurals_str) --[[@as integer]]
  return nplurals, M.compile(expression)
end

return M
