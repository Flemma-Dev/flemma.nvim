local scanner = require("flemma.templating.scanner")

describe("templating.scanner", function()
  -- Helpers: call find_closing with default start_pos=1
  local function scan_expr(s, start)
    return scanner.find_closing(s, start or 1, "expression")
  end

  local function scan_code(s, start)
    return scanner.find_closing(s, start or 1, "code")
  end

  -- Extract the matched delimiter text from return values
  local function delimiter(s, cs, ce)
    return s:sub(cs, ce)
  end

  -- Extract content before the delimiter
  local function content_before(s, cs)
    return s:sub(1, cs - 1)
  end

  describe("find_closing", function()
    -- ================================================================
    -- 1. Basic expressions (no special content)
    -- ================================================================
    describe("basic expressions", function()
      it("finds simple closing delimiter", function()
        local s = " x + 1 }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" x + 1 ", content_before(s, cs))
      end)

      it("finds closing at start of string", function()
        local s = "}}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(1, cs)
      end)

      it("finds closing with only whitespace before", function()
        local s = "  }}"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals("  ", content_before(s, cs))
      end)

      it("finds closing when delimiter is entire string", function()
        local cs, ce = scan_expr("}}")
        assert.is_not_nil(cs)
        assert.equals(1, cs)
        assert.equals(2, ce)
      end)

      it("returns nil when no closing delimiter exists", function()
        local cs, ce = scan_expr(" x + 1 ")
        assert.is_nil(cs)
        assert.is_nil(ce)
      end)

      it("returns nil for single closing brace", function()
        local cs, ce = scan_expr(" x } rest")
        assert.is_nil(cs)
        assert.is_nil(ce)
      end)

      it("skips lone } at depth 0 when not followed by }", function()
        local s = " x } + y }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" x } + y ", content_before(s, cs))
      end)

      it("returns nil for empty input", function()
        local cs, ce = scan_expr("")
        assert.is_nil(cs)
        assert.is_nil(ce)
      end)
    end)

    -- ================================================================
    -- 2. String literals containing }}
    -- ================================================================
    describe("string literals containing closing delimiter", function()
      it("skips }} inside double-quoted string", function()
        local s = [[ "hello }}" }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find('"hello }}"', 1, true))
      end)

      it("skips }} inside single-quoted string", function()
        local s = [[ 'hello }}' }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find("'hello }}'", 1, true))
      end)

      it("skips }} inside long string [[]]", function()
        local s = [=[ [[hello }}]] }}rest]=]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find("[[hello }}]]", 1, true))
      end)

      it("skips }} inside leveled long string [=[]=]", function()
        local s = [==[ [=[}}]=] }}rest]==]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find("[=[}}]=]", 1, true))
      end)

      it("skips }} in string at end of expression", function()
        local s = [[ "val}}" }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find('"val}}"', 1, true))
      end)

      it("skips }} in multiple strings", function()
        local s = [[ "a}}" .. "b}}" }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find('"b}}"', 1, true))
      end)

      it("handles empty string before closing", function()
        local s = [[ "" }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("skips {{ and }} inside string", function()
        local s = [[ "{{x}}" }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find('"{{x}}"', 1, true))
      end)
    end)

    -- ================================================================
    -- 3. Escape sequences in strings
    -- ================================================================
    describe("escape sequences in strings", function()
      it("handles escaped quotes in double-quoted string", function()
        -- Buffer text: "he said \"yes\"" }}rest
        -- The \" inside the string should not end it
        local s = [[ "he said \"yes\"" }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find("he said", 1, true))
      end)

      it("handles escaped backslash before closing quote", function()
        -- Buffer text: "\\" }}rest
        -- \\ is escaped backslash, then " closes the string
        local s = [[ "\\" }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("handles escaped backslash before escaped quote", function()
        -- Buffer text: "\\\"" }}rest
        -- \\ is escaped backslash, \" is escaped quote, then " closes
        local s = [[ "\\\"" }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("handles escape followed by }} inside string", function()
        -- Buffer text: "a\"b}}c" }}rest
        -- \" doesn't end string, }} inside string is skipped
        local s = [[ "a\"b}}c" }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find("b}}c", 1, true))
      end)

      it("handles escaped single quote in single-quoted string", function()
        -- Buffer text: 'it\'s }}' }}rest
        local s = [[ 'it\'s }}' }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)
    end)

    -- ================================================================
    -- 4. Brace balancing (expression mode)
    -- ================================================================
    describe("brace balancing", function()
      it("balances simple table constructor", function()
        local s = " {a=1} }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" {a=1} ", content_before(s, cs))
      end)

      it("balances nested tables", function()
        local s = " {a={b=1}} }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" {a={b=1}} ", content_before(s, cs))
      end)

      it("handles table closing brace adjacent to delimiter", function()
        -- Three }s: first closes table, remaining two are delimiter
        local s = " {1}}}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" {1}", content_before(s, cs))
      end)

      it("balances empty table", function()
        local s = " {} }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" {} ", content_before(s, cs))
      end)

      it("balances multiple tables", function()
        local s = " {1} .. {2} }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" {1} .. {2} ", content_before(s, cs))
      end)

      it("balances empty table adjacent to delimiter", function()
        -- {}}} = empty table close, then }} closing delimiter
        local s = " {}}}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" {}", content_before(s, cs))
      end)

      it("balances table with string containing single }", function()
        -- String "val}" has one } inside — does not affect brace depth
        local s = [[ {key="val}"} }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find('{key="val}"}', 1, true))
      end)

      it("balances table with string containing }}", function()
        -- String "}}" inside table — skipped entirely
        local s = [[ {key="}}"} }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find('{key="}}"}', 1, true))
      end)

      it("balances deeply nested tables", function()
        local s = " {{{1}}} }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" {{{1}}} ", content_before(s, cs))
      end)

      it("balances nested tables adjacent to delimiter", function()
        -- {a={b=1}}}} = nested table (4 }s: 2 close tables, 2 close expression)
        local s = " {a={b=1}}}}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" {a={b=1}}", content_before(s, cs))
      end)

      it("balances maximum depth nesting", function()
        local s = " {{{{{}}}}} }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" {{{{{}}}}} ", content_before(s, cs))
      end)
    end)

    -- ================================================================
    -- 5. Comments containing }}
    -- ================================================================
    describe("comments containing closing delimiter", function()
      it("skips }} in single-line comment", function()
        local s = " x -- }} comment\n }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        -- Content includes the comment line
        assert.truthy(content_before(s, cs):find("-- }}", 1, true))
      end)

      it("skips }} in long comment --[[]]", function()
        local s = " x --[[}}]] }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find("--[[}}]]", 1, true))
      end)

      it("skips }} in leveled long comment --[=[]=]", function()
        local s = [==[ x --[=[}}]=] }}rest]==]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("returns nil when }} only in comment at EOF", function()
        local s = " x -- }}"
        local cs, ce = scan_expr(s)
        assert.is_nil(cs)
        assert.is_nil(ce)
      end)

      it("finds }} on next line after single-line comment", function()
        local s = " x --comment\n}}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)
    end)

    -- ================================================================
    -- 6. Code block mode (%})
    -- ================================================================
    describe("code block mode", function()
      it("finds simple %} closing", function()
        local s = " if x then %}rest"
        local cs, ce = scan_code(s)
        assert.is_not_nil(cs)
        assert.equals("%}", delimiter(s, cs, ce))
        assert.equals(" if x then ", content_before(s, cs))
      end)

      it("skips %} inside double-quoted string", function()
        local s = [[ "contains %}" %}rest]]
        local cs, ce = scan_code(s)
        assert.is_not_nil(cs)
        assert.equals("%}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find('"contains %}"', 1, true))
      end)

      it("skips %} inside single-quoted string", function()
        local s = [[ 'contains %}' %}rest]]
        local cs, ce = scan_code(s)
        assert.is_not_nil(cs)
        assert.equals("%}", delimiter(s, cs, ce))
      end)

      it("skips %} inside long string", function()
        local s = [=[ [[contains %}]] %}rest]=]
        local cs, ce = scan_code(s)
        assert.is_not_nil(cs)
        assert.equals("%}", delimiter(s, cs, ce))
      end)

      it("skips %} inside single-line comment", function()
        local s = " x --%}\n %}rest"
        local cs, ce = scan_code(s)
        assert.is_not_nil(cs)
        assert.equals("%}", delimiter(s, cs, ce))
      end)

      it("does not track brace depth in code mode", function()
        -- Unbalanced { should not prevent finding %}
        local s = " { %}rest"
        local cs, ce = scan_code(s)
        assert.is_not_nil(cs)
        assert.equals("%}", delimiter(s, cs, ce))
      end)

      it("does not match lone % in code mode", function()
        -- % is Lua's modulo operator — only %} is a closing delimiter
        local s = " x % 2 %}rest"
        local cs, ce = scan_code(s)
        assert.is_not_nil(cs)
        assert.equals("%}", delimiter(s, cs, ce))
        assert.equals(" x % 2 ", content_before(s, cs))
      end)
    end)

    -- ================================================================
    -- 7. Trim variants
    -- ================================================================
    describe("trim variants", function()
      it("detects trim-after on expression -}}", function()
        local s = " x -}}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("-}}", delimiter(s, cs, ce))
        assert.equals(" x ", content_before(s, cs))
      end)

      it("detects trim-after on code block -%}", function()
        local s = " x -%}rest"
        local cs, ce = scan_code(s)
        assert.is_not_nil(cs)
        assert.equals("-%}", delimiter(s, cs, ce))
        assert.equals(" x ", content_before(s, cs))
      end)

      it("does not false-match trim when dash is not adjacent", function()
        local s = " x - }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" x - ", content_before(s, cs))
      end)

      it("skips -}} inside string then finds real trim close", function()
        local s = [[ "-}}" -}}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("-}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find('"-}}"', 1, true))
      end)

      it("detects trim on brace-balanced expression", function()
        local s = " {1} -}}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("-}}", delimiter(s, cs, ce))
        assert.equals(" {1} ", content_before(s, cs))
      end)
    end)

    -- ================================================================
    -- 8. Multi-line expressions
    -- ================================================================
    describe("multi-line expressions", function()
      it("finds closing on different line", function()
        local s = " x +\n y }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("finds closing when on its own line", function()
        local s = " x\n}}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("skips multi-line string containing }}", function()
        local s = ' "line1\nline2}}" }}rest'
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find("line2}}", 1, true))
      end)

      it("skips comment on same line, finds }} on next", function()
        local s = " x -- }}\n}}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("skips multi-line long string containing }}", function()
        local s = [=[ [[
}}
]] }}rest]=]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("finds multi-line code block close", function()
        local s = " for i = 1, 10 do\n  print(i)\n %}rest"
        local cs, ce = scan_code(s)
        assert.is_not_nil(cs)
        assert.equals("%}", delimiter(s, cs, ce))
      end)
    end)

    -- ================================================================
    -- 9. Edge cases
    -- ================================================================
    describe("edge cases", function()
      it("returns nil for unclosed double-quoted string", function()
        local s = [[ "unterminated }}]]
        local cs, ce = scan_expr(s)
        assert.is_nil(cs)
        assert.is_nil(ce)
      end)

      it("returns nil for unclosed single-quoted string", function()
        local s = [[ 'unterminated }}]]
        local cs, ce = scan_expr(s)
        assert.is_nil(cs)
        assert.is_nil(ce)
      end)

      it("returns nil for unclosed long string", function()
        local s = " [[unterminated }}"
        local cs, ce = scan_expr(s)
        assert.is_nil(cs)
        assert.is_nil(ce)
      end)

      it("returns nil for unclosed long comment", function()
        local s = " --[[unterminated }}"
        local cs, ce = scan_expr(s)
        assert.is_nil(cs)
        assert.is_nil(ce)
      end)

      it("does not close long string with wrong level", function()
        -- [=[ needs ]=] not ]]
        local s = [==[ [=[ ]] ]=] }}rest]==]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("does not close long string with single ]", function()
        local s = [==[ [=[ ] ]=] }}rest]==]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("handles } as last character without second }", function()
        local cs, ce = scan_expr(" x }")
        assert.is_nil(cs)
        assert.is_nil(ce)
      end)

      it("respects start_pos parameter", function()
        -- }} exists before start_pos but should be ignored
        local s = "}}abc }}rest"
        local cs, ce = scan_expr(s, 4)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        -- Should find the second }}, not the first
        assert.truthy(cs > 3)
      end)

      it("returns nil for code mode with no %}", function()
        local cs, ce = scan_code(" if true then end")
        assert.is_nil(cs)
        assert.is_nil(ce)
      end)

      it("does not confuse -- with long comment when not followed by [", function()
        -- -- without [[ is single-line comment, ends at newline
        local s = " x -- not long\n }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("treats --[ as single-line comment not long comment", function()
        -- --[ without a second [ is a regular single-line comment
        local s = " x --[ }}]\n }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("handles string immediately followed by }}", function()
        -- No space between closing quote and }}
        local s = [[ "str"}}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("handles alternating string types", function()
        local s = [[ "a}}" .. 'b}}' }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)
    end)
  end)
end)
