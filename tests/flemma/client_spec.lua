--- Tests for the HTTP client module.
--- Covers curl command construction and header behaviour verified via a
--- local socat listener that captures the raw request.

local client = require("flemma.client")

-- ─── unit: prepare_curl_command ────────────────────────────────────────────

describe("client.prepare_curl_command()", function()
  it("includes Expect: suppression header", function()
    local cmd = client.prepare_curl_command("/dev/null", { "Content-Type: application/json" }, "http://localhost", {})
    local found = false
    for i, arg in ipairs(cmd) do
      if arg == "Expect:" and cmd[i - 1] == "-H" then
        found = true
        break
      end
    end
    assert.is_true(found, "curl command must include -H 'Expect:' to suppress 100-continue")
  end)

  it("respects connect_timeout and timeout parameters", function()
    local cmd = client.prepare_curl_command("/dev/null", {}, "http://localhost", {
      connect_timeout = 5,
      timeout = 60,
    })
    local flat = table.concat(cmd, " ")
    assert.is_truthy(flat:match("%-%-connect%-timeout 5"))
    assert.is_truthy(flat:match("%-%-max%-time 60"))
  end)
end)

-- ─── integration: header capture via socat ─────────────────────────────────

describe("client.send_request() header wire format", function()
  local PORT = 19876
  local socat_job ---@type integer|nil

  ---@type string[]
  local captured_lines

  local function skip_unless_socat()
    if vim.fn.executable("socat") ~= 1 then
      pending("socat not installed, skipping")
      return true
    end
    return false
  end

  --- Start a one-shot socat listener that captures raw request bytes,
  --- then replies with a minimal 200 OK so curl exits cleanly.
  ---@return boolean ok
  local function start_listener()
    captured_lines = {}

    -- socat SYSTEM runs in a shell — the script reads stdin line-by-line
    -- (the HTTP request from curl), stores everything, then writes back a
    -- minimal HTTP/1.1 200 OK response with an empty JSON body.
    local script = table.concat({
      "#!/bin/sh",
      'lines=""',
      "while IFS= read -r line; do",
      '  lines="$lines$line\\n"',
      -- blank line (just \\r) ends HTTP headers
      '  case "$line" in ""|"\\r") break;; esac',
      "done",
      -- send back a valid HTTP response so curl exits 0
      'printf "HTTP/1.1 200 OK\\r\\nContent-Length: 2\\r\\nConnection: close\\r\\n\\r\\n{}"',
      -- then dump captured headers to stderr for our on_stderr handler
      'printf "%b" "$lines" >&2',
    }, "\n")

    socat_job = vim.fn.jobstart({
      "socat",
      "TCP-LISTEN:" .. PORT .. ",reuseaddr",
      "SYSTEM:" .. vim.fn.shellescape(script),
    }, {
      on_stderr = function(_, data)
        if data then
          for _, line in ipairs(data) do
            if #line > 0 then
              table.insert(captured_lines, line)
            end
          end
        end
      end,
      on_exit = function() end,
    })

    if not socat_job or socat_job <= 0 then
      return false
    end

    -- Give socat a moment to bind the port.
    vim.wait(200, function()
      return false
    end, 50)

    return true
  end

  after_each(function()
    if socat_job then
      pcall(vim.fn.jobstop, socat_job)
      socat_job = nil
    end
  end)

  it("does not send Expect: 100-continue on the wire", function()
    if skip_unless_socat() then
      return
    end
    if not start_listener() then
      pending("failed to start socat listener")
      return
    end

    local done = false

    client.send_request({
      endpoint = "http://127.0.0.1:" .. PORT .. "/v1/test",
      headers = { "Content-Type: application/json" },
      request_body = { model = "test-model", messages = {} },
      parameters = { connect_timeout = 5, timeout = 10 },
      callbacks = {
        on_request_complete = function()
          done = true
        end,
      },
      process_response_line_fn = function() end,
      finalize_response_fn = function() end,
    })

    vim.wait(5000, function()
      return done
    end, 50)

    assert.is_true(done, "request should complete within timeout")

    -- Wait a beat for stderr delivery to finish.
    vim.wait(300, function()
      return false
    end, 50)

    -- Verify no Expect header was sent.
    local raw = table.concat(captured_lines, "\n"):lower()
    assert.is_falsy(raw:match("expect:%s*100%-continue"), "curl must NOT send Expect: 100-continue")
    -- Also confirm we did capture *something* (sanity check).
    assert.is_truthy(raw:match("content%-type"), "should have captured at least the Content-Type header")
  end)
end)
