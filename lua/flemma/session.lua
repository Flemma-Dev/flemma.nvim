--- Session and Request management for Flemma plugin
--- Tracks individual requests and their associated costs/tokens
---
--- Architecture:
--- - Session: Global per-Neovim instance, shared across all buffers
--- - Request: Represents a single API request with pricing snapshot and metadata
--- - inflight_usage: Per-buffer temporary state for accumulating tokens during streaming
---
--- Request Identification:
--- - filepath: Resolved absolute path (handles symlinks, relative paths, etc.)
--- - bufnr: Only stored for unnamed/unsaved buffers as fallback identifier
---
--- Flow:
--- 1. During streaming: tokens accumulate in buffer_state.inflight_usage
--- 2. On completion: inflight_usage is used to create a Request and add to global session
--- 3. inflight_usage is reset for the next request
--- 4. Session maintains historical data for all requests across all chat buffers
--- 5. Requests can be analyzed by filepath (e.g., cost per project)

---@class flemma.SessionModule
local M = {}

---@class flemma.session.Request
---@field provider string
---@field model string
---@field input_tokens number
---@field output_tokens number
---@field thoughts_tokens number
---@field input_price number
---@field output_price number
---@field filepath? string
---@field bufnr? integer
---@field timestamp number
---@field output_has_thoughts boolean
---@field cache_read_input_tokens number
---@field cache_creation_input_tokens number
---@field cache_read_multiplier? number Cache read cost as fraction of input price (e.g. 0.1)
---@field cache_write_multiplier? number Cache write cost multiplier (e.g. 1.25 for short, 2.0 for long)
local Request = {}
Request.__index = Request

---@class flemma.session.RequestOpts
---@field provider string Provider name (e.g., "anthropic", "openai")
---@field model string Model name (e.g., "claude-sonnet-4-5")
---@field input_tokens number Number of input tokens
---@field output_tokens number Number of output tokens
---@field thoughts_tokens? number Number of thoughts/reasoning tokens
---@field input_price number USD per million input tokens
---@field output_price number USD per million output tokens
---@field filepath? string Resolved absolute filepath (nil for unnamed buffers)
---@field bufnr? integer Buffer number (fallback for unnamed buffers)
---@field timestamp? number Unix timestamp (defaults to current time)
---@field output_has_thoughts? boolean Whether output_tokens already includes thoughts (true for OpenAI/Anthropic, false for Vertex)
---@field cache_read_input_tokens? number Number of cache read tokens
---@field cache_creation_input_tokens? number Number of cache creation tokens
---@field cache_read_multiplier? number Cache read cost as fraction of input price (e.g. 0.1)
---@field cache_write_multiplier? number Cache write cost multiplier (e.g. 1.25 for short, 2.0 for long)

--- Create a new Request instance
---@param opts flemma.session.RequestOpts Options for the request
---@return flemma.session.Request
function Request.new(opts)
  local self = setmetatable({}, Request)

  self.provider = opts.provider
  self.model = opts.model
  self.input_tokens = opts.input_tokens or 0
  self.output_tokens = opts.output_tokens or 0
  self.thoughts_tokens = opts.thoughts_tokens or 0
  self.input_price = opts.input_price
  self.output_price = opts.output_price
  self.filepath = opts.filepath
  self.bufnr = opts.bufnr
  self.timestamp = opts.timestamp or os.time()
  -- Whether output_tokens already includes thoughts (true for OpenAI/Anthropic, false for Vertex)
  self.output_has_thoughts = opts.output_has_thoughts or false
  self.cache_read_input_tokens = opts.cache_read_input_tokens or 0
  self.cache_creation_input_tokens = opts.cache_creation_input_tokens or 0
  self.cache_read_multiplier = opts.cache_read_multiplier
  self.cache_write_multiplier = opts.cache_write_multiplier

  return self
end

