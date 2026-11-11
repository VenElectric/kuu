import std/[tables,strutils,sugar,math]
import ../lvalue,../ltypes,../lerror,../lutil,lmatch,../lvm
from algorithm import reverse

const REPEATLIMIT = 4 * 1024 * 1024

proc resolveByteIndex(pos: int64, len: int): int =
  # Converts a Lua-style 1-based (or negative, counting from the end)
  # position into a clamped, 0-based Nim index.
  var i = pos
  if i < 0: i = int64(len) + i + 1
  if i < 1: i = 1
  if i > int64(len): i = int64(len)
  return int(i) - 1

proc luaStrByte(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 1 or len(args) > 3:
    raise newException(LuaRuntimeError, argErrFmtNumbered("byte", "1, 2, or 3"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError, kindErrFmt(1, "byte", "string"))
  let str = getString(args[0])

  if str.len == 0:
    return @[]   # matches real Lua: string.byte("") returns nothing at all

  let sPos = if len(args) >= 2: intVal(args[1]) else: 1'i64
  let ePos = if len(args) >= 3: intVal(args[2]) else: sPos

  let startIdx = resolveByteIndex(sPos, str.len)
  let endIdx = resolveByteIndex(ePos, str.len)

  result = @[]
  if startIdx > endIdx: return result   # an empty range is valid, not an error
  for i in countup(startIdx, endIdx):
    result.add(newLuaInteger(int64(str[i])))

proc luaStrChar(args: varargs[LuaValue]): seq[LuaValue] = 
  var s: string
  for i, a in args:
    if not isNumber(a):
      raise newException(LuaRuntimeError, kindErrFmt(i + 1, "char", "number"))
    let code = intVal(a)
    if code < 0 or code > 255:
      raise newException(LuaRuntimeError, "bad argument #" & $(i + 1) & " to 'char' (value out of range)")
    s.add(char(code))
  return @[newLuaString(s)]

proc luaStrLen(args: varargs[LuaValue]): seq[LuaValue] =  
  if len(args) != 1:
    raise newException(LuaRuntimeError,argErrFmtNumbered("len","1"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError,kindErrFmt(1,"len","string"))
  return @[newLuaInteger(len(getString(args[0])))]

proc luaStrLower(args: varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 1:
    raise newException(LuaRuntimeError,argErrFmtNumbered("lower","1"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError,kindErrFmt(1,"lower","string"))
  return @[newLuaString(toLowerAscii(getString(args[0])))]

proc luaStrRep(args: varargs[LuaValue]): seq[LuaValue] = 
  if len(args) < 2 or len(args) > 3:
    raise newException(LuaRuntimeError, argErrFmtNumbered("rep", "2 or 3"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError, kindErrFmt(1, "rep", "string"))
  if not isNumber(args[1]):
    raise newException(LuaRuntimeError, kindErrFmt(2, "rep", "number"))

  let str = getString(args[0])
  let times = int(intVal(args[1]))
  if times <= 0:
    return @[newLuaString("")]

  var sep = ""
  if len(args) == 3 and isString(args[2]):
    sep = getString(args[2])

  # Check BEFORE multiplying -- times * str.len could itself overflow for a
  # deliberately huge `times`, but division is always safe regardless of size.
  if str.len > 0 and times > REPEATLIMIT div str.len:
    raise newException(LuaRuntimeError, "resulting string too large")

  let strTotal = str.len * times          # safe now: bounded by the check above
  let sepTotal = sep.len * (times - 1)    # (times - 1) separators between pieces
  if strTotal + sepTotal > REPEATLIMIT:
    raise newException(LuaRuntimeError, "resulting string too large")

  var s = newStringOfCap(strTotal + sepTotal)
  for i in 1 .. times:
    if i > 1: s.add(sep)
    s.add(str)
  return @[newLuaString(s)]

proc luaStrReverse(args: varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 1:
    raise newException(LuaRuntimeError,argErrFmtNumbered("reverse","1"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError,kindErrFmt(1,"reverse","string"))
  var str = getString(args[0])
  reverse(str)
  return @[newLuaString(str)]

proc luaStrUpper(args: varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 1:
    raise newException(LuaRuntimeError,argErrFmtNumbered("upper","1"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError,kindErrFmt(1,"upper","string"))
  return @[newLuaString(toUpperAscii(getString(args[0])))]  

proc luaStrSplit(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) == 0:
    raise newException(LuaRuntimeError,argErrFmtNumbered("split","1"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError,kindErrFmt(1,"split","string"))
  let str = getString(args[0])
  var sep = ","
  if len(args) == 2 and isString(args[1]):
    sep = getString(args[1])
  var tab = newLuaTable()
  var idx = 1
  for s in split(str,sep):
    tab.tval[newLuaInteger(idx)] = newLuaString(s)
    inc(idx)
  return @[tab]

proc luaStrSub(args: varargs[LuaValue]): seq[LuaValue] = 
  if len(args) < 2:
    raise newException(LuaRuntimeError,argErrFmtNumbered("sub","2 or 3"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError,kindErrFmt(1,"sub","string"))
  if not isNumber(args[1]):
    raise newException(LuaRuntimeError,kindErrFmt(2,"sub","integer or number"))
  let str = getString(args[0])
  var sPos = intVal(args[1])
  var ePos = len(str) - 1
  if sPos == -1:
    sPos = len(str) - 1
  else:
    sPos = sPos - 1
  if len(args) == 3 and isNumber(args[2]):
    ePos = intVal(args[2])
    if ePos == -1:
      ePos = len(str) - 1
    else:
      ePos = ePos - 1

  return @[newLuaString(str[sPos..ePos])]
  

proc resolveFindInit(initArg: int64, len: int): int =
  # returns a 0-based Nim start index, or -1 meaning "no match is possible"
  var i = initArg
  if i < 0:
    i = int64(len) + i + 1
    if i < 1: i = 1
  elif i == 0:
    i = 1
  if i > int64(len) + 1:
    return -1
  return int(i) - 1

proc luaStrFind*(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 2:
    raise newException(LuaRuntimeError, argErrFmtNumbered("find", "at least 2"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError, kindErrFmt(1, "find", "string"))
  if not isString(args[1]):
    raise newException(LuaRuntimeError, kindErrFmt(2, "find", "string"))

  let s = getString(args[0])
  let pat = getString(args[1])
  let initArg = if len(args) >= 3 and isNumber(args[2]): intVal(args[2]) else: 1'i64
  let plain = len(args) >= 4 and truthy(args[3])   # restored -- no longer hardcoded

  let startIdx = resolveFindInit(initArg, s.len)
  if startIdx == -1:
    return @[newLuaNil()]

  if plain:
    let foundIdx = s.find(pat, startIdx)
    if foundIdx == -1: return @[newLuaNil()]
    return @[newLuaInteger(foundIdx + 1), newLuaInteger(foundIdx + pat.len)]

  let (found, ms, mStart, mEnd) = findMatch(pat, s, startIdx)
  if not found: return @[newLuaNil()]
  result = @[newLuaInteger(mStart + 1), newLuaInteger(mEnd)]
  result.add(capturesToLua(ms))

proc luaStrMatch*(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 2:
    raise newException(LuaRuntimeError, argErrFmtNumbered("match", "at least 2"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError, kindErrFmt(1, "match", "string"))
  if not isString(args[1]):
    raise newException(LuaRuntimeError, kindErrFmt(2, "match", "string"))

  let s = getString(args[0])
  let pat = getString(args[1])
  let initArg = if len(args) >= 3 and isNumber(args[2]): intVal(args[2]) else: 1'i64
  let startIdx = resolveFindInit(initArg, s.len)
  if startIdx == -1:
    return @[newLuaNil()]

  let (found, ms, mStart, mEnd) = findMatch(pat, s, startIdx)
  if not found: return @[newLuaNil()]

  let caps = capturesToLua(ms)
  if caps.len == 0:
    return @[newLuaString(s[mStart ..< mEnd])]
  return caps

proc luaStrGmatch*(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 2:
    raise newException(LuaRuntimeError, argErrFmtNumbered("gmatch", "2 or 3"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError, kindErrFmt(1, "gmatch", "string"))
  if not isString(args[1]):
    raise newException(LuaRuntimeError, kindErrFmt(2, "gmatch", "string"))

  let s = getString(args[0])
  let pat = getString(args[1])
  let initArg = if len(args) >= 3 and isNumber(args[2]): intVal(args[2]) else: 1'i64
  var searchPos = resolveFindInit(initArg, s.len)
  if searchPos == -1: searchPos = s.len + 1   # past the end -- iterator reports "done" immediately

  let iterFn = proc(iterArgs: varargs[LuaValue]): seq[LuaValue] =
    if searchPos > s.len:
      return @[newLuaNil()]
    let (found, ms, mStart, mEnd) = findMatch(pat, s, searchPos)
    if not found:
      searchPos = s.len + 1   # stop any future calls from re-searching
      return @[newLuaNil()]

    # Guarantee forward progress: an empty match (mEnd == mStart) would
    # otherwise be re-found at this exact same position on every subsequent call.
    searchPos = if mEnd > mStart: mEnd else: mEnd + 1

    let caps = capturesToLua(ms)
    if caps.len == 0:
      return @[newLuaString(s[mStart ..< mEnd])]
    return caps

  return @[newNimFn(iterFn), newLuaNil(), newLuaNil()]

proc expandReplacement(repl: string, ms: MatchState, wholeMatch: string): string =
  result = ""
  var i = 0
  while i < repl.len:
    if repl[i] == '%' and i + 1 < repl.len:
      let c = repl[i + 1]
      if c == '%':
        result.add('%')
      elif c == '0':
        result.add(wholeMatch)
      elif c in '1'..'9':
        let idx = ord(c) - ord('1')
        if ms.captures.len == 0 and idx == 0:
          result.add(wholeMatch)   # no captures -- %1 falls back to the whole match
        elif idx < ms.captures.len:
          let cap = ms.captures[idx]
          if cap.len == CapPosition:
            result.add($(cap.start + 1))
          else:
            result.add(ms.subject[cap.start ..< cap.start + cap.len])
        else:
          raise newException(LuaRuntimeError, "invalid capture index %" & $c)
      else:
        raise newException(LuaRuntimeError, "invalid use of '%' in replacement string")
      i += 2
    else:
      result.add(repl[i])
      inc i

proc luaStrGsub*(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 3:
    raise newException(LuaRuntimeError, argErrFmtNumbered("gsub", "3 or 4"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError, kindErrFmt(1, "gsub", "string"))
  if not isString(args[1]):
    raise newException(LuaRuntimeError, kindErrFmt(2, "gsub", "string"))
  let replArg = args[2]
  if not (isString(replArg) or isTable(replArg) or isCallable(replArg)):
    raise newException(LuaRuntimeError, kindErrFmt(3, "gsub", "string, table, or function"))

  let s = getString(args[0])
  let pat = getString(args[1])
  let maxN = if len(args) >= 4 and isNumber(args[3]): int(intVal(args[3])) else: int.high

  var output = ""
  var searchPos = 0
  var count = 0

  while searchPos <= s.len and count < maxN:
    let (found, ms, mStart, mEnd) = findMatch(pat, s, searchPos)
    if not found: break

    output.add(s[searchPos ..< mStart])   # whatever was skipped to reach this match
    let wholeMatch = s[mStart ..< mEnd]
    let capVals = capturesToLua(ms)
    # No explicit captures -> the whole match plays capture #1's role,
    # same convention find/match/gmatch already use via capturesToLua.
    let callArgs = if capVals.len == 0: @[newLuaString(wholeMatch)] else: capVals

    if isString(replArg):
      output.add(expandReplacement(replArg.sval, ms, wholeMatch))
    elif isTable(replArg):
      # Table replacement only ever uses the FIRST capture (or whole match) as a key --
      # unlike function replacement, which gets every capture as a separate argument.
      let key = callArgs[0]
      if replArg.tval.hasKey(key) and truthy(replArg.tval[key]):
        let val = replArg.tval[key]
        if not isString(val):
          raise newException(LuaRuntimeError, "invalid replacement value (a " & $val.kind & ")")
        output.add(val.sval)
      else:
        output.add(wholeMatch)   # nil/false/absent -> keep the original text
    else:   # function
      let results = vm.callMetamethod(replArg, 1, callArgs)
      if not truthy(results[0]):
        output.add(wholeMatch)   # nil/false return -> keep the original text
      else:
        if not isString(results[0]):
          raise newException(LuaRuntimeError, "invalid replacement value (a " & $results[0].kind & ")")
        output.add(results[0].sval)

    inc count

    # Same forward-progress guarantee gmatch needed: a zero-length match
    # must still copy over the one character it's sitting on and step past
    # it, or the next iteration would find the identical match forever.
    if mEnd == mStart:
      if mStart < s.len: output.add(s[mStart])
      searchPos = mStart + 1
    else:
      searchPos = mEnd

  if searchPos <= s.len:
    output.add(s[searchPos ..< s.len])   # whatever's left after the last match (or no match at all)

  return @[newLuaString(output), newLuaInteger(count)]

type
  FmtSpec = object
    leftAlign: bool
    plusSign: bool
    spaceSign: bool
    altForm: bool
    zeroPad: bool
    width: int
    precision: int      # -1 == unspecified
    conv: char
 
proc fmtPad(s: string, spec: FmtSpec, allowZeroPad: bool): string =
  if spec.width <= s.len: return s
  let fill = spec.width - s.len
  if spec.leftAlign:
    return s & repeat(' ', fill)
  if allowZeroPad:
    # zero padding goes AFTER any sign or 0x prefix
    var signLen = 0
    if s.len > 0 and (s[0] == '-' or s[0] == '+' or s[0] == ' '):
      signLen = 1
    if s.len >= signLen + 2 and s[signLen] == '0' and
       (s.len > signLen + 1 and (s[signLen + 1] == 'x' or s[signLen + 1] == 'X')):
      signLen += 2
    return s[0 ..< signLen] & repeat('0', fill) & s[signLen .. ^1]
  return repeat(' ', fill) & s
 
proc fmtApplySign(body: string, negative: bool, spec: FmtSpec): string =
  if negative: return "-" & body
  if spec.plusSign: return "+" & body
  if spec.spaceSign: return " " & body
  return body
 
proc fmtInt(v: int64, spec: FmtSpec): string =
  var digits: string
  var negative = false
  case spec.conv
  of 'd', 'i':
    negative = v < 0
    # abs() overflows on low(int64); go through unsigned instead
    digits = if negative: $(uint64(0) - uint64(v)) else: $uint64(v)
  of 'u':
    digits = $uint64(v)
  of 'x':
    digits = toLowerAscii(toHex(uint64(v)).strip(chars = {'0'}, trailing = false))
    if digits.len == 0: digits = "0"
  of 'X':
    digits = toHex(uint64(v)).strip(chars = {'0'}, trailing = false)
    if digits.len == 0: digits = "0"
  of 'o':
    var u = uint64(v)
    if u == 0'u64:
      digits = "0"
    else:
      digits = ""
      while u > 0'u64:
        digits = $chr(ord('0') + int(u mod 8'u64)) & digits
        u = u div 8'u64
  of 'c':
    return fmtPad($char(v), spec, false)
  else:
    digits = $v
 
  if spec.precision >= 0 and digits.len < spec.precision:
    digits = repeat('0', spec.precision - digits.len) & digits
  if spec.altForm:
    case spec.conv
    of 'x':
      if digits != "0": digits = "0x" & digits
    of 'X':
      if digits != "0": digits = "0X" & digits
    of 'o':
      if not digits.startsWith("0"): digits = "0" & digits
    else: discard
 
  # C ignores the '0' flag for integer conversions when a precision
  # is given, so allow zero padding only when precision is unset.
  result = fmtPad(fmtApplySign(digits, negative, spec), spec,
                  spec.zeroPad and spec.precision < 0)
 
proc fmtTrimGZeros(s: string): string =
  ## %g drops trailing fractional zeros (and a bare trailing '.').
  if not ('.' in s): return s
  var mantissa = s
  var exponent = ""
  for i, ch in s:
    if ch == 'e' or ch == 'E':
      mantissa = s[0 ..< i]
      exponent = s[i .. ^1]
      break
  mantissa = mantissa.strip(chars = {'0'}, leading = false)
  if mantissa.endsWith("."): mantissa = mantissa[0 ..< ^1]
  return mantissa & exponent
 
proc fmtHexDigitChar(d: int): char =
  if d < 10: chr(ord('0') + d) else: chr(ord('a') + d - 10)
 
proc fmtHexFloat(v: float64, spec: FmtSpec): string =
  ## C's %a: hexadecimal floating point, e.g. 3.14159 -> 0x1.921f9f01b866ep+1.
  ## Note this is NOT the hex of the value's bytes -- it's a normalised
  ## 1.f mantissa in hex with a binary exponent, so it needs frexp
  ## rather than toHex.
  let negative = v < 0 or (v == 0.0 and 1.0 / v < 0)
  let a = abs(v)
  var body: string
 
  if a.classify == fcNan:
    body = "nan"
    return fmtPad(fmtApplySign(body, false, spec), spec, false)
  if a.classify == fcInf:
    body = "inf"
    return fmtPad(fmtApplySign(body, negative, spec), spec, false)
 
  if a == 0.0:
    body = "0x0"
    if spec.precision > 0:
      body.add("." & repeat('0', spec.precision))
    body.add("p+0")
  else:
    # frexp gives a = m * 2^e with 0.5 <= m < 1; C's %a normalises to
    # 1.f * 2^e instead, so double the mantissa and drop the exponent.
    var (m, e) = frexp(a)
    m = m * 2.0
    e = e - 1
 
    let intPart = int(m)
    var frac = m - float64(intPart)
 
    var digits = ""
    if spec.precision >= 0:
      for _ in 0 ..< spec.precision:
        frac = frac * 16.0
        let d = int(frac)
        digits.add(fmtHexDigitChar(d))
        frac = frac - float64(d)
      # round half up on whatever mantissa is left over
      if frac * 16.0 >= 8.0:
        var carried = digits
        var k = carried.len - 1
        var carry = true
        while k >= 0 and carry:
          var dv = if carried[k] <= '9': ord(carried[k]) - ord('0')
                   else: ord(carried[k]) - ord('a') + 10
          dv.inc
          if dv == 16:
            dv = 0
          else:
            carry = false
          carried[k] = fmtHexDigitChar(dv)
          k.dec
        digits = carried
    else:
      # 52 mantissa bits / 4 == 13 hex digits is exact for a double
      for _ in 0 ..< 13:
        frac = frac * 16.0
        let d = int(frac)
        digits.add(fmtHexDigitChar(d))
        frac = frac - float64(d)
      digits = digits.strip(chars = {'0'}, leading = false)
 
    body = "0x" & $intPart
    if digits.len > 0: body.add("." & digits)
    body.add("p" & (if e >= 0: "+" else: "-") & $abs(e))
 
  if spec.conv == 'A': body = toUpperAscii(body)
  result = fmtPad(fmtApplySign(body, negative, spec), spec, spec.zeroPad)
 
proc fmtFloat(v: float64, spec: FmtSpec): string =
  let negative = v < 0 or (v == 0.0 and 1.0 / v < 0)
  let a = abs(v)
  var body: string
 
  if a.classify == fcNan:
    return fmtPad(fmtApplySign("nan", false, spec), spec, false)
  if a.classify == fcInf:
    return fmtPad(fmtApplySign("inf", negative, spec), spec, false)
 
  let prec = if spec.precision < 0: 6 else: spec.precision
  case spec.conv
  of 'f', 'F':
    body = formatFloat(a, ffDecimal, prec)
    # Nim leaves a bare trailing '.' at precision 0; C does not.
    if not spec.altForm and body.endsWith("."): body = body[0 ..< ^1]
  of 'e', 'E':
    body = formatFloat(a, ffScientific, prec)
    if spec.conv == 'E': body = toUpperAscii(body)
  of 'g', 'G':
    let p = if prec == 0: 1 else: prec
    # C's %g picks %e when the exponent is < -4 or >= precision
    var expn = 0
    if a != 0.0: expn = int(floor(log10(a)))
    if expn < -4 or expn >= p:
      body = formatFloat(a, ffScientific, p - 1)
    else:
      body = formatFloat(a, ffDecimal, p - 1 - expn)
    if not spec.altForm: body = fmtTrimGZeros(body)
    if spec.conv == 'G': body = toUpperAscii(body)
  else:
    body = formatFloat(a, ffDecimal, prec)
 
  result = fmtPad(fmtApplySign(body, negative, spec), spec, spec.zeroPad)
 
proc fmtQuote(s: string): string =
  result = "\""
  for ch in s:
    case ch
    of '"': result.add("\\\"")
    of '\\': result.add("\\\\")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\0': result.add("\\0")
    of '\t': result.add("\\t")
    else:
      if ch.ord < 32 or ch.ord == 127:
        result.add("\\" & $ch.ord)
      else:
        result.add(ch)
  result.add("\"")
 
proc luaStrFormat*(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 1:
    raise newException(LuaRuntimeError, argErrFmtNumbered("format", "at least 1"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError, kindErrFmt(1, "format", "string"))
 
  let f = getString(args[0])
  let argSeq = @args
  var output = ""
  var argIdx = 1          # args[0] is the format string itself
  var i = 0
 
  proc takeArg(): LuaValue =
    if argIdx >= argSeq.len:
      raise newException(LuaRuntimeError,
        "bad argument #" & $(argIdx + 1) & " to 'format' (no value)")
    result = argSeq[argIdx]
    argIdx.inc
 
  while i < f.len:
    if f[i] != '%':
      output.add(f[i])
      i.inc
      continue
 
    i.inc                              # step past '%'
    if i < f.len and f[i] == '%':
      output.add('%')
      i.inc
      continue
 
    var spec = FmtSpec(width: 0, precision: -1)
 
    # flags
    while i < f.len:
      case f[i]
      of '-': spec.leftAlign = true
      of '+': spec.plusSign = true
      of ' ': spec.spaceSign = true
      of '#': spec.altForm = true
      of '0': spec.zeroPad = true
      else: break
      i.inc
 
    # width
    while i < f.len and f[i].isDigit:
      spec.width = spec.width * 10 + (ord(f[i]) - ord('0'))
      i.inc
 
    # precision
    if i < f.len and f[i] == '.':
      i.inc
      spec.precision = 0
      while i < f.len and f[i].isDigit:
        spec.precision = spec.precision * 10 + (ord(f[i]) - ord('0'))
        i.inc
 
    if i >= f.len:
      raise newException(LuaRuntimeError, "invalid conversion '%' to 'format'")
    spec.conv = f[i]
    i.inc
 
    case spec.conv
    of 'd', 'i', 'u', 'c', 'x', 'X', 'o':
      let v = takeArg()
      if not isNumber(v):
        raise newException(LuaRuntimeError, kindErrFmt(argIdx, "format", "number"))
      output.add(fmtInt(intVal(v), spec))
    of 'f', 'F', 'e', 'E', 'g', 'G':
      let v = takeArg()
      if not isNumber(v):
        raise newException(LuaRuntimeError, kindErrFmt(argIdx, "format", "number"))
      output.add(fmtFloat(numVal(v), spec))
    of 'a', 'A':
      let v = takeArg()
      if not isNumber(v):
        raise newException(LuaRuntimeError, kindErrFmt(argIdx, "format", "number"))
      output.add(fmtHexFloat(numVal(v), spec))
    of 's':
      let v = takeArg()
      # honor __tostring, the way real Lua's format does
      var s: string
      if hasMetaKey(v, MTTOSTR):
        let handler = v.mt.tval[MTTOSTR]
        let res = vm.callMetamethod(handler, 1, v)
        s = if res.len > 0: $res[0] else: "nil"
      else:
        s = $v
      if spec.precision >= 0 and s.len > spec.precision:
        s = s[0 ..< spec.precision]
      output.add(fmtPad(s, spec, false))
    of 'q':
      let v = takeArg()
      if isString(v):
        output.add(fmtQuote(getString(v)))
      else:
        output.add($v)
    else:
      raise newException(LuaRuntimeError,
        "invalid conversion '%" & $spec.conv & "' to 'format'")
 
  return @[newLuaString(output)]

proc newStringLib*(): LuaValue = 
  result = newLuaTable()
  result.tval[newLuaString("byte")] = newNimFn(luaStrByte)
  result.tval[newLuaString("char")] = newNimFn(luaStrChar)
  result.tval[newLuaString("len")] = newNimFn(luaStrLen)
  result.tval[newLuaString("lower")] = newNimFn(luaStrLower)
  result.tval[newLuaString("rep")] = newNimFn(luaStrRep)
  result.tval[newLuaString("reverse")] = newNimFn(luaStrReverse)
  result.tval[newLuaString("upper")] = newNimFn(luaStrUpper)
  result.tval[newLuaString("find")] = newNimFn(luaStrFind)
  result.tval[newLuaString("match")] = newNimFn(luaStrMatch)
  result.tval[newLuaString("gmatch")] = newNimFn(luaStrGmatch)
  result.tval[newLuaString("gsub")] = newNimFnVM(luaStrGSub)
  result.tval[newLuaString("sub")] = newNimFn(luaStrSub)
  result.tval[newLuaString("split")] = newNimFn(luaStrSplit)
  result.tval[newLuaString("format")] = newNimFnVM(luaStrFormat)