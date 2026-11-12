import std/[tables,json]
import ../lvalue,../ltypes,../lutil,../lerror




proc luaLoadJson(args: varargs[LuaValue]): seq[LuaValue] =
  checkruntime(len(args) < 1 or len(args) > 1,argErrFmtNumbered("loadjson","1"))
  checkruntime(not isString(args[0]),kindErrFmt(1,"loadjson","string"))
  try:
    return @[toLua(parseJson(getString(args[0])))]
  except IOError, OSError, JsonParsingError, ValueError:
    let e = getCurrentException()
    raise newException(LuaRuntimeError,"Unable to parse json: (" & e.msg & ")")

proc luaToJson(args: varargs[LuaValue]): seq[LuaValue] =
  checkruntime(len(args) < 1 or len(args) > 1,argErrFmtNumbered("tojson","1"))
  checkruntime(not isTable(args[0]),kindErrFmt(1,"tojson","table"))
  
  return @[newLuaString($(%args[0]))]

proc newJsonLib*(): LuaValue = 
  result = newLuaTable()
  result.tval[newLuaString("loadjson")] = newNimFn(luaLoadJson)
  result.tval[newLuaString("tojson")] = newNimFn(luaToJson)
  