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
proc checkruntime*(cond:bool,msg:string) = luacheck(cond,LuaSyntaxError,msg)
proc checkcompile*(cond:bool,msg:string) = luacheck(cond,LuaSyntaxError,msg)

proc moduleArgKindErrorFmt*(pos:int,fnName,kind:string): string = "bad argument #" & $pos & " to '" & fnName & "' (" & kind & " expected)"
proc moduleArgKindsErrorFmt*(pos:int,fnName:string,kinds:openArray[string]): string = "bad argument #" & $pos & " to '" & fnName & "' (" & kinds.join(",") & " expected)"
proc moduleArgNumErrorFmt*(fnName:string,args:varargs[string]): string = "invalid # of arguments to '" & fnName & "'. (" & args.join(" and ") & " expected)"