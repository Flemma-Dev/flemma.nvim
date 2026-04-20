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
    vim.cmd("silent! %bdelete!")
  end)

  ---@return integer bufnr, integer winid
  local function open_chat_in_current_win()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = "chat"
    return bufnr, vim.api.nvim_get_current_win()
  end

  it("applies the default '2n' when unset in user config", function()
    flemma.setup({})
    local bufnr, winid = open_chat_in_current_win()
    vim.api.nvim_set_option_value("conceallevel", 0, { win = winid })
    vim.api.nvim_set_option_value("concealcursor", "", { win = winid })

    ui.apply_chat_window_settings(winid, bufnr)

    assert.are.equal(2, vim.api.nvim_get_option_value("conceallevel", { win = winid }))
    assert.are.equal("n", vim.api.nvim_get_option_value("concealcursor", { win = winid }))
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
    -- Clear the default "2n" via runtime writer
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
end)
