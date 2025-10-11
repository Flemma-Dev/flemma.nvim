--- Session and Request management for Flemma plugin
--- Tracks individual requests and their associated costs/tokens
---
--- Architecture:
--- - Session: Global per-Neovim instance, shared across all buffers
--- - Request: Represents a single API request with pricing snapshot and metadata
--- - inflight_usage: Per-buffer temporary state for accumulating tokens during streaming
---
--- Flow:
--- 1. During streaming: tokens accumulate in buffer_state.inflight_usage
--- 2. On completion: inflight_usage is used to create a Request and add to global session
--- 3. inflight_usage is reset for the next request
--- 4. Session maintains historical data for all requests across all chat buffers

local M = {}

--- Request class
--- Represents a single API request with its associated metadata and token usage
local Request = {}
Request.__index = Request

--- Create a new Request instance
---@param opts table Options for the request
---@param opts.provider string Provider name (e.g., "claude", "openai")
---@param opts.model string Model name (e.g., "claude-sonnet-4-0")
---@param opts.input_tokens number Number of input tokens
---@param opts.output_tokens number Number of output tokens
---@param opts.thoughts_tokens number|nil Number of thoughts/reasoning tokens
---@param opts.input_price number USD per million input tokens
---@param opts.output_price number USD per million output tokens
---@param opts.bufnr number|nil Buffer number where the request originated
---@param opts.timestamp number|nil Unix timestamp (defaults to current time)
---@return table Request instance
function Request.new(opts)
  local self = setmetatable({}, Request)

  self.provider = opts.provider
  self.model = opts.model
  self.input_tokens = opts.input_tokens or 0
  self.output_tokens = opts.output_tokens or 0
  self.thoughts_tokens = opts.thoughts_tokens or 0
  self.input_price = opts.input_price
  self.output_price = opts.output_price
  self.bufnr = opts.bufnr
  self.timestamp = opts.timestamp or os.time()

  return self
end

--- Calculate input cost for this request
---@return number Cost in USD
function Request:get_input_cost()
  return (self.input_tokens / 1000000) * self.input_price
end

--- Calculate output cost for this request (includes thoughts tokens)
---@return number Cost in USD
function Request:get_output_cost()
  local total_output = self.output_tokens + self.thoughts_tokens
  return (total_output / 1000000) * self.output_price
end

--- Calculate total cost for this request
---@return number Cost in USD
function Request:get_total_cost()
  return self:get_input_cost() + self:get_output_cost()
end

--- Get total output tokens (output + thoughts)
---@return number Total output tokens
function Request:get_total_output_tokens()
  return self.output_tokens + self.thoughts_tokens
end

--- Session class
--- Represents a collection of requests in the current editing session
local Session = {}
Session.__index = Session

--- Create a new Session instance
---@return table Session instance
function Session.new()
  local self = setmetatable({}, Session)
  self.requests = {}
  return self
end

--- Add a request to the session
---@param opts table Request options (provider, model, input_tokens, output_tokens, thoughts_tokens, input_price, output_price, bufnr, timestamp)
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
---@return table|nil Most recent request or nil if no requests
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
