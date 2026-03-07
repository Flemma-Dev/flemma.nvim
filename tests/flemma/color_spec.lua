describe("flemma.utilities.color", function()
  local color

  before_each(function()
    package.loaded["flemma.utilities.color"] = nil
    color = require("flemma.utilities.color")
  end)

  describe("hex_to_rgb", function()
    it("should convert hex with hash prefix", function()
      local rgb = color.hex_to_rgb("#ff0000")
      assert.are.equal(255, rgb.r)
      assert.are.equal(0, rgb.g)
      assert.are.equal(0, rgb.b)
    end)

    it("should convert hex without hash prefix", function()
      local rgb = color.hex_to_rgb("00ff00")
      assert.are.equal(0, rgb.r)
      assert.are.equal(255, rgb.g)
      assert.are.equal(0, rgb.b)
    end)

    it("should return nil for nil input", function()
      assert.is_nil(color.hex_to_rgb(nil))
    end)

    it("should return nil for invalid hex length", function()
      assert.is_nil(color.hex_to_rgb("#fff"))
    end)
  end)

  describe("rgb_to_hex", function()
    it("should convert RGB to hex", function()
      assert.are.equal("#ff0000", color.rgb_to_hex({ r = 255, g = 0, b = 0 }))
      assert.are.equal("#000000", color.rgb_to_hex({ r = 0, g = 0, b = 0 }))
      assert.are.equal("#ffffff", color.rgb_to_hex({ r = 255, g = 255, b = 255 }))
    end)
  end)

  describe("blend", function()
    it("should add colors", function()
      local result = color.blend({ r = 100, g = 50, b = 0 }, { r = 10, g = 20, b = 30 }, "+")
      assert.are.equal(110, result.r)
      assert.are.equal(70, result.g)
      assert.are.equal(30, result.b)
    end)

    it("should subtract colors", function()
      local result = color.blend({ r = 100, g = 50, b = 30 }, { r = 10, g = 20, b = 30 }, "-")
      assert.are.equal(90, result.r)
      assert.are.equal(30, result.g)
      assert.are.equal(0, result.b)
    end)

    it("should clamp to 0-255", function()
      local result = color.blend({ r = 250, g = 0, b = 0 }, { r = 10, g = 10, b = 10 }, "+")
      assert.are.equal(255, result.r)

      local sub = color.blend({ r = 5, g = 0, b = 0 }, { r = 10, g = 10, b = 10 }, "-")
      assert.are.equal(0, sub.r)
      assert.are.equal(0, sub.g)
    end)
  end)

  describe("relative_luminance", function()
    it("should return 0 for black", function()
      assert.is_near(0.0, color.relative_luminance("#000000"), 0.001)
    end)

    it("should return 1 for white", function()
      assert.is_near(1.0, color.relative_luminance("#ffffff"), 0.001)
    end)

    it("should compute luminance for mid-gray", function()
      -- #808080 -> each channel 128/255 = 0.502
      -- linearized: ((0.502 + 0.055) / 1.055)^2.4 ≈ 0.2159
      -- luminance: 0.2126*0.2159 + 0.7152*0.2159 + 0.0722*0.2159 ≈ 0.2159
      local lum = color.relative_luminance("#808080")
      assert.is_near(0.2159, lum, 0.01)
    end)
  end)

  describe("contrast_ratio", function()
    it("should return 21:1 for black on white", function()
      assert.is_near(21.0, color.contrast_ratio("#ffffff", "#000000"), 0.1)
    end)

    it("should return 1:1 for same color", function()
      assert.is_near(1.0, color.contrast_ratio("#ff0000", "#ff0000"), 0.01)
    end)

    it("should be symmetric", function()
      local ratio_ab = color.contrast_ratio("#336699", "#ccddee")
      local ratio_ba = color.contrast_ratio("#ccddee", "#336699")
      assert.is_near(ratio_ab, ratio_ba, 0.001)
    end)
  end)

  describe("ensure_contrast", function()
    it("should return fg unchanged when contrast is sufficient", function()
      -- White on black is 21:1 — well above 4.5
      local result = color.ensure_contrast("#ffffff", "#000000", 4.5)
      assert.are.equal("#ffffff", result)
    end)

    it("should lighten fg against dark bg when contrast is insufficient", function()
      -- Dark gray on black — very low contrast
      local result = color.ensure_contrast("#222222", "#000000", 4.5)
      -- Result should be lighter than #222222
      local original_lum = color.relative_luminance("#222222")
      local adjusted_lum = color.relative_luminance(result)
      assert.is_true(adjusted_lum > original_lum, "should lighten toward white")
      -- And should meet the target ratio
      local ratio = color.contrast_ratio(result, "#000000")
      assert.is_true(ratio >= 4.5, "should meet 4.5:1 contrast: got " .. tostring(ratio))
    end)

    it("should darken fg against light bg when contrast is insufficient", function()
      -- Light gray on white — very low contrast
      local result = color.ensure_contrast("#dddddd", "#ffffff", 4.5)
      local original_lum = color.relative_luminance("#dddddd")
      local adjusted_lum = color.relative_luminance(result)
      assert.is_true(adjusted_lum < original_lum, "should darken toward black")
      local ratio = color.contrast_ratio(result, "#ffffff")
      assert.is_true(ratio >= 4.5, "should meet 4.5:1 contrast: got " .. tostring(ratio))
    end)

    it("should handle extreme case: same color as bg", function()
      local result = color.ensure_contrast("#336699", "#336699", 4.5)
      local ratio = color.contrast_ratio(result, "#336699")
      assert.is_true(ratio >= 4.5, "should meet 4.5:1 even when fg == bg: got " .. tostring(ratio))
    end)
  end)
end)
