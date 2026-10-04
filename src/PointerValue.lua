-- Decode only an already-copied 8-byte Lua string. Accepted addresses fit in
-- 47 bits, so every intermediate integer is exact in a Lua double.
local M={}
function M.decode(data)
    if not data or #data<8 then return nil end
    local a,b,c,d,e,f,g,h=data:byte(1,8)
    if g~=0 or h~=0 or f>=128 then return nil end
    local p=a+b*256+c*65536+d*16777216+e*4294967296+f*1099511627776
    if p>=65536 then return p end
end
return M
