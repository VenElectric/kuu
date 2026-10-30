import std/[streams, macros]
from std/terminal import Style, ForegroundColor, BackgroundColor,
                         ansiStyleCode, ansiForegroundColorCode, ansiResetCode
import ./ltypes

export Style, ForegroundColor, BackgroundColor

proc emit(vm: var VM, code: string) {.inline.} =
  if vm.useColor: vm.output.write(code)

proc styledArg*(vm: var VM, s: string)         = vm.output.write(s)
proc styledArg*(vm: var VM, st: Style)         = vm.emit(ansiStyleCode(st))
proc styledArg*(vm: var VM, sts: set[Style])   = (for st in sts: vm.emit(ansiStyleCode(st)))
proc styledArg*(vm: var VM, fg: ForegroundColor) = vm.emit(ansiForegroundColorCode(fg))
proc styledArg*(vm: var VM, bg: BackgroundColor) = vm.emit(ansiStyleCode(bg.int))

proc writeReset*(vm: var VM) = vm.emit(ansiResetCode)

macro styledWrite*(vm: typed, args: varargs[typed]): untyped =
  ## Mirrors terminal.styledWrite, but targets vm.output.
  result = newStmtList()
  for a in args:
    result.add newCall(bindSym"styledArg", vm, a)
  result.add newCall(bindSym"writeReset", vm)

template styledWriteLine*(vm: var VM, args: varargs[untyped]) =
  styledWrite(vm, args)
  vm.output.write("\n")