--- Calculate input cost for this request (cache-aware)
--- When cache multipliers are available, cache reads/writes use discounted rates.
--- When multipliers are nil (no pricing data), cache tokens are charged at full input price.
---@return number Cost in USD
function Request:get_input_cost()
  local base = (self.input_tokens / 1000000) * self.input_price
  local read_mult = self.cache_read_multiplier or 1
  local read = (self.cache_read_input_tokens / 1000000) * (self.input_price * read_mult)
  local write_mult = self.cache_write_multiplier or 1
  local write = (self.cache_creation_input_tokens / 1000000) * (self.input_price * write_mult)
  return base + read + write
end

--- Calculate output cost for this request
--- For Vertex: adds thoughts_tokens since they're separate from output_tokens
--- For OpenAI/Anthropic: uses output_tokens alone since thoughts are already included
---@return number Cost in USD
function Request:get_output_cost()
  local total_output
  if self.output_has_thoughts then
    -- OpenAI/Anthropic: thoughts already counted in output_tokens
    total_output = self.output_tokens
  else
    -- Vertex: thoughts are separate from output tokens
    total_output = self.output_tokens + self.thoughts_tokens
  end
  return (total_output / 1000000) * self.output_price
end

--- Calculate total cost for this request
---@return number Cost in USD
function Request:get_total_cost()
  return self:get_input_cost() + self:get_output_cost()
end

--- Get total output tokens for display/billing
--- For Vertex: adds thoughts_tokens since they're separate
--- For OpenAI/Anthropic: uses output_tokens alone since thoughts are already included
---@return number Total output tokens
function Request:get_total_output_tokens()
  if self.output_has_thoughts then
    return self.output_tokens
  else
    return self.output_tokens + self.thoughts_tokens
  end
end

---@class flemma.session.Session
---@field requests flemma.session.Request[]
local Session = {}
Session.__index = Session

--- Create a new Session instance
---@return flemma.session.Session
function Session.new()
  local self = setmetatable({}, Session)
  self.requests = {}
  return self
end

--- Add a request to the session
---@param opts flemma.session.RequestOpts Request options
function Session:add_request(opts)
  local request = Request.new(opts)
  table.insert(self.requests, request)
end

--- Get total input tokens across all requests
---@return number Total input tokens
function Session:get_total_input_tokens()
  local total = 0
  for _, request in ipairs(self.requests) do
    total = total + request.input_tokens
  end
  return total
end

--- Get total output tokens across all requests (includes thoughts)
---@return number Total output tokens
function Session:get_total_output_tokens()
  local total = 0
  for _, request in ipairs(self.requests) do
    total = total + request:get_total_output_tokens()
  end
  return total
end

--- Get total thoughts tokens across all requests
---@return number Total thoughts tokens
function Session:get_total_thoughts_tokens()
  local total = 0
  for _, request in ipairs(self.requests) do
    total = total + request.thoughts_tokens
  end
  return total
end

--- Get total input cost across all requests
---@return number Total input cost in USD
function Session:get_total_input_cost()
  local total = 0
  for _, request in ipairs(self.requests) do
    total = total + request:get_input_cost()
  end
  return total
end

--- Get total output cost across all requests
---@return number Total output cost in USD
function Session:get_total_output_cost()
  local total = 0
  for _, request in ipairs(self.requests) do
    total = total + request:get_output_cost()
  end
  return total
end

--- Get total cost across all requests
---@return number Total cost in USD
function Session:get_total_cost()
  return self:get_total_input_cost() + self:get_total_output_cost()
end

--- Get the number of requests in the session
---@return number Number of requests
function Session:get_request_count()
  return #self.requests
end

--- Get the most recent request
---@return flemma.session.Request|nil Most recent request or nil if no requests
function Session:get_latest_request()
  if #self.requests > 0 then
    return self.requests[#self.requests]
  end
  return nil
end

--- Reset the session (clear all requests)
function Session:reset()
  self.requests = {}
end

M.Request = Request
M.Session = Session

return M
