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

---Format a cost in USD with smart precision.
---Sub-cent values (> 0 and < 0.01) use 4 decimal places; otherwise 2.
---@param cost number
---@return string
function M.format_cost(cost)
  if cost > 0 and cost < 0.01 then
    return string.format("$%.4f", cost)
  end
  return string.format("$%.2f", cost)
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

return M
