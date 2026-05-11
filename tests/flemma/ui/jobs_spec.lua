package.loaded["flemma.hooks"] = nil
package.loaded["flemma.ui.jobs"] = nil
package.loaded["flemma.ui.bar"] = nil
package.loaded["flemma.ui.bar.layout"] = nil
package.loaded["flemma.ui.spinners"] = nil

local hooks = require("flemma.hooks")
local jobs = require("flemma.ui.jobs")
local spinners = require("flemma.ui.spinners")

---Create a visible scratch buffer suitable for bar rendering.
---@return integer bufnr
local function make_visible_buf()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "test" })
  vim.api.nvim_set_current_buf(bufnr)
  return bufnr
end

describe("flemma.ui.jobs", function()
  ---@type integer
  local bufnr

  before_each(function()
    package.loaded["flemma.hooks"] = nil
    package.loaded["flemma.ui.jobs"] = nil
    package.loaded["flemma.ui.bar"] = nil
    package.loaded["flemma.ui.bar.layout"] = nil
    hooks = require("flemma.hooks")
    jobs = require("flemma.ui.jobs")
    bufnr = make_visible_buf()
  end)

  after_each(function()
    jobs._reset()
    hooks._clear_subscribers()
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end)

  ---Helper: read the rendered text from any floating window on the test buffer.
  ---@return string|nil
  local function read_float_text()
    local wins = vim.api.nvim_list_wins()
    for _, win in ipairs(wins) do
      local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
      if ok and cfg.relative and cfg.relative ~= "" then
        local win_buf = vim.api.nvim_win_get_buf(win)
        if win_buf ~= bufnr then
          local lines = vim.api.nvim_buf_get_lines(win_buf, 0, -1, false)
          if lines[1] then
            return lines[1]
          end
        end
      end
    end
    return nil
  end

  ---Helper: count floating windows visible for the test buffer.
  ---@return integer
  local function count_floats()
    local count = 0
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
      if ok and cfg.relative and cfg.relative ~= "" then
        count = count + 1
      end
    end
    return count
  end

  describe("job:submitted", function()
    it("creates a bar when first job is submitted", function()
      assert.equals(0, count_floats())
      hooks.dispatch("job:submitted", {
        bufnr = bufnr,
        job_id = "job_abc",
        tool_id = "t1",
        tool_name = "bash",
        active_count = 1,
      })
      assert.truthy(count_floats() > 0)
    end)

    it("renders singular 'job' for count of 1", function()
      hooks.dispatch("job:submitted", {
        bufnr = bufnr,
        job_id = "job_abc",
        tool_id = "t1",
        tool_name = "bash",
        active_count = 1,
      })
      local text = read_float_text()
      assert.truthy(text)
      assert.truthy(text:match("1 job"), "expected '1 job' in: " .. text)
      assert.is_nil(text:match("1 jobs"))
    end)

    it("renders plural 'jobs' for count > 1", function()
      hooks.dispatch("job:submitted", {
        bufnr = bufnr,
        job_id = "job_abc",
        tool_id = "t1",
        tool_name = "bash",
        active_count = 3,
      })
      local text = read_float_text()
      assert.truthy(text)
      assert.truthy(text:match("3 jobs"), "expected '3 jobs' in: " .. text)
    end)

    it("updates count on subsequent submissions", function()
      hooks.dispatch("job:submitted", {
        bufnr = bufnr,
        job_id = "job_a",
        tool_id = "t1",
        tool_name = "bash",
        active_count = 1,
      })
      local text1 = read_float_text()
      assert.truthy(text1:match("1 job"))

      hooks.dispatch("job:submitted", {
        bufnr = bufnr,
        job_id = "job_b",
        tool_id = "t2",
        tool_name = "grep",
        active_count = 2,
      })
      local text2 = read_float_text()
      assert.truthy(text2:match("2 jobs"))
    end)
  end)

  describe("job:completed", function()
    it("updates count when a job completes", function()
      hooks.dispatch("job:submitted", {
        bufnr = bufnr,
        job_id = "job_a",
        tool_id = "t1",
        tool_name = "bash",
        active_count = 2,
      })

      hooks.dispatch("job:completed", {
        bufnr = bufnr,
        job_id = "job_a",
        tool_id = "t1",
        tool_name = "bash",
        success = true,
        active_count = 1,
      })
      local text = read_float_text()
      assert.truthy(text:match("1 job"))
    end)

    it("dismisses bar immediately when count reaches zero", function()
      hooks.dispatch("job:submitted", {
        bufnr = bufnr,
        job_id = "job_a",
        tool_id = "t1",
        tool_name = "bash",
        active_count = 1,
      })
      assert.truthy(count_floats() > 0)

      hooks.dispatch("job:completed", {
        bufnr = bufnr,
        job_id = "job_a",
        tool_id = "t1",
        tool_name = "bash",
        success = true,
        active_count = 0,
      })
      assert.equals(0, count_floats())
    end)

    it("clears spinner icon when count reaches zero", function()
      hooks.dispatch("job:submitted", {
        bufnr = bufnr,
        job_id = "job_a",
        tool_id = "t1",
        tool_name = "bash",
        active_count = 1,
      })

      -- Verify spinner icon is present while jobs active
      local text_with_spinner = read_float_text()
      assert.truthy(text_with_spinner)
      local first_char = vim.fn.strcharpart(text_with_spinner:gsub("^%s+", ""), 0, 1)
      local has_spinner = false
      for _, frame in ipairs(spinners.FRAMES.tool) do
        if first_char == frame then
          has_spinner = true
          break
        end
      end
      assert.is_true(has_spinner, "expected spinner icon, got: " .. first_char)

      -- Complete the job
      hooks.dispatch("job:completed", {
        bufnr = bufnr,
        job_id = "job_a",
        tool_id = "t1",
        tool_name = "bash",
        success = true,
        active_count = 0,
      })

      -- The bar text should NOT contain a spinner frame
      local text_after = read_float_text()
      if text_after then
        local trimmed = text_after:gsub("^%s+", ""):gsub("%s+$", "")
        assert.equals("", trimmed, "expected empty bar text after all jobs complete, got: " .. trimmed)
      end
    end)
  end)

  describe("autopilot:resume-scheduled", function()
    it("shows 'Resuming…' in bar segments", function()
      hooks.dispatch("job:submitted", {
        bufnr = bufnr,
        job_id = "job_a",
        tool_id = "t1",
        tool_name = "bash",
        active_count = 1,
      })

      hooks.dispatch("job:completed", {
        bufnr = bufnr,
        job_id = "job_a",
        tool_id = "t1",
        tool_name = "bash",
        success = true,
        active_count = 0,
      })

      hooks.dispatch("autopilot:resume-scheduled", { bufnr = bufnr, delay_ms = 2000 })

      local text = read_float_text()
      assert.truthy(text)
      assert.truthy(text:match("Resuming…"), "expected 'Resuming…' in: " .. text)
    end)

    it("includes countdown frame and remaining seconds with middle dot", function()
      hooks.dispatch("autopilot:resume-scheduled", { bufnr = bufnr, delay_ms = 2000 })
      local text = read_float_text()
      assert.truthy(text)
      local first_countdown = spinners.FRAMES.countdown[1]
      assert.truthy(text:match(first_countdown), "expected countdown frame '" .. first_countdown .. "' in: " .. text)
      assert.truthy(text:match("·"), "expected middle dot in: " .. text)
      assert.truthy(text:match("%d%.%ds"), "expected X.Xs remaining seconds in: " .. text)
    end)
  end)

  describe("autopilot:resume-cancelled", function()
    it("removes countdown from bar", function()
      hooks.dispatch("autopilot:resume-scheduled", { bufnr = bufnr, delay_ms = 2000 })
      local text_before = read_float_text()
      assert.truthy(text_before:match("Resuming…"))

      hooks.dispatch("autopilot:resume-cancelled", { bufnr = bufnr })

      -- Bar should now have no resume text (and since no jobs, it should be
      -- empty or scheduled for dismissal)
      local text_after = read_float_text()
      if text_after then
        assert.is_nil(text_after:match("Resuming…"))
      end
    end)
  end)

  describe("autopilot:resumed", function()
    it("clears countdown state", function()
      hooks.dispatch("autopilot:resume-scheduled", { bufnr = bufnr, delay_ms = 2000 })
      assert.truthy(read_float_text():match("Resuming…"))

      hooks.dispatch("autopilot:resumed", { bufnr = bufnr })

      local text_after = read_float_text()
      if text_after then
        assert.is_nil(text_after:match("Resuming…"))
      end
    end)
  end)

  describe("combined jobs + resume", function()
    it("shows both job count and countdown", function()
      hooks.dispatch("job:submitted", {
        bufnr = bufnr,
        job_id = "job_a",
        tool_id = "t1",
        tool_name = "bash",
        active_count = 1,
      })
      hooks.dispatch("autopilot:resume-scheduled", { bufnr = bufnr, delay_ms = 2000 })

      local text = read_float_text()
      assert.truthy(text)
      assert.truthy(text:match("1 job"), "expected '1 job' in: " .. text)
      assert.truthy(text:match("Resuming…"), "expected 'Resuming…' in: " .. text)
    end)

    it("renders resume countdown before job count", function()
      hooks.dispatch("job:submitted", {
        bufnr = bufnr,
        job_id = "job_a",
        tool_id = "t1",
        tool_name = "bash",
        active_count = 1,
      })
      hooks.dispatch("autopilot:resume-scheduled", { bufnr = bufnr, delay_ms = 2000 })

      local text = read_float_text()
      assert.truthy(text)
      local resume_pos = text:find("Resuming…")
      local job_pos = text:find("1 job")
      assert.truthy(resume_pos, "expected 'Resuming…' in: " .. text)
      assert.truthy(job_pos, "expected '1 job' in: " .. text)
      assert.truthy(resume_pos < job_pos, "expected resume before jobs in: " .. text)

      local trimmed = text:gsub("^%s+", "")
      local first_char = vim.fn.strcharpart(trimmed, 0, 1)
      local is_countdown = false
      for _, frame in ipairs(spinners.FRAMES.countdown) do
        if first_char == frame then
          is_countdown = true
          break
        end
      end
      assert.is_true(is_countdown, "expected countdown frame as leading character, got: " .. first_char)
    end)

    it("does not schedule hide while resume countdown is active", function()
      hooks.dispatch("autopilot:resume-scheduled", { bufnr = bufnr, delay_ms = 2000 })

      hooks.dispatch("job:submitted", {
        bufnr = bufnr,
        job_id = "job_a",
        tool_id = "t1",
        tool_name = "bash",
        active_count = 1,
      })
      hooks.dispatch("job:completed", {
        bufnr = bufnr,
        job_id = "job_a",
        tool_id = "t1",
        tool_name = "bash",
        success = true,
        active_count = 0,
      })

      -- Bar should still be visible because resume countdown is active
      local text = read_float_text()
      assert.truthy(text)
      assert.truthy(text:match("Resuming…"))
    end)
  end)

  describe("cleanup", function()
    it("dismisses bar and clears state", function()
      hooks.dispatch("job:submitted", {
        bufnr = bufnr,
        job_id = "job_a",
        tool_id = "t1",
        tool_name = "bash",
        active_count = 1,
      })
      assert.truthy(count_floats() > 0)

      jobs.cleanup(bufnr)
      assert.equals(0, count_floats())
    end)

    it("is safe to call on buffer with no state", function()
      assert.has_no.errors(function()
        jobs.cleanup(999999)
      end)
    end)
  end)

  describe("_reset", function()
    it("cleans up all buffer states", function()
      hooks.dispatch("job:submitted", {
        bufnr = bufnr,
        job_id = "job_a",
        tool_id = "t1",
        tool_name = "bash",
        active_count = 1,
      })
      assert.truthy(count_floats() > 0)

      jobs._reset()
      assert.equals(0, count_floats())
    end)
  end)
end)
