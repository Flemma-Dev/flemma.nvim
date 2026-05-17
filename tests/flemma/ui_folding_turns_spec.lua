describe("UI Folding Turns", function()
  local flemma
  local folding
  local turns

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.ui"] = nil
    package.loaded["flemma.ui.preview"] = nil
    package.loaded["flemma.ui.folding"] = nil
    package.loaded["flemma.ui.folding.merge"] = nil
    package.loaded["flemma.ui.folding.rules.frontmatter"] = nil
    package.loaded["flemma.ui.folding.rules.thinking"] = nil
    package.loaded["flemma.ui.folding.rules.tool_blocks"] = nil
    package.loaded["flemma.ui.folding.rules.messages"] = nil
    package.loaded["flemma.ui.turns"] = nil
    package.loaded["flemma.ast"] = nil
    package.loaded["flemma.ast.nodes"] = nil
    package.loaded["flemma.ast.query"] = nil
    package.loaded["flemma.parser"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.tools.context"] = nil
    package.loaded["flemma.tools.injector"] = nil

    flemma = require("flemma")
    folding = require("flemma.ui.folding")
    turns = require("flemma.ui.turns")

    flemma.setup({})

    vim.cmd("silent! %bdelete!")
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  ---Create a chat buffer with folding and turns initialized in a window.
  ---@param lines string[]
  ---@return integer bufnr
  local function setup_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.bo[bufnr].filetype = "chat"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    vim.cmd("new")
    vim.api.nvim_set_current_buf(bufnr)
    vim.wo.foldmethod = "expr"
    vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
    vim.wo.foldlevel = 99

    turns.setup_statuscolumn(bufnr)
    turns.update(bufnr)

    return bufnr
  end

  describe("fold_turn_at_cursor", function()
    it("folds intermediate messages in the turn under cursor", function()
      local bufnr = setup_buffer({
        "@You:", -- 1
        "What files exist?", -- 2
        "@Assistant:", -- 3
        "**Tool Use:** `ls` (`tool_1`)", -- 4
        "```json", -- 5
        '{"path": "."}', -- 6
        "```", -- 7
        "@You:", -- 8
        "**Tool Result:** `tool_1`", -- 9
        "```", -- 10
        "file1.txt", -- 11
        "```", -- 12
        "@Assistant:", -- 13
        "I found file1.txt", -- 14
      })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      folding.fold_turn_at_cursor(bufnr)

      -- First message (@You line 1) should remain open
      assert.are.equal(-1, vim.fn.foldclosed(1), "First message should remain open")
      -- Intermediate: @Assistant with tool_use (line 3) should be folded
      assert.are.equal(3, vim.fn.foldclosed(3), "Intermediate assistant message should be folded")
      -- Intermediate: @You with tool_result (line 8) should be folded
      assert.are.equal(8, vim.fn.foldclosed(8), "Intermediate tool result message should be folded")
      -- Last message (terminal @Assistant line 13) should remain open
      assert.are.equal(-1, vim.fn.foldclosed(13), "Last message should remain open")
    end)

    it("is a no-op when the turn has only two messages", function()
      local bufnr = setup_buffer({
        "@You:", -- 1
        "Hello!", -- 2
        "@Assistant:", -- 3
        "Hi there!", -- 4
      })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      folding.fold_turn_at_cursor(bufnr)

      -- Both messages should remain open (nothing intermediate to fold)
      assert.are.equal(-1, vim.fn.foldclosed(1), "First message should remain open")
      assert.are.equal(-1, vim.fn.foldclosed(3), "Last message should remain open")
    end)

    it("closes inner folds before closing intermediate messages", function()
      local bufnr = setup_buffer({
        "@You:", -- 1
        "question", -- 2
        "@Assistant:", -- 3
        "<thinking>", -- 4
        "reasoning here", -- 5
        "</thinking>", -- 6
        "**Tool Use:** `bash` (`tool_1`)", -- 7
        "```json", -- 8
        '{"command": "ls"}', -- 9
        "```", -- 10
        "@You:", -- 11
        "**Tool Result:** `tool_1`", -- 12
        "```", -- 13
        "output", -- 14
        "```", -- 15
        "@Assistant:", -- 16
        "Here is the result.", -- 17
      })

      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      folding.fold_turn_at_cursor(bufnr)

      -- Intermediate message at line 3 should be folded
      assert.are.equal(3, vim.fn.foldclosed(3), "Intermediate assistant should be folded")
      -- When we reopen the intermediate message, inner thinking should still be folded
      vim.cmd("3 foldopen")
      assert.are.equal(4, vim.fn.foldclosed(4), "Thinking should remain folded after message reopen")
    end)

    it("keeps last available message open in incomplete turn", function()
      local bufnr = setup_buffer({
        "@You:", -- 1
        "Do something", -- 2
        "@Assistant:", -- 3
        "**Tool Use:** `bash` (`tool_1`)", -- 4
        "```json", -- 5
        '{"command": "echo hi"}', -- 6
        "```", -- 7
        "@You:", -- 8
        "**Tool Result:** `tool_1`", -- 9
        "```", -- 10
        "hi", -- 11
        "```", -- 12
        "@Assistant:", -- 13
        "**Tool Use:** `bash` (`tool_2`)", -- 14
        "```json", -- 15
        '{"command": "echo bye"}', -- 16
        "```", -- 17
      })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      folding.fold_turn_at_cursor(bufnr)

      -- First message should stay open
      assert.are.equal(-1, vim.fn.foldclosed(1), "First message should remain open")
      -- Intermediate messages folded
      assert.are.equal(3, vim.fn.foldclosed(3), "First intermediate should be folded")
      assert.are.equal(8, vim.fn.foldclosed(8), "Second intermediate should be folded")
      -- Last available message (even though turn is incomplete) stays open
      assert.are.equal(-1, vim.fn.foldclosed(13), "Last available message should remain open")
    end)

    it("is a no-op when cursor is outside any turn", function()
      local bufnr = setup_buffer({
        "@System:", -- 1
        "You are helpful.", -- 2
        "@You:", -- 3
        "Hello!", -- 4
      })

      -- Cursor on system message (not part of any turn)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      folding.fold_turn_at_cursor(bufnr)

      -- Nothing should be folded
      assert.are.equal(-1, vim.fn.foldclosed(1), "System message should remain open")
      assert.are.equal(-1, vim.fn.foldclosed(3), "You message should remain open")
    end)
  end)

  describe("fold_all_turns", function()
    it("folds intermediate messages in all turns", function()
      local bufnr = setup_buffer({
        "@You:", -- 1: turn 1 first
        "first question", -- 2
        "@Assistant:", -- 3: turn 1 intermediate
        "**Tool Use:** `ls` (`tool_1`)", -- 4
        "```json", -- 5
        '{"path": "."}', -- 6
        "```", -- 7
        "@You:", -- 8: turn 1 intermediate
        "**Tool Result:** `tool_1`", -- 9
        "```", -- 10
        "files", -- 11
        "```", -- 12
        "@Assistant:", -- 13: turn 1 last
        "Found files.", -- 14
        "@You:", -- 15: turn 2 first
        "second question", -- 16
        "@Assistant:", -- 17: turn 2 intermediate
        "**Tool Use:** `bash` (`tool_2`)", -- 18
        "```json", -- 19
        '{"command": "pwd"}', -- 20
        "```", -- 21
        "@You:", -- 22: turn 2 intermediate
        "**Tool Result:** `tool_2`", -- 23
        "```", -- 24
        "/home", -- 25
        "```", -- 26
        "@Assistant:", -- 27: turn 2 last
        "You are in /home.", -- 28
      })

      folding.fold_all_turns(bufnr)

      -- Turn 1: first and last open, intermediates folded
      assert.are.equal(-1, vim.fn.foldclosed(1), "Turn 1 first message open")
      assert.are.equal(3, vim.fn.foldclosed(3), "Turn 1 intermediate assistant folded")
      assert.are.equal(8, vim.fn.foldclosed(8), "Turn 1 intermediate tool result folded")
      assert.are.equal(-1, vim.fn.foldclosed(13), "Turn 1 last message open")

      -- Turn 2: first and last open, intermediates folded
      assert.are.equal(-1, vim.fn.foldclosed(15), "Turn 2 first message open")
      assert.are.equal(17, vim.fn.foldclosed(17), "Turn 2 intermediate assistant folded")
      assert.are.equal(22, vim.fn.foldclosed(22), "Turn 2 intermediate tool result folded")
      assert.are.equal(-1, vim.fn.foldclosed(27), "Turn 2 last message open")
    end)

    it("also folds frontmatter", function()
      local bufnr = setup_buffer({
        "```toml", -- 1: frontmatter
        'provider = "anthropic"', -- 2
        "```", -- 3
        "@You:", -- 4
        "Hello!", -- 5
        "@Assistant:", -- 6
        "Hi!", -- 7
      })

      folding.fold_all_turns(bufnr)

      -- Frontmatter should be folded
      assert.are.equal(1, vim.fn.foldclosed(1), "Frontmatter should be folded")
      -- Simple turn (2 messages) — nothing intermediate to fold
      assert.are.equal(-1, vim.fn.foldclosed(4), "You message should remain open")
      assert.are.equal(-1, vim.fn.foldclosed(6), "Assistant message should remain open")
    end)

    it("folds frontmatter even when no turns have intermediate messages", function()
      local bufnr = setup_buffer({
        "```toml", -- 1
        'provider = "openai"', -- 2
        "```", -- 3
        "@You:", -- 4
        "Hi", -- 5
        "@Assistant:", -- 6
        "Hey", -- 7
      })

      folding.fold_all_turns(bufnr)

      assert.are.equal(1, vim.fn.foldclosed(1), "Frontmatter should be folded")
    end)

    it("folds system messages", function()
      local bufnr = setup_buffer({
        "@System:", -- 1
        "You are a helpful assistant.", -- 2
        "@You:", -- 3
        "Hello!", -- 4
        "@Assistant:", -- 5
        "Hi!", -- 6
      })

      folding.fold_all_turns(bufnr)

      assert.are.equal(1, vim.fn.foldclosed(1), "System message should be folded")
      -- Turn messages (first/last) stay open
      assert.are.equal(-1, vim.fn.foldclosed(3), "You message should remain open")
      assert.are.equal(-1, vim.fn.foldclosed(5), "Assistant message should remain open")
    end)

    it("folds multiple system messages", function()
      local bufnr = setup_buffer({
        "@System:", -- 1
        "You are a helpful assistant.", -- 2
        "@System:", -- 3
        "Additional instructions.", -- 4
        "@You:", -- 5
        "Hello!", -- 6
        "@Assistant:", -- 7
        "Hi!", -- 8
      })

      folding.fold_all_turns(bufnr)

      assert.are.equal(1, vim.fn.foldclosed(1), "First system message should be folded")
      assert.are.equal(3, vim.fn.foldclosed(3), "Second system message should be folded")
    end)
  end)

  describe("job-delivery messages", function()
    it("folds a leading @You that contains only job results", function()
      local bufnr = setup_buffer({
        "@You:", -- 1: previous turn's question (turn 1 first)
        "Check disk space", -- 2
        "@Assistant:", -- 3: turn 1 last (responds with background jobs)
        "Running in background.", -- 4
        "@You:", -- 5: turn 2 — auto-delivered job results (should fold)
        "", -- 6
        "**Job Result:** `job_abc123`", -- 7
        "", -- 8
        "```", -- 9
        "output here", -- 10
        "```", -- 11
        "", -- 12
        "@Assistant:", -- 13: turn 2 last
        "Here are your results.", -- 14
      })

      vim.api.nvim_win_set_cursor(0, { 5, 0 })
      folding.fold_turn_at_cursor(bufnr)

      -- The job-delivery @You (line 5) should be folded even though it's "first"
      assert.are.equal(5, vim.fn.foldclosed(5), "Job-delivery @You should be folded")
      -- The terminal @Assistant stays open
      assert.are.equal(-1, vim.fn.foldclosed(13), "Terminal assistant should remain open")
    end)

    it("does not fold a leading @You that has real user text alongside job results", function()
      local bufnr = setup_buffer({
        "@You:", -- 1: has job result AND user text
        "", -- 2
        "**Job Result:** `job_abc123`", -- 3
        "", -- 4
        "```", -- 5
        "output", -- 6
        "```", -- 7
        "", -- 8
        "Now please analyze this output.", -- 9
        "@Assistant:", -- 10: intermediate (tool use)
        "**Tool Use:** `bash` (`tool_1`)", -- 11
        "```json", -- 12
        '{"command": "echo done"}', -- 13
        "```", -- 14
        "@You:", -- 15: intermediate (tool result)
        "**Tool Result:** `tool_1`", -- 16
        "```", -- 17
        "done", -- 18
        "```", -- 19
        "@Assistant:", -- 20: last
        "Analysis complete.", -- 21
      })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      folding.fold_turn_at_cursor(bufnr)

      -- First message has real user content — should NOT be folded
      assert.are.equal(-1, vim.fn.foldclosed(1), "First message with user text should remain open")
      -- Intermediates should fold
      assert.are.equal(10, vim.fn.foldclosed(10), "Intermediate assistant should be folded")
      assert.are.equal(15, vim.fn.foldclosed(15), "Intermediate tool result should be folded")
      -- Last stays open
      assert.are.equal(-1, vim.fn.foldclosed(20), "Last message should remain open")
    end)
  end)

  describe("interaction with zM", function()
    it("opens first/last messages after zM", function()
      local bufnr = setup_buffer({
        "@You:", -- 1
        "What files?", -- 2
        "@Assistant:", -- 3
        "**Tool Use:** `ls` (`tool_1`)", -- 4
        "```json", -- 5
        '{"path": "."}', -- 6
        "```", -- 7
        "@You:", -- 8
        "**Tool Result:** `tool_1`", -- 9
        "```", -- 10
        "files", -- 11
        "```", -- 12
        "@Assistant:", -- 13
        "Found files.", -- 14
      })

      -- Close everything
      vim.cmd("normal! zM")
      assert.are_not.equal(-1, vim.fn.foldclosed(1), "Sanity: zM closed first message")
      assert.are_not.equal(-1, vim.fn.foldclosed(13), "Sanity: zM closed last message")

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      folding.fold_turn_at_cursor(bufnr)

      -- First and last should be opened
      assert.are.equal(-1, vim.fn.foldclosed(1), "First message should be open after zy")
      assert.are.equal(-1, vim.fn.foldclosed(13), "Last message should be open after zy")
      -- Intermediates stay closed
      assert.are_not.equal(-1, vim.fn.foldclosed(3), "Intermediate should be closed")
    end)

    it("fold_all_turns opens first/last after zM", function()
      local bufnr = setup_buffer({
        "@You:", -- 1
        "question", -- 2
        "@Assistant:", -- 3
        "**Tool Use:** `bash` (`tool_1`)", -- 4
        "```json", -- 5
        '{"command": "ls"}', -- 6
        "```", -- 7
        "@You:", -- 8
        "**Tool Result:** `tool_1`", -- 9
        "```", -- 10
        "output", -- 11
        "```", -- 12
        "@Assistant:", -- 13
        "Done.", -- 14
      })

      vim.cmd("normal! zM")
      folding.fold_all_turns(bufnr)

      assert.are.equal(-1, vim.fn.foldclosed(1), "First message should be open after zY")
      assert.are.equal(-1, vim.fn.foldclosed(13), "Last message should be open after zY")
      assert.are_not.equal(-1, vim.fn.foldclosed(3), "Intermediate should be closed")
    end)
  end)

  describe("inner folds in visible messages", function()
    it("closes thinking blocks in the last visible message", function()
      local bufnr = setup_buffer({
        "@You:", -- 1
        "question", -- 2
        "@Assistant:", -- 3
        "**Tool Use:** `bash` (`tool_1`)", -- 4
        "```json", -- 5
        '{"command": "ls"}', -- 6
        "```", -- 7
        "@You:", -- 8
        "**Tool Result:** `tool_1`", -- 9
        "```", -- 10
        "output", -- 11
        "```", -- 12
        "@Assistant:", -- 13
        "<thinking>", -- 14
        "reasoning about the output", -- 15
        "</thinking>", -- 16
        "Here are the results.", -- 17
      })

      -- Sanity: thinking is open before fold
      assert.are.equal(-1, vim.fn.foldclosed(14), "Sanity: thinking should be open initially")

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      folding.fold_turn_at_cursor(bufnr)

      -- Last message stays open but its thinking block is folded
      assert.are.equal(-1, vim.fn.foldclosed(13), "Last message should be open")
      assert.are.equal(14, vim.fn.foldclosed(14), "Thinking in last message should be folded")
    end)

    it("fold_all_turns closes thinking in last message of every turn", function()
      local bufnr = setup_buffer({
        "@You:", -- 1
        "question", -- 2
        "@Assistant:", -- 3
        "<thinking>", -- 4
        "deep thoughts", -- 5
        "</thinking>", -- 6
        "The answer is 42.", -- 7
      })

      folding.fold_all_turns(bufnr)

      -- Simple turn (2 messages, no intermediates) — but thinking should still be folded
      assert.are.equal(-1, vim.fn.foldclosed(3), "Assistant message should be open")
      assert.are.equal(4, vim.fn.foldclosed(4), "Thinking in last message should be folded")
    end)
  end)
end)
