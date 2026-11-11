## test -- a small xUnit-style test module for kuu.
##
##   local s = test.suite("string")
##   s:setup(function() ... end)
##   s.test_len = function() s:expect(string.len("hello") == 5) end
##   s:test("upper", function() s:expectEqual(string.upper("a"), "A") end)
##   s:teardown(function() ... end)
##
##   if test.runAll(s) > 0 then process.exit(1) end

import std/[tables, strutils]
import ../ltypes, ../lvalue, ../lerror, ../lutil, ../lvm, ../lstyle

type
  TestSuiteObj = object of LuaUserDataObj
    name*: string
    setupFn*, teardownFn*: LuaValue        # per test
    setupAllFn*, teardownAllFn*: LuaValue  # per suite
    tests*: OrderedTable[string, LuaValue] # ordered, so tests run as declared
    passed*, failed*: int
    currentTest*: string
    currentMessages*: seq[string]
  TestSuite* = ref TestSuiteObj

proc asSuite(v: LuaValue): TestSuite =
  if not isUserData(v) or v.ud.isNil or not (v.ud of TestSuite):
    raise newException(LuaRuntimeError, "bad argument (test suite expected)")
  return TestSuite(v.ud)

proc addTest(s: TestSuite, name: string, fn: LuaValue) =
  if s.tests.hasKey(name):
    raise newException(LuaRuntimeError,
      "duplicate test '" & name & "' in suite '" & s.name & "'")
  s.tests[name] = fn

proc requireInTest(s: TestSuite, what: string) =
  if s.currentTest.len == 0:
    raise newException(LuaRuntimeError, what & "() called outside of a test")

proc valueRepr(v: LuaValue): string =
  # `$` renders strings bare, which makes expectEqual("5", 5) report
  # "expected 5, got 5". Quote them so the failure is readable.
  if isString(v): "\"" & v.sval & "\"" else: $v

# --- Output ---------------------------------------------------------------

proc writeOK(vm: var VM, name: string) =
  vm.styledWriteLine("    [", fgGreen, "OK", fgDefault, "] ", name)

proc writeFail(vm: var VM, name: string) =
  vm.styledWriteLine("    [", fgRed, "FAIL", fgDefault, "] ", name)

proc writeDetail(vm: var VM, msg: string) =
  vm.styledWriteLine("           ", fgYellow, msg, fgDefault)

proc writeSummary(vm: var VM, label: string, passed, failed: int) =
  if failed == 0:
    vm.styledWriteLine("  ", label, ": ", fgGreen, $passed & " passed", fgDefault)
  else:
    vm.styledWriteLine("  ", label, ": ", fgGreen, $passed & " passed",
                       fgDefault, ", ", fgRed, $failed & " failed", fgDefault)

# --- Methods: none of these need the metatable, only an existing suite ----

