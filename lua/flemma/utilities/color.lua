--- Stateless color manipulation utilities
--- Hex/RGB conversion, additive blending, and WCAG 2.1 contrast enforcement.
--- No Vim API dependencies — pure Lua color math.
---@class flemma.utilities.Color
local M = {}

---@class flemma.utilities.color.RGB
---@field r integer 0-255
---@field g integer 0-255
---@field b integer 0-255

---Convert hex color string to RGB table
---@param hex? string Hex color (e.g., "#ff0000" or "ff0000")
---@return flemma.utilities.color.RGB|nil
function M.hex_to_rgb(hex)
  if not hex then
    return nil
  end
  hex = hex:gsub("^#", "")
  if #hex ~= 6 then
    return nil
  end
  local r = tonumber(hex:sub(1, 2), 16)
  local g = tonumber(hex:sub(3, 4), 16)
  local b = tonumber(hex:sub(5, 6), 16)
  if not (r and g and b) then
    return nil
  end
  return { r = r, g = g, b = b }
end

---Convert RGB table to hex color string
---@param rgb flemma.utilities.color.RGB
---@return string hex Hex color (e.g., "#ff0000")
function M.rgb_to_hex(rgb)
  return string.format("#%02x%02x%02x", math.floor(rgb.r), math.floor(rgb.g), math.floor(rgb.b))
end

---Blend two colors by adding or subtracting their RGB values (clamped to 0-255)
---@param base_rgb flemma.utilities.color.RGB
---@param mod_rgb flemma.utilities.color.RGB
---@param direction "+" | "-"
---@return flemma.utilities.color.RGB
function M.blend(base_rgb, mod_rgb, direction)
  local clamp = function(v)
    return math.max(0, math.min(255, v))
  end
  if direction == "+" then
    return {
      r = clamp(base_rgb.r + mod_rgb.r),
      g = clamp(base_rgb.g + mod_rgb.g),
      b = clamp(base_rgb.b + mod_rgb.b),
    }
  else
    return {
      r = clamp(base_rgb.r - mod_rgb.r),
      g = clamp(base_rgb.g - mod_rgb.g),
      b = clamp(base_rgb.b - mod_rgb.b),
    }
  end
end

---Linearize a single sRGB channel value (0-255) to linear RGB (0.0-1.0)
---@param channel integer 0-255
---@return number linear 0.0-1.0
local function srgb_to_linear(channel)
  local s = channel / 255
  if s <= 0.04045 then
    return s / 12.92
  end
  return ((s + 0.055) / 1.055) ^ 2.4
end

---Compute WCAG 2.1 relative luminance from a hex color string
---@param hex string Hex color (e.g. "#ff0000")
---@return number luminance 0.0-1.0
function M.relative_luminance(hex)
  local rgb = M.hex_to_rgb(hex)
  if not rgb then
    return 0
  end
  local r_lin = srgb_to_linear(rgb.r)
  local g_lin = srgb_to_linear(rgb.g)
  local b_lin = srgb_to_linear(rgb.b)
  return 0.2126 * r_lin + 0.7152 * g_lin + 0.0722 * b_lin
end

---Compute WCAG contrast ratio between two hex colors
---@param hex_a string Hex color
---@param hex_b string Hex color
---@return number ratio Contrast ratio (1.0 to 21.0)
function M.contrast_ratio(hex_a, hex_b)
  local lum_a = M.relative_luminance(hex_a)
  local lum_b = M.relative_luminance(hex_b)
  local lighter = math.max(lum_a, lum_b)
  local darker = math.min(lum_a, lum_b)
  return (lighter + 0.05) / (darker + 0.05)
end

---Adjust fg color to meet minimum contrast ratio against a bg color.
---Interpolates fg toward white (dark bg) or black (light bg) using binary search.
---@param fg_hex string Foreground hex color
---@param bg_hex string Background hex color
---@param target_ratio number Minimum contrast ratio (e.g. 4.5)
---@return string adjusted_fg Hex color meeting the contrast target
function M.ensure_contrast(fg_hex, bg_hex, target_ratio)
  if M.contrast_ratio(fg_hex, bg_hex) >= target_ratio then
    return fg_hex
  end

  local fg_rgb = M.hex_to_rgb(fg_hex)
  if not fg_rgb then
    return fg_hex
  end

  local bg_lum = M.relative_luminance(bg_hex)
  -- Choose direction: dark bg -> lighten toward white, light bg -> darken toward black
  local target_rgb = bg_lum < 0.5 and { r = 255, g = 255, b = 255 } or { r = 0, g = 0, b = 0 }

  -- Binary search for the minimum interpolation factor that meets the target ratio
  local lo, hi = 0.0, 1.0
  for _ = 1, 32 do
    local mid = (lo + hi) / 2
    local candidate = {
      r = math.floor(fg_rgb.r * (1 - mid) + target_rgb.r * mid + 0.5),
      g = math.floor(fg_rgb.g * (1 - mid) + target_rgb.g * mid + 0.5),
      b = math.floor(fg_rgb.b * (1 - mid) + target_rgb.b * mid + 0.5),
    }
    local candidate_hex = M.rgb_to_hex(candidate)
    if M.contrast_ratio(candidate_hex, bg_hex) >= target_ratio then
      hi = mid
    else
      lo = mid
    end
  end

  -- Use the final `hi` value (guaranteed to meet ratio, or as close as possible)
  local final = {
    r = math.floor(fg_rgb.r * (1 - hi) + target_rgb.r * hi + 0.5),
    g = math.floor(fg_rgb.g * (1 - hi) + target_rgb.g * hi + 0.5),
    b = math.floor(fg_rgb.b * (1 - hi) + target_rgb.b * hi + 0.5),
  }
  local result = M.rgb_to_hex(final)

  -- If primary direction failed (e.g., fg and bg on same extreme), flip
  if M.contrast_ratio(result, bg_hex) < target_ratio then
    local alt_rgb = bg_lum < 0.5 and { r = 0, g = 0, b = 0 } or { r = 255, g = 255, b = 255 }
    lo, hi = 0.0, 1.0
    for _ = 1, 32 do
      local mid = (lo + hi) / 2
      local candidate = {
        r = math.floor(fg_rgb.r * (1 - mid) + alt_rgb.r * mid + 0.5),
        g = math.floor(fg_rgb.g * (1 - mid) + alt_rgb.g * mid + 0.5),
        b = math.floor(fg_rgb.b * (1 - mid) + alt_rgb.b * mid + 0.5),
      }
      if M.contrast_ratio(M.rgb_to_hex(candidate), bg_hex) >= target_ratio then
        hi = mid
      else
        lo = mid
      end
    end
    result = M.rgb_to_hex({
      r = math.floor(fg_rgb.r * (1 - hi) + alt_rgb.r * hi + 0.5),
      g = math.floor(fg_rgb.g * (1 - hi) + alt_rgb.g * hi + 0.5),
      b = math.floor(fg_rgb.b * (1 - hi) + alt_rgb.b * hi + 0.5),
    })
  end

  return result
end

return M
