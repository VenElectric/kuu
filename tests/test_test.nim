import std/unittest
import std/strutils
import helpers/testutils
import ../src/lerror
import ../src/ltypes

suite "test module: suite objects":
  test "a suite reports its own type":
    check runLua("""
      local s = test.suite("demo")
      print(type(s))
    """) == "testsuite\n"

  test "type() matches the registered TypeKind name":
    check runLua("""
      local s = test.suite("demo")
      print(type(s) == TypeKind.testsuite)
    """) == "true\n"

  test "the metatable is protected":
    check runLua("""
      local s = test.suite("demo")
      print(getmetatable(s))
    """) == "false\n"

  test "suite() with no arguments raises":
    expect LuaRuntimeError:
      discard runLua("""test.suite()""")

  test "suite() with a non-string name raises":
    expect LuaRuntimeError:
      discard runLua("""test.suite(42)""")

  test "the module is absent when mTest is not opened":
    check runLua("""print(test)""", ALLMODULES - {mTest}) == "nil\n"

suite "test module: registering tests":
  test "a suite with no tests still reports a summary":
    check runLua("""
      local s = test.suite("empty")
      s:run()
    """) == "[suite] empty\n  empty: 0 passed\n"

  test "test() registers a passing test":
    check runLua("""
      local s = test.suite("demo")
      s:test("passes", function() s:expect(true) end)
      s:run()
    """) == "[suite] demo\n    [OK] passes\n  demo: 1 passed\n"

  test "assignment registers a test":
    check runLua("""
      local s = test.suite("demo")
      s.test_len = function() s:expect(string.len("hello") == 5) end
      s:run()
    """) == "[suite] demo\n    [OK] test_len\n  demo: 1 passed\n"

  test "test() returns the suite, so calls chain":
    check runLua("""
      local s = test.suite("demo")
      s:test("a", function() end):test("b", function() end)
      s:run()
    """) == "[suite] demo\n    [OK] a\n    [OK] b\n  demo: 2 passed\n"

  test "tests run in declaration order, not hash order":
    check runLua("""
      local s = test.suite("ord")
      s:test("zeta", function() end)
      s:test("alpha", function() end)
      s:test("mid", function() end)
      s:run()
    """) == "[suite] ord\n    [OK] zeta\n    [OK] alpha\n    [OK] mid\n" &
            "  ord: 3 passed\n"

  test "a duplicate test name raises rather than being dropped":
    expect LuaRuntimeError:
      discard runLua("""
        local s = test.suite("dup")
        s:test("a", function() end)
        s:test("a", function() end)
      """)

  test "a duplicate name assigned as a field also raises":
    expect LuaRuntimeError:
      discard runLua("""
        local s = test.suite("dup")
        s.a = function() end
        s.a = function() end
      """)

  test "a non-callable test body raises":
    expect LuaRuntimeError:
      discard runLua("""
        local s = test.suite("bad")
        s.a = 5
      """)

  test "a non-string test name raises":
    expect LuaRuntimeError:
      discard runLua("""
        local s = test.suite("bad")
        s:test(42, function() end)
      """)

suite "test module: expect":
  test "a truthy expectation passes":
    check runLua("""
      local s = test.suite("e")
      s:test("t", function() s:expect(1 == 1) end)
      s:run()
    """) == "[suite] e\n    [OK] t\n  e: 1 passed\n"

  test "a falsy expectation fails and reports the value":
    check runLua("""
      local s = test.suite("e")
      s:test("t", function() s:expect(false) end)
      s:run()
    """) == "[suite] e\n    [FAIL] t\n" &
            "           expectation failed (got false)\n" &
            "  e: 0 passed, 1 failed\n"

  test "a custom message replaces the default detail":
    check runLua("""
      local s = test.suite("e")
      s:test("t", function() s:expect(false, "the widget was not frobbed") end)
      s:run()
    """) == "[suite] e\n    [FAIL] t\n" &
            "           the widget was not frobbed\n" &
            "  e: 0 passed, 1 failed\n"

  test "nil is falsy, not an argument error":
    check runLua("""
      local s = test.suite("e")
      s:test("t", function() s:expect(nil) end)
      s:run()
    """) == "[suite] e\n    [FAIL] t\n" &
            "           expectation failed (got nil)\n" &
            "  e: 0 passed, 1 failed\n"

  test "several failed expectations in one test report one FAIL and every detail":
    check runLua("""
      local s = test.suite("e")
      s:test("t", function()
        s:expect(false, "first")
        s:expect(false, "second")
      end)
      s:run()
    """) == "[suite] e\n    [FAIL] t\n           first\n           second\n" &
            "  e: 0 passed, 1 failed\n"

  test "expect outside of a test raises":
    expect LuaRuntimeError:
      discard runLua("""
        local s = test.suite("e")
        s:expect(true)
      """)

