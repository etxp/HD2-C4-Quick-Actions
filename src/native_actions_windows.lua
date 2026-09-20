-- Windows x64 ABI, verified against 0x7cd310's original call sites.
-- No code patch, mode write, input injection, or direct spawn/explosion call.
return function(game)
    local ffi=require('ffi')
    assert(ffi.os=='Windows' and ffi.abi('64bit'),'windows_x64_required')
    local start=ffi.cast('void (*)(void *, uint32_t, uint32_t, uint32_t, float)',game+0x7c21a0)
    local consume=ffi.cast('void (*)(void *, uint32_t)',game+0x73ca00)
    local count=ffi.cast('int32_t (*)(void *, uint32_t)',game+0x73bf20)
    local after=ffi.cast('void (*)(void *, uint32_t, int32_t, bool)',game+0x74b220)
    return {
        start=function(manager,id,ability,network,speed)
            start(ffi.cast('void *',manager),id,ability,network,speed)
        end,
        consume=function(manager,id) consume(ffi.cast('void *',manager),id) end,
        count=function(manager,id) return tonumber(count(ffi.cast('void *',manager),id)) end,
        after=function(manager,id,n,enabled) after(ffi.cast('void *',manager),id,n,enabled) end
    }
end
