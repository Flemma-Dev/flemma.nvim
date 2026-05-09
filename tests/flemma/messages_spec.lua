--- Tests for the messages template system

package.loaded["flemma.messages"] = nil

describe("flemma.messages", function()
  local messages

  before_each(function()
    package.loaded["flemma.messages"] = nil
    messages = require("flemma.messages")
  end)

  describe("render", function()
    it("renders job-executing--tracked template with variables", function()
      local result = messages.render("job-executing--tracked", { job_id = "job_test1" })
      assert.is_string(result)
      assert.truthy(result:match("job_test1"))
      assert.truthy(result:match("flemma:jobs:status"))
      assert.truthy(result:match("Do not retry"))
    end)

    it("renders job-executing--untracked template without job_id", function()
      local result = messages.render("job-executing--untracked")
      assert.is_string(result)
      assert.truthy(result:match("Do not retry"))
      assert.is_falsy(result:match("flemma:jobs:status"))
      assert.is_falsy(result:match("job_id"))
    end)

    it("errors for non-existent template", function()
      assert.has_error(function()
        messages.render("nonexistent_template")
      end, nil)
    end)

    it("uses the templating engine for expression evaluation", function()
      local result = messages.render("job-executing--tracked", { job_id = "job_expr" })
      assert.is_string(result)
      assert.truthy(result:match("job_expr"))
      assert.is_falsy(result:match("{{"))
    end)

    it("substitutes different job_ids correctly", function()
      local result_a = messages.render("job-executing--tracked", { job_id = "job_aaa" })
      local result_b = messages.render("job-executing--tracked", { job_id = "job_bbb" })
      assert.truthy(result_a:match("job_aaa"))
      assert.is_falsy(result_a:match("job_bbb"))
      assert.truthy(result_b:match("job_bbb"))
      assert.is_falsy(result_b:match("job_aaa"))
    end)
  end)
end)