suite "test module: expectEqual":
  test "equal strings pass":
    check runLua("""
      local s = test.suite("eq")
      s:test("t", function() s:expectEqual(string.upper("a"), "A") end)
      s:run()
    """) == "[suite] eq\n    [OK] t\n  eq: 1 passed\n"

  test "an integer equals the same value as a float":
    check runLua("""
      local s = test.suite("eq")
      s:test("t", function() s:expectEqual(5, 5.0) end)
      s:run()
    """) == "[suite] eq\n    [OK] t\n  eq: 1 passed\n"

  test "a mismatch reports expected and actual, with strings quoted":
    check runLua("""
      local s = test.suite("eq")
      s:test("t", function() s:expectEqual("5", 5) end)
      s:run()
    """) == "[suite] eq\n    [FAIL] t\n" &
            "           expected 5, got \"5\"\n" &
            "  eq: 0 passed, 1 failed\n"

  test "two distinct tables are not equal":
    check runLua("""
      local s = test.suite("eq")
      s:test("t", function() s:expectEqual({}, {}) end)
      s:run()
    """).contains("[FAIL] t")

  test "the same table is equal to itself":
    check runLua("""
      local s = test.suite("eq")
      local t = {}
      s:test("t", function() s:expectEqual(t, t) end)
      s:run()
    """) == "[suite] eq\n    [OK] t\n  eq: 1 passed\n"

suite "test module: raises":
  test "a function that errors satisfies raises":
    check runLua("""
      local s = test.suite("r")
      s:test("t", function() s:raises(function() error("boom") end) end)
      s:run()
    """) == "[suite] r\n    [OK] t\n  r: 1 passed\n"

  test "a function that does not error fails":
    check runLua("""
      local s = test.suite("r")
      s:test("t", function() s:raises(function() end) end)
      s:run()
    """) == "[suite] r\n    [FAIL] t\n" &
            "           expected an error, but none was raised\n" &
            "  r: 0 passed, 1 failed\n"

  test "a matching message substring satisfies raises":
    check runLua("""
      local s = test.suite("r")
      s:test("t", function()
        s:raises("boom", function() error("boom goes the dynamite") end)
      end)
      s:run()
    """) == "[suite] r\n    [OK] t\n  r: 1 passed\n"

  test "a non-matching message substring fails":
    let output = runLua("""
      local s = test.suite("r")
      s:test("t", function()
        s:raises("frobnicate", function() error("boom") end)
      end)
      s:run()
    """)
    check output.contains("[FAIL] t")
    check output.contains("expected error containing 'frobnicate'")

  test "a runtime error from the VM is caught, not just error()":
    check runLua("""
      local s = test.suite("r")
      s:test("t", function()
        s:raises("index", function() local t = nil; return t.x end)
      end)
      s:run()
    """) == "[suite] r\n    [OK] t\n  r: 1 passed\n"

  test "raises with a non-callable argument is reported as a failed test":
    # The argument error is thrown inside a test body, so the runner traps it
    # and reports it rather than letting it escape to the caller.
    let output = runLua("""
      local s = test.suite("r")
      s:test("t", function() s:raises(5) end)
      s:run()
    """)
    check output.contains("[FAIL] t")
    check output.contains("callable")
    check output.contains("r: 0 passed, 1 failed")

suite "test module: setup and teardown":
  test "setup and teardown wrap every test":
    check runLua("""
      local s = test.suite("hooks")
      s:setup(function() print("setup") end)
      s:teardown(function() print("teardown") end)
      s:test("a", function() print("body a") end)
      s:test("b", function() print("body b") end)
      s:run()
    """) == "[suite] hooks\n" &
            "setup\nbody a\nteardown\n    [OK] a\n" &
            "setup\nbody b\nteardown\n    [OK] b\n" &
            "  hooks: 2 passed\n"

  test "setupAll and teardownAll run once around the whole suite":
    check runLua("""
      local s = test.suite("hooks")
      s:setupAll(function() print("once-before") end)
      s:teardownAll(function() print("once-after") end)
      s:test("a", function() end)
      s:test("b", function() end)
      s:run()
    """) == "[suite] hooks\nonce-before\n    [OK] a\n    [OK] b\n" &
            "once-after\n  hooks: 2 passed\n"

  test "teardown still runs when the test body errors":
    let output = runLua("""
      local s = test.suite("hooks")
      s:teardown(function() print("cleanup ran") end)
      s:test("a", function() error("boom") end)
      s:run()
    """)
    check output.contains("cleanup ran")
    check output.contains("[FAIL] a")

  test "a failing setup fails the test and skips the body":
    let output = runLua("""
      local s = test.suite("hooks")
      s:setup(function() error("setup exploded") end)
      s:test("a", function() print("body should not run") end)
      s:run()
    """)
    check output.contains("[FAIL] a")
    check output.contains("setup failed:")
    check not output.contains("body should not run")

  test "a failing setupAll skips every test":
    let output = runLua("""
      local s = test.suite("hooks")
      s:setupAll(function() error("no dice") end)
      s:test("a", function() print("should not run") end)
      s:test("b", function() print("should not run") end)
      s:run()
    """)
    check output.contains("[FAIL] <setupAll>")
    check not output.contains("should not run")
    check output.contains("0 passed, 2 failed")

  test "a non-callable hook raises":
    expect LuaRuntimeError:
      discard runLua("""
        local s = test.suite("hooks")
        s:setup(5)
      """)

