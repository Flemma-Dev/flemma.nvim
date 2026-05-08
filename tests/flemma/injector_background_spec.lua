describe("injector background extensions", function()
  local injector

  before_each(function()
    package.loaded["flemma.tools.injector"] = nil
    package.loaded["flemma.parser"] = nil
    injector = require("flemma.tools.injector")
  end)

  describe("set_header_modeline", function()
    it("writes KV modeline to tool_result header", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "**Tool Use:** `bash` (`tool_01`)",
        "",
        "```json",
        '{"command": "ls"}',
        "```",
        "",
        "@You:",
        "**Tool Result:** `tool_01`",
        "",
        "```",
        "```",
      })
      vim.bo[bufnr].filetype = "chat"

      local ok, err = injector.set_header_modeline(bufnr, "tool_01", "job=job_k7x2m")
      assert.is_true(ok, err)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local header = lines[9]
      assert.equals("**Tool Result:** `tool_01` (job=job_k7x2m)", header)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("append_job_result", function()
    it("Case 1: appends into empty trailing @You block", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "Done.",
        "",
        "@You:",
        "",
      })
      vim.bo[bufnr].filetype = "chat"

      injector.append_job_result(bufnr, "job_k7x2m", {
        success = true,
        output = "47 passed, 0 failed",
      })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local joined = table.concat(lines, "\n")
      assert.truthy(joined:match("%*%*Job Result:%*%*%s*`job_k7x2m`"))
      assert.truthy(joined:match("47 passed, 0 failed"))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("Case 2: creates @You block when buffer ends with @Assistant", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "Done.",
      })
      vim.bo[bufnr].filetype = "chat"

      injector.append_job_result(bufnr, "job_abc99", {
        success = true,
        output = "result here",
      })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local joined = table.concat(lines, "\n")
      assert.truthy(joined:match("@You:"))
      assert.truthy(joined:match("%*%*Job Result:%*%*%s*`job_abc99`"))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("Case 3: inserts before user's in-progress @You block", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "Done.",
        "",
        "@You:",
        "I'm typing something here",
      })
      vim.bo[bufnr].filetype = "chat"

      injector.append_job_result(bufnr, "job_xyz42", {
        success = true,
        output = "bg result",
      })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local joined = table.concat(lines, "\n")
      local job_pos = joined:find("Job Result")
      local user_pos = joined:find("I'm typing something here")
      assert.truthy(job_pos)
      assert.truthy(user_pos)
      assert.truthy(job_pos < user_pos)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("Case 3: blank line between @You: and job result header", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "Done.",
        "",
        "@You:",
        "I'm typing something here",
      })
      vim.bo[bufnr].filetype = "chat"

      injector.append_job_result(bufnr, "job_ws01", {
        success = true,
        output = "bg result",
      })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local header_idx
      for i, line in ipairs(lines) do
        if line:match("^%*%*Job Result:%*%*") then
          header_idx = i
          break
        end
      end
      assert.truthy(header_idx, "Job result header should exist")
      assert.equals("", lines[header_idx - 1], "Blank line before job result header")
      assert.equals("@You:", lines[header_idx - 2], "@You: marker before blank line")
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("Case 1: blank line between consecutive job results", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "Done.",
        "",
        "@You:",
        "",
      })
      vim.bo[bufnr].filetype = "chat"

      injector.append_job_result(bufnr, "job_ws02a", {
        success = true,
        output = "first output",
      })
      injector.append_job_result(bufnr, "job_ws02b", {
        success = true,
        output = "second output",
      })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local count = 0
      local second_header_idx
      for i, line in ipairs(lines) do
        if line:match("^%*%*Job Result:%*%*") then
          count = count + 1
          if count == 2 then
            second_header_idx = i
            break
          end
        end
      end
      assert.truthy(second_header_idx, "Second job result header should exist")
      assert.equals("", lines[second_header_idx - 1], "Blank line between consecutive job results")
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("Case 3: merges into existing job-result-only @You above user typing", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "Done.",
        "",
        "@You:",
        "I'm typing something here",
      })
      vim.bo[bufnr].filetype = "chat"

      injector.append_job_result(bufnr, "job_ws03a", {
        success = true,
        output = "first output",
      })
      injector.append_job_result(bufnr, "job_ws03b", {
        success = true,
        output = "second output",
      })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local you_count = 0
      for _, line in ipairs(lines) do
        if line == "@You:" then
          you_count = you_count + 1
        end
      end
      assert.equals(2, you_count, "Exactly 2 @You: blocks (jobs + user typing), not 3")

      local joined = table.concat(lines, "\n")
      local first_pos = joined:find("job_ws03a")
      local second_pos = joined:find("job_ws03b")
      local user_pos = joined:find("I'm typing something here")
      assert.truthy(first_pos < user_pos, "First job before user text")
      assert.truthy(second_pos < user_pos, "Second job before user text")

      -- Exactly one blank line between consecutive job results
      local second_header_idx
      local count = 0
      for i, line in ipairs(lines) do
        if line:match("^%*%*Job Result:%*%*") then
          count = count + 1
          if count == 2 then
            second_header_idx = i
            break
          end
        end
      end
      assert.truthy(second_header_idx, "Second job result header should exist")
      assert.equals("", lines[second_header_idx - 1], "Single blank line between consecutive job results")

      -- Exactly one blank line before user's @You
      local user_you_idx
      for i = #lines, 1, -1 do
        if lines[i] == "@You:" then
          user_you_idx = i
          break
        end
      end
      assert.truthy(user_you_idx, "User's @You: should exist")
      assert.equals("", lines[user_you_idx - 1], "Blank line before user's @You:")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("Case 2: blank line between @You: and job result header", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "Done.",
      })
      vim.bo[bufnr].filetype = "chat"

      injector.append_job_result(bufnr, "job_ws04", {
        success = true,
        output = "result here",
      })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local header_idx
      for i, line in ipairs(lines) do
        if line:match("^%*%*Job Result:%*%*") then
          header_idx = i
          break
        end
      end
      assert.truthy(header_idx, "Job result header should exist")
      assert.equals("", lines[header_idx - 1], "Blank line before job result header")
      assert.equals("@You:", lines[header_idx - 2], "@You: marker before blank line")
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("writes (error) suffix for failed results", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "Done.",
        "",
        "@You:",
        "",
      })
      vim.bo[bufnr].filetype = "chat"

      injector.append_job_result(bufnr, "job_err01", {
        success = false,
        error = "Exit code 1",
      })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local joined = table.concat(lines, "\n")
      assert.truthy(joined:match("`job_err01` %(error%)"))
      assert.truthy(joined:match("Exit code 1"))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
