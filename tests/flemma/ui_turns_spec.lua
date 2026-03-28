describe("UI Turns", function()
  local flemma
  local turns

  before_each(function()
    -- Invalidate caches to ensure clean setup
    package.loaded["flemma"] = nil
    package.loaded["flemma.ui"] = nil
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
    turns = require("flemma.ui.turns")

    flemma.setup({})

    -- Clean up any buffers created during previous tests
    vim.cmd("silent! %bdelete!")
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  ---Create a chat buffer with the given lines, run turns.update, and return bufnr + cache.
  ---@param lines string[]
  ---@return integer bufnr
  ---@return { map: table<integer, string>, ranges: table[] }|nil cache
  local function setup_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = "chat"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    turns.update(bufnr)
    return bufnr, turns._get_turn_cache(bufnr)
  end

  describe("turn detection", function()
    it("detects simple You/Assistant turn", function()
      local _, cache = setup_buffer({
        "@You:",
        "Hello!",
        "@Assistant:",
        "Hi there!",
      })

      assert.is_not_nil(cache)
      local map = cache.map
      -- Line 1: top of turn (the @You: marker)
      assert.are.equal("top", map[1])
      -- Line 2: middle
      assert.are.equal("middle", map[2])
      -- Line 3: middle
      assert.are.equal("middle", map[3])
      -- Line 4: bottom of turn (last line of @Assistant)
      assert.are.equal("bottom", map[4])

      -- Exactly one range
      assert.are.equal(1, #cache.ranges)
      assert.are.equal(1, cache.ranges[1].start_line)
      assert.are.equal(4, cache.ranges[1].end_line)
      assert.is_false(cache.ranges[1].streaming)
    end)

    it("detects turn with tool use cycle", function()
      local _, cache = setup_buffer({
        "@You:", -- 1
        "Do something", -- 2
        "@Assistant:", -- 3
        "**Tool Use:** `bash` (`tool_123`)", -- 4
        "```json", -- 5
        '{"command": "ls"}', -- 6
        "```", -- 7
        "@You:", -- 8
        "**Tool Result:** `tool_123`", -- 9
        "```", -- 10
        "file1.txt", -- 11
        "```", -- 12
        "@Assistant:", -- 13
        "Here are your files.", -- 14
      })

      assert.is_not_nil(cache)
      -- Single turn spanning all lines
      assert.are.equal(1, #cache.ranges)
      assert.are.equal(1, cache.ranges[1].start_line)
      assert.are.equal(14, cache.ranges[1].end_line)

      -- Boundary positions
      assert.are.equal("top", cache.map[1])
      assert.are.equal("bottom", cache.map[14])

      -- All interior lines are "middle"
      for lnum = 2, 13 do
        assert.are.equal("middle", cache.map[lnum], "expected middle at line " .. lnum)
      end
    end)

    it("detects two consecutive turns", function()
      local _, cache = setup_buffer({
        "@You:", -- 1
        "First question", -- 2
        "@Assistant:", -- 3
        "First answer", -- 4
        "@You:", -- 5
        "Second question", -- 6
        "@Assistant:", -- 7
        "Second answer", -- 8
      })

      assert.is_not_nil(cache)
      assert.are.equal(2, #cache.ranges)

      -- First turn: lines 1-4
      assert.are.equal(1, cache.ranges[1].start_line)
      assert.are.equal(4, cache.ranges[1].end_line)

      -- Second turn: lines 5-8
      assert.are.equal(5, cache.ranges[2].start_line)
      assert.are.equal(8, cache.ranges[2].end_line)

      -- Boundary check: first turn bottom, second turn top
      assert.are.equal("bottom", cache.map[4])
      assert.are.equal("top", cache.map[5])
    end)

    it("groups consecutive @You messages before @Assistant into one turn", function()
      local _, cache = setup_buffer({
        "@You:", -- 1
        "Part one", -- 2
        "@You:", -- 3
        "Part two", -- 4
        "@Assistant:", -- 5
        "Response", -- 6
      })

      assert.is_not_nil(cache)
      assert.are.equal(1, #cache.ranges)
      assert.are.equal(1, cache.ranges[1].start_line)
      assert.are.equal(6, cache.ranges[1].end_line)

      assert.are.equal("top", cache.map[1])
      assert.are.equal("bottom", cache.map[6])
    end)

    it("groups consecutive terminal @Assistant messages into one turn", function()
      local _, cache = setup_buffer({
        "@You:", -- 1
        "Question", -- 2
        "@Assistant:", -- 3
        "First part", -- 4
        "@Assistant:", -- 5
        "Second part", -- 6
      })

      assert.is_not_nil(cache)
      assert.are.equal(1, #cache.ranges)
      assert.are.equal(1, cache.ranges[1].start_line)
      assert.are.equal(6, cache.ranges[1].end_line)

      assert.are.equal("top", cache.map[1])
      assert.are.equal("bottom", cache.map[6])
    end)

    it("excludes @System messages from turns", function()
      local _, cache = setup_buffer({
        "@System:", -- 1
        "You are helpful.", -- 2
        "@You:", -- 3
        "Hello", -- 4
        "@Assistant:", -- 5
        "Hi", -- 6
      })

      assert.is_not_nil(cache)
      -- System lines should not appear in the turn map
      assert.is_nil(cache.map[1])
      assert.is_nil(cache.map[2])

      -- Turn covers only lines 3-6
      assert.are.equal(1, #cache.ranges)
      assert.are.equal(3, cache.ranges[1].start_line)
      assert.are.equal(6, cache.ranges[1].end_line)
      assert.are.equal("top", cache.map[3])
      assert.are.equal("bottom", cache.map[6])
    end)

    it("does not create a turn for trailing @You with no @Assistant", function()
      local _, cache = setup_buffer({
        "@You:", -- 1
        "Waiting for response", -- 2
      })

      assert.is_not_nil(cache)
      -- No complete turns exist (not streaming)
      assert.are.equal(0, #cache.ranges)
      -- No lines should be in the turn map
      assert.is_nil(cache.map[1])
      assert.is_nil(cache.map[2])
    end)

    it("creates incomplete turn for trailing tool-use cycle without final answer", function()
      local _, cache = setup_buffer({
        "@You:", -- 1
        "What is 2+2?", -- 2
        "@Assistant:", -- 3
        "**Tool Use:** `calculator` (`t1`)", -- 4
        "```json", -- 5
        '{"expression":"2+2"}', -- 6
        "```", -- 7
        "@You:", -- 8
        "**Tool Result:** `t1`", -- 9
        "```", -- 10
        "4", -- 11
        "```", -- 12
      })

      assert.is_not_nil(cache)
      -- Should detect an incomplete turn (not streaming — no active request)
      assert.are.equal(1, #cache.ranges)
      assert.is_true(cache.ranges[1].incomplete)
      assert.is_false(cache.ranges[1].streaming)
      assert.are.equal(1, cache.ranges[1].start_line)
      assert.are.equal(12, cache.ranges[1].end_line)

      -- Incomplete turns: ╭ at top, ┊ for interior, · at end
      assert.are.equal("top", cache.map[1])
      assert.are.equal("pending_end", cache.map[12])
      assert.are.equal("pending", cache.map[6])
    end)

    it("does not create a turn for orphan @Assistant with no preceding @You", function()
      local _, cache = setup_buffer({
        "@Assistant:", -- 1
        "I appeared from nowhere", -- 2
      })

      assert.is_not_nil(cache)
      assert.are.equal(0, #cache.ranges)
      assert.is_nil(cache.map[1])
      assert.is_nil(cache.map[2])
    end)

    it("returns empty turn map for empty buffer", function()
      local _, cache = setup_buffer({})

      assert.is_not_nil(cache)
      assert.are.equal(0, #cache.ranges)
      -- Map should have no entries
      local count = 0
      for _ in pairs(cache.map) do
        count = count + 1
      end
      assert.are.equal(0, count)
    end)

    it("assigns middle position to interior lines of multi-line messages", function()
      local _, cache = setup_buffer({
        "@You:", -- 1
        "Line A", -- 2
        "Line B", -- 3
        "Line C", -- 4
        "@Assistant:", -- 5
        "Reply line 1", -- 6
        "Reply line 2", -- 7
        "Reply line 3", -- 8
        "Reply line 4", -- 9
      })

      assert.is_not_nil(cache)
      assert.are.equal(1, #cache.ranges)

      -- Boundaries
      assert.are.equal("top", cache.map[1])
      assert.are.equal("bottom", cache.map[9])

      -- All interior lines are middle
      for lnum = 2, 8 do
        assert.are.equal("middle", cache.map[lnum], "expected middle at line " .. lnum)
      end
    end)

    it("handles @System between two turns", function()
      local _, cache = setup_buffer({
        "@You:", -- 1
        "First", -- 2
        "@Assistant:", -- 3
        "Reply", -- 4
        "@System:", -- 5
        "Injected context", -- 6
        "@You:", -- 7
        "Second", -- 8
        "@Assistant:", -- 9
        "Reply 2", -- 10
      })

      assert.is_not_nil(cache)
      assert.are.equal(2, #cache.ranges)

      -- First turn: 1-4
      assert.are.equal(1, cache.ranges[1].start_line)
      assert.are.equal(4, cache.ranges[1].end_line)

      -- System lines not in any turn
      assert.is_nil(cache.map[5])
      assert.is_nil(cache.map[6])

      -- Second turn: 7-10
      assert.are.equal(7, cache.ranges[2].start_line)
      assert.are.equal(10, cache.ranges[2].end_line)
    end)

    it("handles single-line turn (one-line @You + one-line @Assistant)", function()
      local _, cache = setup_buffer({
        "@You:", -- 1
        "@Assistant:", -- 2
      })

      assert.is_not_nil(cache)
      assert.are.equal(1, #cache.ranges)
      assert.are.equal(1, cache.ranges[1].start_line)
      assert.are.equal(2, cache.ranges[1].end_line)

      assert.are.equal("top", cache.map[1])
      assert.are.equal("bottom", cache.map[2])
    end)

    it("handles multiple tool use cycles in a single turn", function()
      local _, cache = setup_buffer({
        "@You:", -- 1
        "Do two things", -- 2
        "@Assistant:", -- 3
        "**Tool Use:** `read` (`t1`)", -- 4
        "```json", -- 5
        '{"path": "a.txt"}', -- 6
        "```", -- 7
        "@You:", -- 8
        "**Tool Result:** `t1`", -- 9
        "```", -- 10
        "content A", -- 11
        "```", -- 12
        "@Assistant:", -- 13
        "**Tool Use:** `read` (`t2`)", -- 14
        "```json", -- 15
        '{"path": "b.txt"}', -- 16
        "```", -- 17
        "@You:", -- 18
        "**Tool Result:** `t2`", -- 19
        "```", -- 20
        "content B", -- 21
        "```", -- 22
        "@Assistant:", -- 23
        "Here are both files.", -- 24
      })

      assert.is_not_nil(cache)
      -- All of this is one turn
      assert.are.equal(1, #cache.ranges)
      assert.are.equal(1, cache.ranges[1].start_line)
      assert.are.equal(24, cache.ranges[1].end_line)
    end)

    it("does not include orphan @Assistant before a valid turn", function()
      local _, cache = setup_buffer({
        "@Assistant:", -- 1
        "Orphan response", -- 2
        "@You:", -- 3
        "Real question", -- 4
        "@Assistant:", -- 5
        "Real answer", -- 6
      })

      assert.is_not_nil(cache)
      -- The orphan assistant (lines 1-2) should not be in any turn
      assert.is_nil(cache.map[1])
      assert.is_nil(cache.map[2])

      -- The valid turn should be lines 3-6
      assert.are.equal(1, #cache.ranges)
      assert.are.equal(3, cache.ranges[1].start_line)
      assert.are.equal(6, cache.ranges[1].end_line)
    end)

    it("marks last turn as streaming when buffer has active request", function()
      local state = require("flemma.state")
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:", -- 1
        "Hello!", -- 2
        "@Assistant:", -- 3
        "Hi there!", -- 4
      })

      -- Simulate active streaming request
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.current_request = 12345

      turns.update(bufnr)
      local cache = turns._get_turn_cache(bufnr)

      assert.is_not_nil(cache)
      assert.are.equal(1, #cache.ranges)
      assert.is_true(cache.ranges[1].streaming)

      -- Streaming turns: ╭ at top, ┊ for interior, ╯ at current end
      assert.are.equal("top", cache.map[1])
      assert.are.equal("pending", cache.map[2])
      assert.are.equal("pending", cache.map[3])
      assert.are.equal("pending_end", cache.map[4])

      -- streaming_start_line should be set
      assert.are.equal(1, buffer_state.streaming_start_line)

      -- Cleanup
      buffer_state.current_request = nil
    end)

    it("sets streaming_start_line for fallback rendering during streaming", function()
      local state = require("flemma.state")
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:", -- 1
        "Question", -- 2
      })

      -- Simulate active streaming (no @Assistant yet — trailing @You)
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.current_request = 12345

      turns.update(bufnr)
      local cache = turns._get_turn_cache(bufnr)

      assert.is_not_nil(cache)
      assert.are.equal(1, #cache.ranges)
      assert.is_true(cache.ranges[1].streaming)
      assert.are.equal(1, buffer_state.streaming_start_line)

      -- Cleanup
      buffer_state.current_request = nil
    end)

    it("clears streaming_start_line when request completes", function()
      local state = require("flemma.state")
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:", -- 1
        "Hello", -- 2
        "@Assistant:", -- 3
        "Hi", -- 4
      })

      -- No active request — completed turn
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.current_request = nil

      turns.update(bufnr)

      assert.is_nil(buffer_state.streaming_start_line)
    end)

    it("does not mark earlier turns as streaming when last turn is streaming", function()
      local state = require("flemma.state")
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:", -- 1
        "First", -- 2
        "@Assistant:", -- 3
        "Reply", -- 4
        "@You:", -- 5
        "Second", -- 6
        "@Assistant:", -- 7
        "Streaming...", -- 8
      })

      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.current_request = 12345

      turns.update(bufnr)
      local cache = turns._get_turn_cache(bufnr)

      assert.is_not_nil(cache)
      assert.are.equal(2, #cache.ranges)

      -- First turn: complete (not streaming)
      assert.is_false(cache.ranges[1].streaming)
      assert.are.equal("top", cache.map[1])
      assert.are.equal("bottom", cache.map[4])

      -- Second turn: streaming (╭ at top, ╯ at current end)
      assert.is_true(cache.ranges[2].streaming)
      assert.are.equal("top", cache.map[5])
      assert.are.equal("pending_end", cache.map[8])

      -- Cleanup
      buffer_state.current_request = nil
    end)

    it("uses pending positions for incomplete turn interior lines", function()
      local _, cache = setup_buffer({
        "@You:", -- 1
        "Question", -- 2
        "@Assistant:", -- 3
        "**Tool Use:** `bash` (`t1`)", -- 4
        "```json", -- 5
        '{"command":"ls"}', -- 6
        "```", -- 7
        "@You:", -- 8
        "**Tool Result:** `t1`", -- 9
        "```", -- 10
        "files", -- 11
        "```", -- 12
        "@You:", -- 13
        "", -- 14
      })

      assert.is_not_nil(cache)
      assert.are.equal(1, #cache.ranges)
      assert.is_true(cache.ranges[1].incomplete)

      -- Top gets ╭, all interior get ┊, last gets ·
      assert.are.equal("top", cache.map[1])
      for lnum = 2, 13 do
        assert.are.equal("pending", cache.map[lnum], "expected pending at line " .. lnum)
      end
      assert.are.equal("pending_end", cache.map[14])
    end)
  end)

  describe("changedtick caching", function()
    it("reuses cached turn map when buffer has not changed", function()
      local bufnr, cache1 = setup_buffer({
        "@You:",
        "Hello",
        "@Assistant:",
        "Hi",
      })

      -- Call update again without changing the buffer
      turns.update(bufnr)
      local cache2 = turns._get_turn_cache(bufnr)

      -- Should be the exact same table reference (cache hit)
      assert.are.equal(cache1, cache2)
    end)

    it("recomputes turn map after buffer modification", function()
      local bufnr, cache1 = setup_buffer({
        "@You:",
        "Hello",
        "@Assistant:",
        "Hi",
      })

      -- Modify the buffer
      vim.api.nvim_buf_set_lines(bufnr, 4, 4, false, {
        "@You:",
        "Another question",
        "@Assistant:",
        "Another answer",
      })

      turns.update(bufnr)
      local cache2 = turns._get_turn_cache(bufnr)

      -- Should be a different cache entry (recomputed)
      assert.are_not.equal(cache1, cache2)
      -- Now two turns
      assert.are.equal(2, #cache2.ranges)
    end)
  end)

  describe("cleanup", function()
    it("removes turn cache for a buffer", function()
      local bufnr, cache = setup_buffer({
        "@You:",
        "Hello",
        "@Assistant:",
        "Hi",
      })

      assert.is_not_nil(cache)

      turns.cleanup(bufnr)
      assert.is_nil(turns._get_turn_cache(bufnr))
    end)
  end)

  describe("turns disabled", function()
    it("does not compute turn map when turns.enabled is false", function()
      -- Re-setup with turns disabled
      package.loaded["flemma"] = nil
      package.loaded["flemma.ui.turns"] = nil
      package.loaded["flemma.config"] = nil
      package.loaded["flemma.state"] = nil
      package.loaded["flemma.parser"] = nil
      package.loaded["flemma.ast"] = nil
      package.loaded["flemma.ast.nodes"] = nil
      package.loaded["flemma.tools"] = nil
      package.loaded["flemma.tools.context"] = nil
      package.loaded["flemma.tools.injector"] = nil

      flemma = require("flemma")
      turns = require("flemma.ui.turns")
      flemma.setup({ turns = { enabled = false } })

      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "Hello",
        "@Assistant:",
        "Hi",
      })

      turns.update(bufnr)
      assert.is_nil(turns._get_turn_cache(bufnr))
    end)
  end)
end)
