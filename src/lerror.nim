from strutils import join

type
  LuaError = object of CatchableError
  LuaSyntaxError* = object of LuaError
  LuaCompileError* = object of LuaError
  LuaRuntimeError* = object of LuaError
    line*: int
  LuaExitError* = object of LuaError
    code*: int


proc luacheck*(cond:bool,exc:typedesc[LuaError],msg:string) =
  if cond:
    raise newException(exc,msg)

proc checksyntax*(cond:bool,msg:string) = luacheck(cond,LuaSyntaxError,msg)
proc checkruntime*(cond:bool,msg:string) = luacheck(cond,LuaRuntimeError,msg)
proc checkcompile*(cond:bool,msg:string) = luacheck(cond,LuaCompileError,msg)

proc kindErrFmt*(pos:int,fnName,kind:string): string = "bad argument #" & $pos & " to '" & fnName & "' (" & kind & " expected)"
# proc kindsErrFmt*(fnName:string,kinds:openArray[string]): string = "Incorrect number of arguments to " & fnName & ".(" & kinds.join(",") & " expected)"
proc numArgErrFmt*(fnName:string,args:varargs[string]): string = "invalid # of arguments to '" & fnName & "'. (" & args.join(" and ") & " expected)"
proc argErrFmtNumbered*(fnName:string,numArgs:Natural): string = "invalid # of arguments to '" & fnName & "'. " & $numArgs & " values expected"
proc argErrFmtNumbered*(fnName,numArgs:string): string = "invalid # of arguments to '" & fnName & "'. " & $numArgs & " values expected"


# moduleArgKindErrorFmt
# moduleArgNumErrorFmt