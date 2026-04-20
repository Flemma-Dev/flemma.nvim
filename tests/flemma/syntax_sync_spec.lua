describe("chat syntax sync", function()
  local flemma
  local highlight

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.highlight"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.core"] = nil

    flemma = require("flemma")
    highlight = require("flemma.highlight")
    flemma.setup({})
    vim.cmd("silent! %bdelete!")
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  ---@param line_idx integer 1-based line number
  ---@return string[] group names on the Vim syntax stack at column 1
  local function synstack_at(line_idx)
    local names = {}
    for _, id in ipairs(vim.fn.synstack(line_idx, 1)) do
      table.insert(names, vim.fn.synIDattr(id, "name"))
    end
    return names
  end

  it("matches FlemmaToolUseTitle on every Tool Use header separated by code blocks", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = "chat"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```lua", -- 1
      'x = "y"', -- 2
      "```", -- 3
      "@You:", -- 4
      "hi", -- 5
      "", -- 6
      "@Assistant:", -- 7
      "ok", -- 8
      "", -- 9
      "**Tool Use:** `bash` (`t1`)", -- 10
      "", -- 11
      "```json", -- 12
      '{"a":1}', -- 13
      "```", -- 14
      "", -- 15
      "**Tool Use:** `bash` (`t2`)", -- 16
      "", -- 17
      "```json", -- 18
      '{"a":2}', -- 19
      "```", -- 20
      "", -- 21
      "**Tool Use:** `bash` (`t3`)", -- 22
    })

    highlight.apply_syntax()

    for _, lnum in ipairs({ 10, 16, 22 }) do
      local stack = synstack_at(lnum)
      assert.is_truthy(
        vim.tbl_contains(stack, "FlemmaToolUseTitle"),
        string.format("line %d missing FlemmaToolUseTitle; got [%s]", lnum, table.concat(stack, ","))
      )
    end
  end)

  it("matches FlemmaToolResultTitle on every Tool Result header separated by code blocks", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = "chat"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:", -- 1
      "", -- 2
      "**Tool Result:** `t1`", -- 3
      "", -- 4
      "```", -- 5
      "output 1", -- 6
      "```", -- 7
      "", -- 8
      "**Tool Result:** `t2`", -- 9
      "", -- 10
      "```", -- 11
      "output 2", -- 12
      "```", -- 13
      "", -- 14
      "**Tool Result:** `t3`", -- 15
    })

    highlight.apply_syntax()

    for _, lnum in ipairs({ 3, 9, 15 }) do
      local stack = synstack_at(lnum)
      assert.is_truthy(
        vim.tbl_contains(stack, "FlemmaToolResultTitle"),
        string.format("line %d missing FlemmaToolResultTitle; got [%s]", lnum, table.concat(stack, ","))
      )
    end
  end)

  it("applies a distinct FlemmaToolResult* highlight for every concise status suffix", function()
    local cases = {
      { suffix = "(pending)", group = "FlemmaToolResultPending" },
      { suffix = "(approved)", group = "FlemmaToolResultApproved" },
      { suffix = "(rejected)", group = "FlemmaToolResultRejected" },
      { suffix = "(denied)", group = "FlemmaToolResultDenied" },
      { suffix = "(aborted)", group = "FlemmaToolResultAborted" },
      { suffix = "(error)", group = "FlemmaToolResultError" },
    }

    local lines = { "@You:", "" }
    for _, case in ipairs(cases) do
      table.insert(lines, "**Tool Result:** `t` " .. case.suffix)
      table.insert(lines, "")
    end

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = "chat"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    highlight.apply_syntax()

    for index, case in ipairs(cases) do
      local lnum = 2 + (index - 1) * 2 + 1 -- skip header (2 lines) + preceding case blocks
      local header = vim.fn.getline(lnum)
      local suffix_col = header:find(case.suffix:sub(1, 1), 1, true) -- find "(" byte-1-indexed
      assert.is_truthy(suffix_col, "missing suffix on line " .. lnum .. ": " .. header)
      local stack = synstack_at(lnum)
      -- synstack_at probes col 1; widen check by also probing inside the suffix.
      local inside = {}
      for _, id in ipairs(vim.fn.synstack(lnum, suffix_col + 1)) do
        table.insert(inside, vim.fn.synIDattr(id, "name"))
      end
      assert.is_truthy(
        vim.tbl_contains(inside, case.group),
        string.format(
          "line %d missing %s at col %d; stack=[%s] header_stack=[%s]",
          lnum,
          case.group,
          suffix_col + 1,
          table.concat(inside, ","),
          table.concat(stack, ",")
        )
      )
    end
  end)
end)
