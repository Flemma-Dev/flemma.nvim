--- Shared string display-width utilities for Flemma UI
--- All display-width calculations and width-aware truncation go through this module.
---@class flemma.utilities.String
local M = {}

--- Token counts below this threshold are shown as full comma-separated numbers;
--- at or above it they collapse to a compact K suffix.
local TOKEN_COMPACT_THRESHOLD = 4000

---Compute the display width of a string (handles multibyte and wide characters).
---@param text string
---@return integer
function M.strwidth(text)
  return vim.api.nvim_strwidth(text)
end

---Truncate a string to fit within a display-width budget, appending a suffix when truncated.
---Uses binary search over character count to avoid splitting multibyte UTF-8 sequences.
---Returns the string unchanged when it already fits.
---@param text string
---@param max_width integer Maximum display width for the result (including suffix)
---@param suffix? string Suffix to append when truncated (default: "…")
---@return string
function M.truncate(text, max_width, suffix)
  if max_width <= 0 then
    return ""
  end
  if vim.api.nvim_strwidth(text) <= max_width then
    return text
  end
  suffix = suffix or "\xe2\x80\xa6" -- "…" (U+2026, 3 bytes UTF-8)
  local suffix_width = vim.api.nvim_strwidth(suffix)
  local target = max_width - suffix_width
  if target <= 0 then
    return suffix
  end
  -- Binary search for the maximum character count whose display width fits in target.
  -- Display width is monotonically non-decreasing as characters are added, so this is safe.
  local char_count = vim.fn.strcharlen(text)
  local lo, hi = 0, char_count
  while lo < hi do
    local mid = math.ceil((lo + hi) / 2)
    if vim.api.nvim_strwidth(vim.fn.strcharpart(text, 0, mid)) <= target then
      lo = mid
    else
      hi = mid - 1
    end
  end
  return vim.fn.strcharpart(text, 0, lo) .. suffix
end

---Format a number with comma-separated thousands.
---@param number number
---@return string
function M.format_number(number)
  local s = tostring(math.floor(number))
  local reversed = s:reverse()
  local with_commas = reversed:gsub("(%d%d%d)", "%1,")
  -- Remove trailing comma if present (from the reversed perspective)
  with_commas = with_commas:gsub(",$", "")
  return with_commas:reverse()
end

---Format a token count for compact display.
---Below TOKEN_COMPACT_THRESHOLD: comma-separated number. 1000000+: M suffix. Otherwise: K suffix.
---Trailing .0 is dropped from K and M values.
---@param tokens number
---@return string
function M.format_tokens(tokens)
  if tokens >= 1000000 then
    local value = tokens / 1000000
    if tokens % 1000000 == 0 then
      return string.format("%dM", value)
    end
    return string.format("%.1fM", value)
  end
  if tokens >= TOKEN_COMPACT_THRESHOLD then
    local value = tokens / 1000
    if tokens % 1000 == 0 then
      return string.format("%dK", value)
    end
    return string.format("%.1fK", value)
  end
  return M.format_number(tokens)
end

---Format a generic text length (characters, bytes, etc.) for compact display.
---Delegates to format_tokens — same thresholds and suffixes apply.
---@param count number
---@return string
function M.format_text_length(count)
  return M.format_tokens(count)
end

---Format a monetary value in USD with smart precision.
---Integers get no decimal places, values >= 1 get 2, values in [0.01, 1) get
---3 (trailing zeros past the 2nd decimal stripped), and sub-cent values get 4
---(same stripping rule).
---@param amount number
---@return string
function M.format_money(amount)
  if amount == 0 then
    return "$0"
  end
  if amount == math.floor(amount) then
    return string.format("$%.0f", amount)
  end
  if amount >= 1 then
    return string.format("$%.2f", amount)
  end
  local s
  if amount >= 0.01 then
    s = string.format("$%.3f", amount)
  else
    s = string.format("$%.4f", amount)
  end
  -- Strip trailing zeros past the 2nd decimal place
  return (s:gsub("(%.%d%d)(%d-)0+$", "%1%2"))
