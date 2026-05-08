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

      local ok, err = injector.set_header_modeline(bufnr, "tool_01", "job=bg_k7x2m")
      assert.is_true(ok, err)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local header = lines[9]
      assert.equals("**Tool Result:** `tool_01` (job=bg_k7x2m)", header)
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

      injector.append_job_result(bufnr, "bg_k7x2m", {
        success = true,
        output = "47 passed, 0 failed",
      })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local joined = table.concat(lines, "\n")
      assert.truthy(joined:match("%*%*Job Result:%*%*%s*`bg_k7x2m`"))
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

      injector.append_job_result(bufnr, "bg_abc99", {
        success = true,
        output = "result here",
      })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local joined = table.concat(lines, "\n")
      assert.truthy(joined:match("@You:"))
      assert.truthy(joined:match("%*%*Job Result:%*%*%s*`bg_abc99`"))
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

      injector.append_job_result(bufnr, "bg_xyz42", {
        success = true,
        output = "bg result",
      })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local joined = table.concat(lines, "\n")
      local bg_pos = joined:find("Job Result")
      local user_pos = joined:find("I'm typing something here")
      assert.truthy(bg_pos)
      assert.truthy(user_pos)
      assert.truthy(bg_pos < user_pos)
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

      injector.append_job_result(bufnr, "bg_err01", {
        success = false,
        error = "Exit code 1",
      })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local joined = table.concat(lines, "\n")
      assert.truthy(joined:match("`bg_err01` %(error%)"))
      assert.truthy(joined:match("Exit code 1"))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
