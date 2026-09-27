-- Indices are paired with native flag-reader signatures in the compatibility catalog.
local M={}
function M.has(bytes,index)
    assert(type(index)=='number' and index>=0 and index<192,'invalid_avatar_flag')
    local byte=assert(bytes:byte(math.floor(index/8)+1),'short_avatar_flags')
    return math.floor(byte/2^(index%8))%2==1
end
return M

