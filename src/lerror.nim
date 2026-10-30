
type
  LuaError = object of CatchableError
  LuaSyntaxError* = object of LuaError
  LuaCompileError* = object of LuaError
  LuaRuntimeError* = object of LuaError
    line*: int
  LuaExitError* = object of LuaError
    code*: int


proc raiseLuaException*(cond:bool,exc:typedesc[LuaError],msg:string) =
  if cond:
    raise newException(exc,msg)