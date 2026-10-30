import lvm, log, lauxlib, ltypes,lerror
import std/[logging, parseopt,strutils,appdirs,paths]
from std/terminal import isatty
from std/os import getEnv

initLogging(lvlAll)


proc main() =
  var
    p = initOptParser()
    filename = ""
    enableTrace = false

  # Parse command line arguments
  for kind, key, val in p.getopt():
    case kind
    of cmdArgument:
      filename = key
    of cmdLongOption, cmdShortOption:
      case key
      of "trace", "t":
        enableTrace = true
      of "version","v":
        echo "kuu 1.0"
        return
      else:
        discard
    of cmdEnd: discard

  if filename == "":
    echo "Usage: kuu [options] <script.lua>"
    echo "Options:"
    echo "  -t, --trace    Enable opcode instruction tracing"
    echo "  -v, --version  Get version"
    quit(1)

  let useColor = isatty(stdout) and getEnv("NO_COLOR").len == 0 and getEnv("TERM") != "dumb"
  var vm = newVm(enableTrace,useColor)
  
  if enableTrace:
    setLogFilter(lvlDebug)
  try:
    vm.executeFile(fileName)
  except LuaExitError as e:
    quit(e.code)

when isMainModule:
  main()