suite "test module: error isolation":
  test "a test that errors is reported and later tests still run":
    let output = runLua("""
      local s = test.suite("iso")
      s:test("boom", function() error("kaboom") end)
      s:test("after", function() s:expect(true) end)
      s:run()
    """)
    check output.contains("[FAIL] boom")
    check output.contains("kaboom")
    check output.contains("[OK] after")
    check output.contains("iso: 1 passed, 1 failed")

  test "the VM is still usable after a test errors":
    let output = runLua("""
      local s = test.suite("iso")
      s:test("boom", function() error("kaboom") end)
      s:run()
      print("still alive")
    """)
    check output.contains("still alive")

  test "a closure captured by an aborted test does not corrupt a later one":
    check runLua("""
      local s = test.suite("iso")
      s:test("captures then throws", function()
        local n = 1
        local grab = function() return n end
        error("bail")
      end)
      s:test("later", function()
        local m = 99
        s:expectEqual(m, 99)
      end)
      s:run()
      print("done")
    """).contains("[OK] later")

  test "an error inside a metamethod does not exhaust the metatable depth":
    check runLua("""
      local s = test.suite("iso")
      local t = setmetatable({}, {__index = function() error("nope") end})
      s:test("a", function() s:raises(function() return t.x end) end)
      s:test("b", function() s:raises(function() return t.y end) end)
      s:test("c", function() s:raises(function() return t.z end) end)
      s:run()
    """) == "[suite] iso\n    [OK] a\n    [OK] b\n    [OK] c\n  iso: 3 passed\n"

suite "test module: run and runAll":
  test "run returns the failure count":
    check runLua("""
      local s = test.suite("rc")
      s:test("a", function() s:expect(false, "nope") end)
      s:test("b", function() s:expect(true) end)
      local failed = s:run()
      print(failed)
    """).endsWith("1\n")

  test "run returns zero when everything passes":
    check runLua("""
      local s = test.suite("rc")
      s:test("a", function() s:expect(true) end)
      print(s:run())
    """) == "[suite] rc\n    [OK] a\n  rc: 1 passed\n0\n"

  test "runAll totals across suites":
    check runLua("""
      local a = test.suite("a")
      a:test("t", function() end)
      local b = test.suite("b")
      b:test("t", function() end)
      print(test.runAll(a, b))
    """) == "[suite] a\n    [OK] t\n  a: 1 passed\n" &
            "[suite] b\n    [OK] t\n  b: 1 passed\n" &
            "  total: 2 passed\n0\n"

  test "runAll reports a failing suite in the total":
    check runLua("""
      local a = test.suite("a")
      a:test("t", function() a:expect(false, "no") end)
      local b = test.suite("b")
      b:test("t", function() b:expect(false, "no") end)
      print(test.runAll(a, b))
    """) == "[suite] a\n    [FAIL] t\n           no\n  a: 0 passed, 1 failed\n" &
            "[suite] b\n    [FAIL] t\n           no\n  b: 0 passed, 1 failed\n" &
            "  total: 0 passed, 2 failed\n2\n"

  test "runAll with a single suite omits the total line":
    check runLua("""
      local a = test.suite("a")
      a:test("t", function() end)
      print(test.runAll(a))
    """) == "[suite] a\n    [OK] t\n  a: 1 passed\n0\n"

  test "runAll with no arguments returns zero":
    check runLua("""print(test.runAll())""") == "0\n"

  test "runAll with a non-suite argument raises":
    expect LuaRuntimeError:
      discard runLua("""test.runAll(5)""")

  test "a suite can be run twice and the counts reset":
    check runLua("""
      local s = test.suite("twice")
      s:test("a", function() end)
      s:run()
      s:run()
    """) == "[suite] twice\n    [OK] a\n  twice: 1 passed\n" &
            "[suite] twice\n    [OK] a\n  twice: 1 passed\n"