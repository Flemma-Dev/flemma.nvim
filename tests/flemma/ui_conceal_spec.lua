describe("UI conceal override", function()
  local flemma
  local ui

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.ui"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.tools"] = nil

    flemma = require("flemma")
    ui = require("flemma.ui")

    vim.cmd("silent! %bdelete!")
  end)

  after_each(function()
    vim.cmd("silent! only")
    vim.cmd("silent! %bdelete!")
  end)

  ---@return integer bufnr, integer winid
  local function open_chat_in_current_win()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = "chat"
    return bufnr, vim.api.nvim_get_current_win()
  end

  it("applies the default '2nv' when unset in user config", function()
    flemma.setup({})
    local bufnr, winid = open_chat_in_current_win()
    vim.api.nvim_set_option_value("conceallevel", 0, { win = winid })
    vim.api.nvim_set_option_value("concealcursor", "", { win = winid })

    ui.apply_chat_window_settings(winid, bufnr)

    assert.are.equal(2, vim.api.nvim_get_option_value("conceallevel", { win = winid }))
    assert.are.equal("nv", vim.api.nvim_get_option_value("concealcursor", { win = winid }))
  end)

  it("parses a string '0i' into conceallevel=0 concealcursor='i'", function()
    flemma.setup({ editing = { conceal = "0i" } })
    local bufnr, winid = open_chat_in_current_win()

    ui.apply_chat_window_settings(winid, bufnr)

    assert.are.equal(0, vim.api.nvim_get_option_value("conceallevel", { win = winid }))
    assert.are.equal("i", vim.api.nvim_get_option_value("concealcursor", { win = winid }))
  end)

  it("accepts an integer '3' as conceallevel=3 with empty concealcursor", function()
    flemma.setup({ editing = { conceal = 3 } })
    local bufnr, winid = open_chat_in_current_win()
    vim.api.nvim_set_option_value("concealcursor", "nv", { win = winid })

    ui.apply_chat_window_settings(winid, bufnr)

    assert.are.equal(3, vim.api.nvim_get_option_value("conceallevel", { win = winid }))
    assert.are.equal("", vim.api.nvim_get_option_value("concealcursor", { win = winid }))
  end)

  it("accepts multi-char concealcursor like '1nvic'", function()
    flemma.setup({ editing = { conceal = "1nvic" } })
    local bufnr, winid = open_chat_in_current_win()

    ui.apply_chat_window_settings(winid, bufnr)

    assert.are.equal(1, vim.api.nvim_get_option_value("conceallevel", { win = winid }))
    assert.are.equal("nvic", vim.api.nvim_get_option_value("concealcursor", { win = winid }))
  end)

  it("leaves window settings untouched when conceal=false", function()
    flemma.setup({ editing = { conceal = false } })
    local bufnr, winid = open_chat_in_current_win()
    vim.api.nvim_set_option_value("conceallevel", 3, { win = winid })
    vim.api.nvim_set_option_value("concealcursor", "v", { win = winid })

    ui.apply_chat_window_settings(winid, bufnr)

    assert.are.equal(3, vim.api.nvim_get_option_value("conceallevel", { win = winid }))
    assert.are.equal("v", vim.api.nvim_get_option_value("concealcursor", { win = winid }))
  end)

  it("leaves window settings untouched when conceal=nil at runtime", function()
    flemma.setup({})
    local bufnr, winid = open_chat_in_current_win()
    local config = require("flemma.config")
    -- Clear the default "2nv" via runtime writer
    local writer = config.writer(bufnr, config.LAYERS.RUNTIME)
    writer.editing.conceal = nil
    vim.api.nvim_set_option_value("conceallevel", 3, { win = winid })
    vim.api.nvim_set_option_value("concealcursor", "v", { win = winid })

    ui.apply_chat_window_settings(winid, bufnr)

    assert.are.equal(3, vim.api.nvim_get_option_value("conceallevel", { win = winid }))
    assert.are.equal("v", vim.api.nvim_get_option_value("concealcursor", { win = winid }))
  end)

  it("ignores malformed values without raising", function()
    flemma.setup({ editing = { conceal = "garbage" } })
    local bufnr, winid = open_chat_in_current_win()
    vim.api.nvim_set_option_value("conceallevel", 3, { win = winid })

    ui.apply_chat_window_settings(winid, bufnr)

    assert.are.equal(3, vim.api.nvim_get_option_value("conceallevel", { win = winid }))
  end)

  describe("toggle_conceal", function()
    it("flips conceallevel from configured to 0", function()
      flemma.setup({ editing = { conceal = "2nv" } })
      local _, winid = open_chat_in_current_win()
      vim.api.nvim_set_option_value("conceallevel", 2, { win = winid, scope = "local" })

      ui.toggle_conceal()

      assert.are.equal(0, vim.api.nvim_get_option_value("conceallevel", { win = winid }))
    end)

    it("flips conceallevel from 0 back to configured", function()
      flemma.setup({ editing = { conceal = "2nv" } })
      local _, winid = open_chat_in_current_win()
      vim.api.nvim_set_option_value("conceallevel", 0, { win = winid, scope = "local" })

      ui.toggle_conceal()

      assert.are.equal(2, vim.api.nvim_get_option_value("conceallevel", { win = winid }))
    end)

    it("respects non-default configured level", function()
      flemma.setup({ editing = { conceal = "1n" } })
      local _, winid = open_chat_in_current_win()
      vim.api.nvim_set_option_value("conceallevel", 1, { win = winid, scope = "local" })

      ui.toggle_conceal()
      assert.are.equal(0, vim.api.nvim_get_option_value("conceallevel", { win = winid }))

      ui.toggle_conceal()
      assert.are.equal(1, vim.api.nvim_get_option_value("conceallevel", { win = winid }))
    end)

    it("is a no-op when conceal is false", function()
      flemma.setup({ editing = { conceal = false } })
      local _, winid = open_chat_in_current_win()
      vim.api.nvim_set_option_value("conceallevel", 3, { win = winid, scope = "local" })

      ui.toggle_conceal()

      assert.are.equal(3, vim.api.nvim_get_option_value("conceallevel", { win = winid }))
    end)

    it("keeps frontmatter fold open when toggling to conceallevel 0", function()
      package.loaded["flemma.ui.folding"] = nil
      package.loaded["flemma.ui.folding.merge"] = nil
      package.loaded["flemma.ui.folding.rules.frontmatter"] = nil
      package.loaded["flemma.ui.folding.rules.thinking"] = nil
      package.loaded["flemma.ui.folding.rules.tool_blocks"] = nil
      package.loaded["flemma.ui.folding.rules.messages"] = nil
      package.loaded["flemma.parser"] = nil
      package.loaded["flemma.ast"] = nil
      package.loaded["flemma.ast.nodes"] = nil
      package.loaded["flemma.ast.query"] = nil

      flemma.setup({ editing = { conceal = "2nv" } })
      ui = require("flemma.ui")
      local folding = require("flemma.ui.folding")

      local bufnr, winid = open_chat_in_current_win()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "```lua",
        "model = 'claude-sonnet-4-20250514'",
        "```",
        "",
        "@You:",
        "Hello",
      })

      -- Set up folding with conceallevel=2 (frontmatter fold suppressed)
      vim.api.nvim_set_option_value("conceallevel", 2, { win = winid, scope = "local" })
      folding.setup_folding(bufnr)

      -- Toggle to conceallevel=0 — frontmatter fold appears but should stay open
      ui.toggle_conceal()

      assert.are.equal(0, vim.api.nvim_get_option_value("conceallevel", { win = winid }))
      assert.are.equal(-1, vim.fn.foldclosed(1), "frontmatter should not be folded after toggle")
    end)

    it("does not touch concealcursor", function()
      flemma.setup({ editing = { conceal = "2nv" } })
      local _, winid = open_chat_in_current_win()
      vim.api.nvim_set_option_value("conceallevel", 2, { win = winid, scope = "local" })
      vim.api.nvim_set_option_value("concealcursor", "nv", { win = winid, scope = "local" })

      ui.toggle_conceal()

      assert.are.equal("nv", vim.api.nvim_get_option_value("concealcursor", { win = winid }))
    end)
  end)

  it("does not leak chat conceal to a sibling window opened from a chat window", function()
    -- Repro: open a .chat buffer, then `:vsplit` (or `:tabedit`) to open a
    -- non-chat file. Neovim copies window-local options to the new window, so
    -- the sibling inherits Flemma's conceallevel=2 / concealcursor="nv"
    -- even though it's not a chat buffer. The new window should instead
    -- carry the global conceal values, letting the non-chat filetype's own
    -- ftplugins decide conceal behaviour.
    flemma.setup({})

    local expected_level = vim.go.conceallevel
    local expected_cursor = vim.go.concealcursor

    -- 1) Open a chat buffer; FileType autocmd applies Flemma's conceal
    local chat_bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(chat_bufnr)
    vim.bo[chat_bufnr].filetype = "chat"
    local chat_winid = vim.api.nvim_get_current_win()

    assert.are.equal(2, vim.api.nvim_get_option_value("conceallevel", { win = chat_winid }))
    assert.are.equal("nv", vim.api.nvim_get_option_value("concealcursor", { win = chat_winid }))

    -- 2) :vsplit — Neovim creates a new window that inherits window-local
    --    options from the chat window (this is the leak).
    vim.cmd("vsplit")
    local new_winid = vim.api.nvim_get_current_win()
    assert.are_not.equal(chat_winid, new_winid)

    -- 3) Load a non-chat buffer (e.g., :edit IDEAS.md after the split)
    local md_bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(md_bufnr)
    vim.bo[md_bufnr].filetype = "markdown"

    -- 4) The sibling window should NOT carry chat's conceal values
    assert.are.equal(
      expected_level,
      vim.api.nvim_get_option_value("conceallevel", { win = new_winid }),
      "sibling window must not inherit chat conceallevel"
    )
    assert.are.equal(
      expected_cursor,
      vim.api.nvim_get_option_value("concealcursor", { win = new_winid }),
      "sibling window must not inherit chat concealcursor"
    )

    -- 5) The original chat window is untouched
    assert.are.equal(2, vim.api.nvim_get_option_value("conceallevel", { win = chat_winid }))
    assert.are.equal("nv", vim.api.nvim_get_option_value("concealcursor", { win = chat_winid }))
  end)
end)
