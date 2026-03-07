--- Shared string display-width utilities for Flemma UI
--- All display-width calculations and width-aware truncation go through this module.
---@class flemma.utilities.String
local M = {}

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

return M
