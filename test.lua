local proto = {}
proto.f = function(a, b) print(a, b) end
local t = setmetatable({}, {__index = proto})

t.f("x")   -- x            nil
t:f("x")   -- table: 0x..  x