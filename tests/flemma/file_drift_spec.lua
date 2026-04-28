describe("file drift detection", function()
  local processor, parser, context_util
  local runner_mod, file_refs_mod

  before_each(function()
    package.loaded["flemma.processor"] = nil
    package.loaded["flemma.parser"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.context"] = nil
    package.loaded["flemma.preprocessor"] = nil
    package.loaded["flemma.preprocessor.registry"] = nil
    package.loaded["flemma.preprocessor.runner"] = nil
    package.loaded["flemma.preprocessor.context"] = nil
    package.loaded["flemma.utilities.encoding"] = nil
    package.loaded["flemma.preprocessor.rewriters.file_references"] = nil
    processor = require("flemma.processor")
    parser = require("flemma.parser")
    context_util = require("flemma.context")
    runner_mod = require("flemma.preprocessor.runner")
    file_refs_mod = require("flemma.preprocessor.rewriters.file_references")
  end)

  --- Run file-references rewriter on a parsed document.
  ---@param doc flemma.ast.DocumentNode
  ---@return flemma.ast.DocumentNode
  local function run_file_refs(doc)
    return runner_mod.run_pipeline(doc, 0, {
      interactive = false,
      rewriters = { file_refs_mod.rewriter },
    })
  end

  --- Write content to a file, creating or overwriting it.
  ---@param path string
  ---@param content string
  local function write_file(path, content)
    local f = assert(io.open(path, "w"))
    f:write(content)
    f:close()
  end

  --- Find diagnostics of a specific type in an evaluated result.
  ---@param result flemma.processor.EvaluatedResult
  ---@param diagnostic_type string
  ---@return flemma.ast.Diagnostic[]
  local function find_diagnostics(result, diagnostic_type)
    return vim.tbl_filter(function(d)
      return d.type == diagnostic_type
    end, result.diagnostics or {})
  end

  it("emits no drift diagnostic on first evaluation", function()
    local temp_dir = vim.fn.tempname() .. "_file_drift_first"
    vim.fn.mkdir(temp_dir, "p")
    write_file(temp_dir .. "/code.js", "const x = 1;")

    local bufnr = vim.api.nvim_create_buf(false, true)
    local context = context_util.from_file(temp_dir .. "/test.chat")

    local lines = { "@You:", "Review @./code.js" }
    local doc = run_file_refs(parser.parse_lines(lines))
    local result = processor.evaluate(doc, context, { bufnr = bufnr })

    local drift_diags = find_diagnostics(result, "custom:file_drift")
    assert.equals(0, #drift_diags)

    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(temp_dir, "rf")
  end)

  it("emits drift diagnostic when file changes between evaluations", function()
    local temp_dir = vim.fn.tempname() .. "_file_drift_change"
    vim.fn.mkdir(temp_dir, "p")
    write_file(temp_dir .. "/code.js", "const x = 1;")

    local bufnr = vim.api.nvim_create_buf(false, true)
    local context = context_util.from_file(temp_dir .. "/test.chat")
    local lines = { "@You:", "Review @./code.js" }

    -- First evaluation: establishes baseline hash
    processor.evaluate(run_file_refs(parser.parse_lines(lines)), context, { bufnr = bufnr })

    -- Modify the file on disk
    write_file(temp_dir .. "/code.js", "const x = 2; // changed")

    -- Second evaluation: should detect drift
    local result = processor.evaluate(run_file_refs(parser.parse_lines(lines)), context, { bufnr = bufnr })
    local drift_diags = find_diagnostics(result, "custom:file_drift")

    assert.equals(1, #drift_diags)
    assert.equals("warning", drift_diags[1].severity)
    assert.is_true(drift_diags[1].error:match("code.js") ~= nil)
    assert.is_string(drift_diags[1].label, "diagnostic must carry a label for generic rendering")

    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(temp_dir, "rf")
  end)

  it("emits no drift diagnostic when file content is unchanged", function()
    local temp_dir = vim.fn.tempname() .. "_file_drift_same"
    vim.fn.mkdir(temp_dir, "p")
    write_file(temp_dir .. "/code.js", "const x = 1;")

    local bufnr = vim.api.nvim_create_buf(false, true)
    local context = context_util.from_file(temp_dir .. "/test.chat")
    local lines = { "@You:", "Review @./code.js" }

    -- First evaluation
    processor.evaluate(run_file_refs(parser.parse_lines(lines)), context, { bufnr = bufnr })

    -- Second evaluation without changing the file
    local result = processor.evaluate(run_file_refs(parser.parse_lines(lines)), context, { bufnr = bufnr })
    local drift_diags = find_diagnostics(result, "custom:file_drift")

    assert.equals(0, #drift_diags)

    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(temp_dir, "rf")
  end)

  it("updates stored hash after drift so subsequent unchanged evaluations are clean", function()
    local temp_dir = vim.fn.tempname() .. "_file_drift_update"
    vim.fn.mkdir(temp_dir, "p")
    write_file(temp_dir .. "/code.js", "version 1")

    local bufnr = vim.api.nvim_create_buf(false, true)
    local context = context_util.from_file(temp_dir .. "/test.chat")
    local lines = { "@You:", "Review @./code.js" }

    -- First evaluation: baseline
    processor.evaluate(run_file_refs(parser.parse_lines(lines)), context, { bufnr = bufnr })

    -- Modify file
    write_file(temp_dir .. "/code.js", "version 2")

    -- Second evaluation: drift detected
    local result2 = processor.evaluate(run_file_refs(parser.parse_lines(lines)), context, { bufnr = bufnr })
    assert.equals(1, #find_diagnostics(result2, "custom:file_drift"))

    -- Third evaluation without further changes: hash was updated, no drift
    local result3 = processor.evaluate(run_file_refs(parser.parse_lines(lines)), context, { bufnr = bufnr })
    assert.equals(0, #find_diagnostics(result3, "custom:file_drift"))

    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(temp_dir, "rf")
  end)

  it("tracks multiple files independently", function()
    local temp_dir = vim.fn.tempname() .. "_file_drift_multi"
    vim.fn.mkdir(temp_dir, "p")
    write_file(temp_dir .. "/a.js", "file a")
    write_file(temp_dir .. "/b.js", "file b")

    local bufnr = vim.api.nvim_create_buf(false, true)
    local context = context_util.from_file(temp_dir .. "/test.chat")
    local lines = { "@You:", "Review @./a.js and @./b.js" }

    -- First evaluation: baseline for both
    processor.evaluate(run_file_refs(parser.parse_lines(lines)), context, { bufnr = bufnr })

    -- Only change file a
    write_file(temp_dir .. "/a.js", "file a modified")

    -- Second evaluation: drift only for a.js
    local result = processor.evaluate(run_file_refs(parser.parse_lines(lines)), context, { bufnr = bufnr })
    local drift_diags = find_diagnostics(result, "custom:file_drift")

    assert.equals(1, #drift_diags)
    assert.is_true(drift_diags[1].error:match("a.js") ~= nil)
    assert.is_nil(drift_diags[1].error:match("b.js"))

    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(temp_dir, "rf")
  end)

  it("does not emit drift when no bufnr is provided", function()
    local temp_dir = vim.fn.tempname() .. "_file_drift_nobuf"
    vim.fn.mkdir(temp_dir, "p")
    write_file(temp_dir .. "/code.js", "const x = 1;")

    local context = context_util.from_file(temp_dir .. "/test.chat")
    local lines = { "@You:", "Review @./code.js" }

    -- First evaluation without bufnr
    processor.evaluate(run_file_refs(parser.parse_lines(lines)), context)

    -- Modify file
    write_file(temp_dir .. "/code.js", "const x = 2;")

    -- Second evaluation without bufnr: no state to compare against, so no drift
    local result = processor.evaluate(run_file_refs(parser.parse_lines(lines)), context)
    local drift_diags = find_diagnostics(result, "custom:file_drift")

    assert.equals(0, #drift_diags)

    vim.fn.delete(temp_dir, "rf")
  end)
end)
