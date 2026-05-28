describe("flemma.hl", function()
  local h

  before_each(function()
    package.loaded["flemma.hl"] = nil
    package.loaded["flemma.utilities.color"] = nil
    h = require("flemma.hl")

    -- Set up test highlight groups
    vim.api.nvim_set_hl(0, "TestNormal", { fg = "#ffffff", bg = "#000000" })
    vim.api.nvim_set_hl(0, "TestComment", { fg = "#888888", bg = "#111111", italic = true })
    vim.api.nvim_set_hl(0, "TestLinked", { link = "TestComment" })
    vim.api.nvim_set_hl(0, "TestFgOnly", { fg = "#ff0000" })
    vim.api.nvim_set_hl(0, "TestEmpty", {})
    vim.api.nvim_set_hl(0, "TestBold", { bold = true, fg = "#aabbcc" })
    vim.api.nvim_set_hl(0, "TestCursorLine", { bg = "#1a1a1a" })
  end)

  after_each(function()
    -- Clean up test groups
    for _, name in ipairs({
      "TestNormal",
      "TestComment",
      "TestLinked",
      "TestFgOnly",
      "TestEmpty",
      "TestBold",
      "TestCursorLine",
      "FlemmaTestGroup",
      "FlemmaTestLink",
    }) do
      pcall(vim.api.nvim_set_hl, 0, name, {})
    end
  end)

  -- ---------------------------------------------------------------------------
  -- LinkOp
  -- ---------------------------------------------------------------------------

  describe("h.link()", function()
    it("returns a link table", function()
      local result = h.link("Function"):get()
      assert.same({ link = "Function" }, result)
    end)

    it("sets a link highlight group", function()
      h.link("TestComment"):set("FlemmaTestLink")
      local hl = vim.api.nvim_get_hl(0, { name = "FlemmaTestLink" })
      assert.is_not_nil(hl.link)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- FromOp
  -- ---------------------------------------------------------------------------

  describe("h.from()", function()
    it("resolves concrete attrs from an existing group", function()
      local result = h.from("TestComment"):get()
      assert.is_not_nil(result)
      assert.equals("#888888", result.fg)
      assert.equals("#111111", result.bg)
      assert.is_true(result.italic)
    end)

    it("returns nil for nonexistent group", function()
      local result = h.from("NonExistentGroup12345"):get()
      assert.is_nil(result)
    end)

    it("returns nil for empty group", function()
      local result = h.from("TestEmpty"):get()
      assert.is_nil(result)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- HexOp
  -- ---------------------------------------------------------------------------

  describe("h.hex()", function()
    it("defaults to fg attr", function()
      local result = h.hex("#ff0000"):get()
      assert.same({ fg = "#ff0000" }, result)
    end)

    it("accepts explicit attr", function()
      local result = h.hex("#00ff00", "bg"):get()
      assert.same({ bg = "#00ff00" }, result)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- AttrsOp
  -- ---------------------------------------------------------------------------

  describe("h.attrs()", function()
    it("returns literal attrs", function()
      local result = h.attrs({ bold = true, italic = true }):get()
      assert.same({ bold = true, italic = true }, result)
    end)

    it("never returns nil", function()
      local result = h.attrs({}):get()
      assert.is_not_nil(result)
      assert.same({}, result)
    end)

    it("returns a copy, not the original table", function()
      local original = { bold = true }
      local op = h.attrs(original)
      local r1 = op:get()
      r1.italic = true
      local r2 = op:get()
      assert.is_nil(r2.italic)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- DefaultOp
  -- ---------------------------------------------------------------------------

  describe("h.default()", function()
    it("returns Normal bg when available", function()
      vim.api.nvim_set_hl(0, "Normal", { fg = "#ffffff", bg = "#1a1a2e" })
      local result = h.default("bg"):get()
      assert.same({ bg = "#1a1a2e" }, result)
    end)

    it("returns Normal fg when available", function()
      vim.api.nvim_set_hl(0, "Normal", { fg = "#aabbcc", bg = "#000000" })
      local result = h.default("fg"):get()
      assert.same({ fg = "#aabbcc" }, result)
    end)

    it("falls back to black bg in dark mode when Normal lacks bg", function()
      vim.api.nvim_set_hl(0, "Normal", {})
      vim.o.background = "dark"
      local result = h.default("bg"):get()
      assert.same({ bg = "#000000" }, result)
    end)

    it("falls back to white bg in light mode when Normal lacks bg", function()
      vim.o.background = "light"
      vim.api.nvim_set_hl(0, "Normal", {})
      local result = h.default("bg"):get()
      assert.same({ bg = "#ffffff" }, result)
      vim.o.background = "dark"
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- CoalesceOp
  -- ---------------------------------------------------------------------------

  describe("h.coalesce()", function()
    it("returns first non-nil result", function()
      local result = h.coalesce(h.from("NonExistent12345"), h.from("TestComment")):get()
      assert.is_not_nil(result)
      assert.equals("#888888", result.fg)
    end)

    it("returns nil when all children are nil", function()
      local result = h.coalesce(h.from("NonExistent1"), h.from("NonExistent2")):get()
      assert.is_nil(result)
    end)

    it("skips nil children", function()
      local result = h.coalesce(h.from("NonExistent1"), h.from("NonExistent2"), h.hex("#aabbcc")):get()
      assert.same({ fg = "#aabbcc" }, result)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- DiffOp
  -- ---------------------------------------------------------------------------

  describe("h.diff()", function()
    it("computes signed delta between two groups", function()
      vim.api.nvim_set_hl(0, "TestDiffA", { bg = "#100000" })
      vim.api.nvim_set_hl(0, "TestDiffB", { bg = "#200010" })
      local d = h.diff("TestDiffA", "TestDiffB", "bg")
      local delta = d:delta()
      assert.is_not_nil(delta)
      assert.equals(16, delta.r)
      assert.equals(0, delta.g)
      assert.equals(16, delta.b)
      pcall(vim.api.nvim_set_hl, 0, "TestDiffA", {})
      pcall(vim.api.nvim_set_hl, 0, "TestDiffB", {})
    end)

    it("errors on :get()", function()
      local d = h.diff("TestNormal", "TestComment", "bg")
      assert.has_error(function()
        d:get()
      end)
    end)

    it("errors on :set()", function()
      local d = h.diff("TestNormal", "TestComment", "bg")
      assert.has_error(function()
        d:set("FlemmaTestGroup")
      end)
    end)

    it("falls back to default_color when group_a lacks attr", function()
      local d = h.diff("TestFgOnly", "TestComment", "bg")
      local delta = d:delta()
      assert.is_not_nil(delta)
    end)

    it("returns nil delta when group_b lacks attr", function()
      local d = h.diff("TestComment", "TestFgOnly", "bg")
      assert.is_nil(d:delta())
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- ThemedOp
  -- ---------------------------------------------------------------------------

  describe("h.themed()", function()
    it("selects dark branch on dark background", function()
      local saved = vim.o.background
      vim.o.background = "dark"
      local result = h.themed({
        dark = h.hex("#111111"),
        light = h.hex("#eeeeee"),
      }):get()
      assert.same({ fg = "#111111" }, result)
      vim.o.background = saved
    end)

    it("selects light branch on light background", function()
      local saved = vim.o.background
      vim.o.background = "light"
      local result = h.themed({
        dark = h.hex("#111111"),
        light = h.hex("#eeeeee"),
      }):get()
      assert.same({ fg = "#eeeeee" }, result)
      vim.o.background = saved
    end)

    it("returns nil when branch is missing", function()
      local saved = vim.o.background
      vim.o.background = "dark"
      local result = h.themed({ light = h.hex("#eeeeee") }):get()
      assert.is_nil(result)
      vim.o.background = saved
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- BlendOp
  -- ---------------------------------------------------------------------------

  describe(":blend()", function()
    it("blends with additive hex string", function()
      local result = h.from("TestNormal"):blend("bg", "+#101010"):get()
      assert.is_not_nil(result)
      assert.equals("#101010", result.bg)
      assert.equals("#ffffff", result.fg)
    end)

    it("blends with subtractive hex string", function()
      local result = h.from("TestComment"):blend("fg", "-#080808"):get()
      assert.is_not_nil(result)
      assert.equals("#808080", result.fg)
    end)

    it("blends with a DiffOp", function()
      vim.api.nvim_set_hl(0, "TestDiffBase", { bg = "#100000" })
      vim.api.nvim_set_hl(0, "TestDiffTarget", { bg = "#200000" })
      local delta = h.diff("TestDiffBase", "TestDiffTarget", "bg")
      local result = h.from("TestNormal"):blend("bg", delta):get()
      assert.is_not_nil(result)
      assert.equals("#100000", result.bg)
      pcall(vim.api.nvim_set_hl, 0, "TestDiffBase", {})
      pcall(vim.api.nvim_set_hl, 0, "TestDiffTarget", {})
    end)

    it("falls back to Normal when parent lacks the blended attr", function()
      local result = h.from("TestFgOnly"):blend("bg", "+#101010"):get()
      assert.is_not_nil(result)
      assert.is_not_nil(result.bg)
    end)

    it("preserves other attrs", function()
      local result = h.from("TestComment"):blend("fg", "-#080808"):get()
      assert.is_not_nil(result)
      assert.equals("#111111", result.bg)
      assert.is_true(result.italic)
    end)

    it("returns nil when parent is nil", function()
      local result = h.from("NonExistent12345"):blend("bg", "+#101010"):get()
      assert.is_nil(result)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- TintOp / MuteOp
  -- ---------------------------------------------------------------------------

  describe(":tint()", function()
    it("adds in dark mode", function()
      vim.o.background = "dark"
      local result = h.from("TestNormal"):tint("bg", "#101010"):get()
      assert.is_not_nil(result)
      assert.equals("#101010", result.bg)
    end)

    it("subtracts in light mode", function()
      vim.o.background = "light"
      vim.api.nvim_set_hl(0, "TestNormal", { fg = "#000000", bg = "#ffffff" })
      local result = h.from("TestNormal"):tint("bg", "#101010"):get()
      assert.is_not_nil(result)
      assert.equals("#efefef", result.bg)
      vim.o.background = "dark"
      vim.api.nvim_set_hl(0, "TestNormal", { fg = "#ffffff", bg = "#000000" })
    end)

    it("returns nil when parent is nil", function()
      local result = h.from("NonExistent"):tint("bg", "#101010"):get()
      assert.is_nil(result)
    end)
  end)

  describe(":mute()", function()
    it("subtracts in dark mode", function()
      vim.o.background = "dark"
      local result = h.from("TestComment"):mute("fg", "#333333"):get()
      assert.is_not_nil(result)
      assert.equals("#555555", result.fg)
    end)

    it("adds in light mode", function()
      vim.o.background = "light"
      vim.api.nvim_set_hl(0, "TestComment", { fg = "#888888", bg = "#111111", italic = true })
      local result = h.from("TestComment"):mute("fg", "#333333"):get()
      assert.is_not_nil(result)
      assert.equals("#bbbbbb", result.fg)
      vim.o.background = "dark"
      vim.api.nvim_set_hl(0, "TestComment", { fg = "#888888", bg = "#111111", italic = true })
    end)

    it("returns nil when parent is nil", function()
      local result = h.from("NonExistent"):mute("fg", "#333333"):get()
      assert.is_nil(result)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- OmitOp
  -- ---------------------------------------------------------------------------

  describe(":omit()", function()
    it("strips named attrs", function()
      local result = h.from("TestComment"):omit("bg"):get()
      assert.is_not_nil(result)
      assert.is_nil(result.bg)
      assert.equals("#888888", result.fg)
      assert.is_true(result.italic)
    end)

    it("strips multiple attrs", function()
      local result = h.from("TestComment"):omit("bg", "italic"):get()
      assert.is_not_nil(result)
      assert.is_nil(result.bg)
      assert.is_nil(result.italic)
      assert.equals("#888888", result.fg)
    end)

    it("returns empty table when all attrs omitted", function()
      local result = h.from("TestFgOnly"):omit("fg"):get()
      assert.is_not_nil(result)
      assert.same({}, result)
    end)

    it("returns nil when parent is nil", function()
      local result = h.from("NonExistent"):omit("bg"):get()
      assert.is_nil(result)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- PickOp
  -- ---------------------------------------------------------------------------

  describe(":pick()", function()
    it("keeps only named attrs", function()
      local result = h.from("TestComment"):pick("fg"):get()
      assert.is_not_nil(result)
      assert.same({ fg = "#888888" }, result)
    end)

    it("keeps multiple attrs", function()
      local result = h.from("TestComment"):pick("fg", "bg"):get()
      assert.is_not_nil(result)
      assert.equals("#888888", result.fg)
      assert.equals("#111111", result.bg)
      assert.is_nil(result.italic)
    end)

    it("returns nil when no picked attrs exist", function()
      local result = h.from("TestFgOnly"):pick("bg"):get()
      assert.is_nil(result)
    end)

    it("returns nil when parent is nil", function()
      local result = h.from("NonExistent"):pick("fg"):get()
      assert.is_nil(result)
    end)

    it("strict returns nil when any picked attr is missing", function()
      local result = h.from("TestFgOnly"):pick("fg", "bg", { strict = true }):get()
      assert.is_nil(result)
    end)

    it("strict passes when all picked attrs exist", function()
      local result = h.from("TestComment"):pick("fg", "bg", { strict = true }):get()
      assert.is_not_nil(result)
      assert.equals("#888888", result.fg)
      assert.equals("#111111", result.bg)
      assert.is_nil(result.italic)
    end)

    it("strict returns nil when parent is nil", function()
      local result = h.from("NonExistent"):pick("fg", { strict = true }):get()
      assert.is_nil(result)
    end)

    it("strict strips non-picked attrs", function()
      vim.api.nvim_set_hl(0, "TestReverse", { fg = "#aabbcc", bg = "#112233", reverse = true, bold = true })
      local result = h.from("TestReverse"):pick("fg", "bg", { strict = true }):get()
      assert.is_not_nil(result)
      assert.equals("#aabbcc", result.fg)
      assert.equals("#112233", result.bg)
      assert.is_nil(result.reverse)
      assert.is_nil(result.bold)
      pcall(vim.api.nvim_set_hl, 0, "TestReverse", {})
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- ContrastOp
  -- ---------------------------------------------------------------------------

  describe(":contrast()", function()
    it("adjusts fg for contrast against bg", function()
      vim.api.nvim_set_hl(0, "TestLowContrast", { fg = "#333333" })
      vim.api.nvim_set_hl(0, "TestDarkBg", { bg = "#111111" })
      local result = h.from("TestLowContrast"):contrast("fg", h.from("TestDarkBg"):pick("bg"), 4.5):get()
      assert.is_not_nil(result)
      assert.is_not_nil(result.fg)
      assert.not_equals("#333333", result.fg)
      assert.is_nil(result.bg)
      pcall(vim.api.nvim_set_hl, 0, "TestLowContrast", {})
      pcall(vim.api.nvim_set_hl, 0, "TestDarkBg", {})
    end)

    it("preserves already-good contrast", function()
      vim.api.nvim_set_hl(0, "TestHighContrast", { fg = "#ffffff" })
      vim.api.nvim_set_hl(0, "TestDarkBg2", { bg = "#000000" })
      local result = h.from("TestHighContrast"):contrast("fg", h.from("TestDarkBg2"):pick("bg"), 4.5):get()
      assert.is_not_nil(result)
      assert.equals("#ffffff", result.fg)
      pcall(vim.api.nvim_set_hl, 0, "TestHighContrast", {})
      pcall(vim.api.nvim_set_hl, 0, "TestDarkBg2", {})
    end)

    it("returns nil when parent is nil", function()
      local result = h.from("NonExistent"):contrast("fg", h.from("TestNormal"):pick("bg"), 4.5):get()
      assert.is_nil(result)
    end)

    it("returns nil when against is nil", function()
      local result = h.from("TestComment"):contrast("fg", h.from("NonExistent"):pick("bg"), 4.5):get()
      assert.is_nil(result)
    end)

    it("preserves parent attrs without leaking against attrs", function()
      vim.api.nvim_set_hl(0, "TestSrc", { fg = "#333333", italic = true })
      vim.api.nvim_set_hl(0, "TestAgainst", { bg = "#000000", bold = true })
      local result = h.from("TestSrc"):contrast("fg", h.from("TestAgainst"), 4.5):get()
      assert.is_not_nil(result)
      assert.is_true(result.italic)
      assert.is_nil(result.bold)
      assert.is_nil(result.bg)
      pcall(vim.api.nvim_set_hl, 0, "TestSrc", {})
      pcall(vim.api.nvim_set_hl, 0, "TestAgainst", {})
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- StyleOp
  -- ---------------------------------------------------------------------------

  describe(":style()", function()
    it("merges style attrs", function()
      local result = h.from("TestComment"):style({ bold = true }):get()
      assert.is_not_nil(result)
      assert.is_true(result.bold)
      assert.is_true(result.italic)
    end)

    it("overrides existing style attrs", function()
      local result = h.from("TestComment"):style({ italic = false }):get()
      assert.is_not_nil(result)
      assert.is_false(result.italic)
    end)

    it("returns nil when parent is nil", function()
      local result = h.from("NonExistent"):style({ bold = true }):get()
      assert.is_nil(result)
    end)

    it("works on empty parent result", function()
      vim.api.nvim_set_hl(0, "TestStyleEmpty", { nocombine = true })
      local result = h.from("TestStyleEmpty"):style({ bold = true }):get()
      assert.is_not_nil(result)
      assert.is_true(result.bold)
      pcall(vim.api.nvim_set_hl, 0, "TestStyleEmpty", {})
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- MergeOp
  -- ---------------------------------------------------------------------------

  describe(":merge()", function()
    it("fills gaps with keep strategy (default)", function()
      local result = h.from("TestFgOnly"):merge(h.hex("#00ff00", "bg")):get()
      assert.is_not_nil(result)
      assert.equals("#ff0000", result.fg)
      assert.equals("#00ff00", result.bg)
    end)

    it("parent wins on conflict with keep strategy", function()
      local result = h.from("TestFgOnly"):merge(h.hex("#00ff00")):get()
      assert.is_not_nil(result)
      assert.equals("#ff0000", result.fg)
    end)

    it("other wins on conflict with force strategy", function()
      local result = h.from("TestFgOnly"):merge(h.hex("#00ff00"), "force"):get()
      assert.is_not_nil(result)
      assert.equals("#00ff00", result.fg)
    end)

    it("returns parent unchanged when other is nil", function()
      local result = h.from("TestFgOnly"):merge(h.from("NonExistent")):get()
      assert.is_not_nil(result)
      assert.equals("#ff0000", result.fg)
    end)

    it("returns nil when parent is nil", function()
      local result = h.from("NonExistent"):merge(h.hex("#ff0000")):get()
      assert.is_nil(result)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- NilOp propagation
  -- ---------------------------------------------------------------------------

  describe("NilOp propagation", function()
    it("chain on nil parent returns nil", function()
      local result = h.from("NonExistent"):pick("fg"):blend("fg", "+#101010"):get()
      assert.is_nil(result)
    end)

    it("NilOp chain methods return NilOp", function()
      local op = h.NilOp
      assert.equals(h.NilOp, op:blend("fg", "+#101010"))
      assert.equals(h.NilOp, op:pick("fg"))
      assert.equals(h.NilOp, op:omit("bg"))
      assert.equals(h.NilOp, op:tint("fg", "#101010"))
      assert.equals(h.NilOp, op:mute("fg", "#101010"))
      assert.equals(h.NilOp, op:style({ bold = true }))
      assert.equals(h.NilOp, op:merge(h.hex("#ff0000")))
      assert.equals(h.NilOp, op:contrast("fg", h.from("TestNormal"), 4.5))
    end)

    it("NilOp:set() is a silent no-op", function()
      assert.has_no_error(function()
        h.NilOp:set("FlemmaTestGroup")
      end)
    end)

    it("coalesce skips nil children", function()
      local result = h.coalesce(h.from("NonExistent1"), h.from("NonExistent2"), h.from("TestFgOnly")):get()
      assert.is_not_nil(result)
      assert.equals("#ff0000", result.fg)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- LinkOp chaining (resolve_to_attrs)
  -- ---------------------------------------------------------------------------

  describe("LinkOp chaining", function()
    it("pick resolves link to concrete attrs", function()
      local result = h.link("TestComment"):pick("fg"):get()
      assert.is_not_nil(result)
      assert.same({ fg = "#888888" }, result)
    end)

    it("omit resolves link to concrete attrs", function()
      local result = h.link("TestComment"):omit("bg"):get()
      assert.is_not_nil(result)
      assert.is_nil(result.bg)
      assert.equals("#888888", result.fg)
    end)

    it("blend resolves link to concrete attrs", function()
      local result = h.link("TestComment"):blend("fg", "-#080808"):get()
      assert.is_not_nil(result)
      assert.equals("#808080", result.fg)
    end)

    it("style resolves link to concrete attrs", function()
      local result = h.link("TestComment"):style({ bold = true }):get()
      assert.is_not_nil(result)
      assert.is_true(result.bold)
      assert.is_true(result.italic)
    end)

    it("transitive link resolution", function()
      local result = h.link("TestLinked"):pick("fg"):get()
      assert.is_not_nil(result)
      assert.same({ fg = "#888888" }, result)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- :set() invariants
  -- ---------------------------------------------------------------------------

  describe(":set() invariants", function()
    it("asserts Flemma prefix", function()
      assert.has_error(function()
        h.hex("#ff0000"):set("NotFlemma")
      end)
    end)

    it("sets default = true", function()
      h.hex("#ff0000"):set("FlemmaTestGroup")
      local hl = vim.api.nvim_get_hl(0, { name = "FlemmaTestGroup" })
      assert.is_not_nil(hl.fg)
    end)

    it("nil result is a silent no-op", function()
      assert.has_no_error(function()
        h.from("NonExistent"):set("FlemmaTestGroup")
      end)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Complex chains (real-world patterns from the spec)
  -- ---------------------------------------------------------------------------

  describe("complex chains", function()
    it("usage bar secondary tier (themed blend)", function()
      local saved = vim.o.background
      vim.o.background = "dark"
      vim.api.nvim_set_hl(0, "TestBar", { fg = "#aaaaaa", bg = "#222222" })
      local bar_base = h.from("TestBar")
      local result = h.themed({
        dark = bar_base:blend("fg", "-#222222"),
        light = bar_base:blend("fg", "+#222222"),
      }):get()
      assert.is_not_nil(result)
      assert.equals("#888888", result.fg)
      assert.equals("#222222", result.bg)
      vim.o.background = saved
      pcall(vim.api.nvim_set_hl, 0, "TestBar", {})
    end)

    it("role name: pick fg + merge with style", function()
      local role_name_op = h.attrs({ bold = true })
      local result = h.from("TestComment"):pick("fg"):merge(role_name_op):get()
      assert.is_not_nil(result)
      assert.equals("#888888", result.fg)
      assert.is_true(result.bold)
      assert.is_nil(result.bg)
      assert.is_nil(result.italic)
    end)

    it("CursorLine delta blend + decoration merge", function()
      vim.api.nvim_set_hl(0, "Normal", { fg = "#ffffff", bg = "#000000" })
      vim.api.nvim_set_hl(0, "CursorLine", { bg = "#1a1a1a", bold = true })
      vim.api.nvim_set_hl(0, "FlemmaTestLine", { bg = "#111111" })
      local cl_delta = h.diff("Normal", "CursorLine", "bg")
      local cl_decorations = h.from("CursorLine"):omit("fg", "bg", "sp")
      local result = h.from("FlemmaTestLine"):blend("bg", cl_delta):merge(cl_decorations):get()
      assert.is_not_nil(result)
      assert.is_true(result.bold)
      assert.is_not_nil(result.bg)
      pcall(vim.api.nvim_set_hl, 0, "FlemmaTestLine", {})
    end)

    it("blend then contrast chain", function()
      vim.api.nvim_set_hl(0, "TestLightFg", { fg = "#ffffff" })
      local result = h.from("TestLightFg"):blend("fg", "-#dddddd"):contrast("fg", h.hex("#111111", "bg"), 4.5):get()
      assert.is_not_nil(result)
      assert.is_not_nil(result.fg)
      local color = require("flemma.utilities.color")
      local ratio = color.contrast_ratio(result.fg, "#111111")
      assert.is_true(ratio >= 4.5, "blend then contrast should meet 4.5:1: got " .. tostring(ratio))
      pcall(vim.api.nvim_set_hl, 0, "TestLightFg", {})
    end)

    it("coalesce with contrast fallback", function()
      vim.api.nvim_set_hl(0, "TestDiag", { fg = "#333333" })
      vim.api.nvim_set_hl(0, "TestBarBg", { bg = "#111111" })
      local result =
        h.coalesce(h.from("TestDiag"):contrast("fg", h.from("TestBarBg"):pick("bg"), 4.5), h.link("TestDiag")):get()
      assert.is_not_nil(result)
      assert.is_not_nil(result.fg)
      pcall(vim.api.nvim_set_hl, 0, "TestDiag", {})
      pcall(vim.api.nvim_set_hl, 0, "TestBarBg", {})
    end)
  end)
end)