proc luaSuiteTest(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 3:
    raise newException(LuaRuntimeError, argErrFmtNumbered("test", "two"))
  let s = asSuite(args[0])
  if not isString(args[1]):
    raise newException(LuaRuntimeError, kindErrFmt(1, "test", "string"))
  if not isCallable(args[2]):
    raise newException(LuaRuntimeError, kindErrFmt(2, "test", "callable"))
  s.addTest(getString(args[1]), args[2])
  return @[args[0]]

proc luaSuiteSetup(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 2:
    raise newException(LuaRuntimeError, argErrFmtNumbered("setup", "one"))
  if not isCallable(args[1]):
    raise newException(LuaRuntimeError, kindErrFmt(1, "setup", "callable"))
  asSuite(args[0]).setupFn = args[1]
  return @[args[0]]

proc luaSuiteTeardown(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 2:
    raise newException(LuaRuntimeError, argErrFmtNumbered("teardown", "one"))
  if not isCallable(args[1]):
    raise newException(LuaRuntimeError, kindErrFmt(1, "teardown", "callable"))
  asSuite(args[0]).teardownFn = args[1]
  return @[args[0]]

proc luaSuiteSetupAll(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 2:
    raise newException(LuaRuntimeError, argErrFmtNumbered("setupAll", "one"))
  if not isCallable(args[1]):
    raise newException(LuaRuntimeError, kindErrFmt(1, "setupAll", "callable"))
  asSuite(args[0]).setupAllFn = args[1]
  return @[args[0]]

proc luaSuiteTeardownAll(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 2:
    raise newException(LuaRuntimeError, argErrFmtNumbered("teardownAll", "one"))
  if not isCallable(args[1]):
    raise newException(LuaRuntimeError, kindErrFmt(1, "teardownAll", "callable"))
  asSuite(args[0]).teardownAllFn = args[1]
  return @[args[0]]

proc luaSuiteExpect(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 2:
    raise newException(LuaRuntimeError, argErrFmtNumbered("expect", "one"))
  let s = asSuite(args[0])
  s.requireInTest("expect")
  if not truthy(args[1]):
    if args.len >= 3 and isString(args[2]):
      s.currentMessages.add(getString(args[2]))
    else:
      s.currentMessages.add("expectation failed (got " & valueRepr(args[1]) & ")")
  return @[args[0]]

proc luaSuiteExpectEqual(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 3:
    raise newException(LuaRuntimeError, argErrFmtNumbered("expectEqual", "two"))
  let s = asSuite(args[0])
  s.requireInTest("expectEqual")
  # lvalue's `==`: strings and numbers by value (5 == 5.0 passes), everything
  # else by identity. It does not consult __eq.
  if args[1] != args[2]:
    if args.len >= 4 and isString(args[3]):
      s.currentMessages.add(getString(args[3]))
    else:
      s.currentMessages.add("expected " & valueRepr(args[2]) &
                            ", got " & valueRepr(args[1]))
  return @[args[0]]

proc luaSuiteRaises(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  ## s:raises(fn)            -- any error
  ## s:raises(substring, fn) -- error message must contain `substring`
  if args.len < 2:
    raise newException(LuaRuntimeError, argErrFmtNumbered("raises", "one"))
  let s = asSuite(args[0])
  s.requireInTest("raises")

  var pattern = ""
  var fn: LuaValue
  if isCallable(args[1]):
    fn = args[1]
  elif isString(args[1]) and args.len >= 3 and isCallable(args[2]):
    pattern = getString(args[1])
    fn = args[2]
  else:
    raise newException(LuaRuntimeError, kindErrFmt(1, "raises", "callable"))

  let r = vm.protectedCall(fn)
  if r.ok:
    s.currentMessages.add("expected an error, but none was raised")
  elif pattern.len > 0 and not r.errMsg.contains(pattern):
    s.currentMessages.add("expected error containing '" & pattern &
                          "', got '" & r.errMsg & "'")
  return @[args[0]]

proc runSuite(s: TestSuite, vm: var VM): int =
  s.passed = 0
  s.failed = 0
  vm.styledWriteLine(fgCyan, "[suite] ", fgDefault, s.name)

  if not isNil(s.setupAllFn):
    let r = vm.protectedCall(s.setupAllFn)
    if not r.ok:
      vm.writeFail("<setupAll>")
      vm.writeDetail(r.errMsg)
      s.failed = max(1, s.tests.len)
      vm.writeSummary(s.name, s.passed, s.failed)
      return s.failed

  for name, fn in s.tests.pairs:
    s.currentTest = name
    s.currentMessages.setLen(0)

    var err = ""
    if not isNil(s.setupFn):
      let r = vm.protectedCall(s.setupFn)
      if not r.ok: err = "setup failed: " & r.errMsg
    if err.len == 0:
      let r = vm.protectedCall(fn)
      if not r.ok: err = r.errMsg
    if not isNil(s.teardownFn):   # runs even when the body blew up
      let r = vm.protectedCall(s.teardownFn)
      if not r.ok: s.currentMessages.add("teardown failed: " & r.errMsg)

    if err.len > 0 or s.currentMessages.len > 0:
      vm.writeFail(name)
      if err.len > 0: vm.writeDetail(err)
      for m in s.currentMessages: vm.writeDetail(m)
      inc s.failed
    else:
      vm.writeOK(name)
      inc s.passed

    s.currentTest = ""
    s.currentMessages.setLen(0)

  if not isNil(s.teardownAllFn):
    let r = vm.protectedCall(s.teardownAllFn)
    if not r.ok:
      vm.writeFail("<teardownAll>")
      vm.writeDetail(r.errMsg)
      inc s.failed

  vm.writeSummary(s.name, s.passed, s.failed)
  return s.failed

proc luaSuiteRun(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 1:
    raise newException(LuaRuntimeError, argErrFmtNumbered("run", "none"))
  return @[newLuaInteger(int64(asSuite(args[0]).runSuite(vm)))]

proc luaSuiteNewIndex(args: varargs[LuaValue]): seq[LuaValue] =
  ## s.test_name = function() ... end
  if args.len < 3:
    raise newException(LuaRuntimeError, "bad assignment to test suite")
  let s = asSuite(args[0])
  if not isString(args[1]):
    raise newException(LuaRuntimeError, "invalid test name (string expected)")
  if not isCallable(args[2]):
    raise newException(LuaRuntimeError, "invalid test body (callable expected)")
  s.addTest(getString(args[1]), args[2])
  return @[]

proc luaTestRunAll(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  var passed, failed = 0
  for a in args:
    let s = asSuite(a)
    failed += s.runSuite(vm)
    passed += s.passed
  if args.len > 1:
    vm.writeSummary("total", passed, failed)
  return @[newLuaInteger(int64(failed))]

proc newTestLib*(): LuaValue =
  let SuiteMethods = newLuaTable()
  SuiteMethods.tval[newLuaString("test")] = newNimFn(luaSuiteTest)
  SuiteMethods.tval[newLuaString("run")] = newNimFnVM(luaSuiteRun)
  SuiteMethods.tval[newLuaString("expect")] = newNimFn(luaSuiteExpect)
  SuiteMethods.tval[newLuaString("expectEqual")] = newNimFn(luaSuiteExpectEqual)
  SuiteMethods.tval[newLuaString("raises")] = newNimFnVM(luaSuiteRaises)
  SuiteMethods.tval[newLuaString("setup")] = newNimFn(luaSuiteSetup)
  SuiteMethods.tval[newLuaString("teardown")] = newNimFn(luaSuiteTeardown)
  SuiteMethods.tval[newLuaString("setupAll")] = newNimFn(luaSuiteSetupAll)
  SuiteMethods.tval[newLuaString("teardownAll")] = newNimFn(luaSuiteTeardownAll)

  let suiteMT = newLuaTable()
  suiteMT.tval[MTINDEX] = SuiteMethods
  suiteMT.tval[MTNEWINDEX] = newNimFn(luaSuiteNewIndex)
  suiteMT.tval[MTTYPE] = newLuaString("testsuite")
  suiteMT.tval[MTMETA] = newLuaBool(false)

  let luaTestSuite = proc(args: varargs[LuaValue]): seq[LuaValue] =
    if args.len < 1:
      raise newException(LuaRuntimeError, argErrFmtNumbered("suite", "one"))
    if not isString(args[0]):
      raise newException(LuaRuntimeError, kindErrFmt(1, "suite", "string"))
    var suite = newUserData(TestSuite(name: getString(args[0])))
    suite.mt = suiteMT
    return @[suite]

  result = newLuaTable()
  result.tval[newLuaString("suite")] = newNimFn(luaTestSuite)
  result.tval[newLuaString("runAll")] = newNimFnVM(luaTestRunAll)