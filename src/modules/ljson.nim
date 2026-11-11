import std/[tables,json]
import ../lvalue,../ltypes,../lutil,../lerror




proc luaLoadJson(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 1 or len(args) > 1:
    raise newException(LuaRuntimeError,argErrFmtNumbered("loadjson","1"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError,kindErrFmt(1,"loadjson","string"))
  try:
    return @[toLua(parseJson(getString(args[0])))]
  except IOError, OSError, JsonParsingError, ValueError:
    let e = getCurrentException()
    raise newException(LuaRuntimeError,"Unable to parse json: (" & e.msg & ")")

proc luaToJson(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 1 or len(args) > 1:
    raise newException(LuaRuntimeError,argErrFmtNumbered("tojson","1"))
  if not isTable(args[0]):
    raise newException(LuaRuntimeError,kindErrFmt(1,"tojson","table"))
  
  return @[newLuaString($(%args[0]))]

proc newJsonLib*(): LuaValue = 
  result = newLuaTable()
  result.tval[newLuaString("loadjson")] = newNimFn(luaLoadJson)
  result.tval[newLuaString("tojson")] = newNimFn(luaToJson)
  