end

---Format the per-MTok pricing fragment used by the high-cost warning and
---`:Flemma usage:estimate`. Input is a pricing table with `input` and `output`
---rates in dollars per million tokens.
---@param pricing { input: number, output: number }
---@return string
function M.format_pricing_suffix(pricing)
  return M.format_money(pricing.input) .. " input / " .. M.format_money(pricing.output) .. " output per MTok"
end

---Build the single-line estimate string shown by `:Flemma usage:estimate`.
---Pure formatter — caller supplies the pricing table (nil if unavailable); no
---registry lookup happens here. Falls back to a tokens-only message when
---`pricing` is nil.
---@param input_tokens integer
---@param model string
---@param pricing? { input: number, output: number }
---@return string
function M.format_estimate(input_tokens, model, pricing)
  if not pricing then
    return M.format_number(input_tokens) .. " input tokens \xc2\xb7 " .. model
  end
  local cost = input_tokens * pricing.input / 1000000
  return string.format(
    "%s input tokens \xc2\xb7 %s \xc2\xb7 %s (%s)",
    M.format_number(input_tokens),
    M.format_money(cost),
    model,
    M.format_pricing_suffix(pricing)
  )
end

---Format a byte size for human-readable display using binary divisors.
---No space between number and unit suffix.
---@param bytes number
---@return string
function M.format_size(bytes)
  local KB = 1024
  local MB = 1024 * 1024
  local GB = 1024 * 1024 * 1024
  if bytes >= GB then
    return string.format("%.1fGB", bytes / GB)
  elseif bytes >= MB then
    return string.format("%.1fMB", bytes / MB)
  elseif bytes >= KB then
    return string.format("%.1fKB", bytes / KB)
  else
    return string.format("%dB", bytes)
  end
end

---Format a number as a percentage string.
---@param n number
---@return string
function M.format_percent(n)
  return tostring(n) .. "%"
end

---Compute Levenshtein edit distance between two strings.
---@param a string
---@param b string
---@return integer
function M.levenshtein(a, b)
  local la, lb = #a, #b
  if la == 0 then
    return lb
  end
  if lb == 0 then
    return la
  end
  local prev, curr = {}, {}
  for j = 0, lb do
    prev[j] = j
  end
  for i = 1, la do
    curr[0] = i
    for j = 1, lb do
      local cost = a:byte(i) == b:byte(j) and 0 or 1
      curr[j] = math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
    end
    prev, curr = curr, prev
  end
  return prev[lb]
end

---Find the closest match for a name among candidates.
---Returns nil if no candidate is within max_distance.
---@param name string
---@param candidates string[]|table<string, any> Array of strings or table whose keys are candidates
---@param max_distance? integer Maximum edit distance to consider (default: 3)
---@return string|nil closest The closest candidate, or nil if none is close enough
function M.closest_match(name, candidates, max_distance)
  max_distance = max_distance or 3
  local best, best_dist = nil, math.huge
  local iter = type(candidates) == "table" and candidates or {}
  -- Support both arrays and key-value tables
  if #iter > 0 then
    for _, candidate in ipairs(iter) do
      local dist = M.levenshtein(name, candidate)
      if dist < best_dist then
        best, best_dist = candidate, dist
      end
    end
  else
    for key in pairs(iter) do
      local candidate = key --[[@as string]]
      local dist = M.levenshtein(name, candidate)
      if dist < best_dist then
        best, best_dist = candidate, dist
      end
    end
  end
  if best and best_dist <= max_distance then
    return best
  end
  return nil
end

---Format an elapsed duration in seconds for compact display.
---@param seconds number Elapsed time in seconds (fractional allowed, floored to integer)
---@return string formatted e.g. "3s", "1m 3s", "12m 45s"
function M.format_elapsed(seconds)
  local total = math.floor(seconds)
  if total < 60 then
    return total .. "s"
  end
  local minutes = math.floor(total / 60)
  local remaining_seconds = total % 60
  return minutes .. "m " .. remaining_seconds .. "s"
end

return M
