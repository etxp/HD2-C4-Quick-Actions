-- No code patch, mode write, input injection, or direct spawn/explosion call.
return function(game)
    local ffi=require('ffi')
    assert(ffi.os=='Windows' and ffi.abi('64bit'),'windows_x64_required')
    local start=ffi.cast('void (*)(void *, uint32_t, uint32_t, uint32_t, float)',game+R.fn_start)
    local consume=ffi.cast('void (*)(void *, uint32_t)',game+R.fn_consume)
    local count=ffi.cast('int32_t (*)(void *, uint32_t)',game+R.fn_count)
    local after=ffi.cast('void (*)(void *, uint32_t, int32_t, bool)',game+R.fn_after)
    local lean=ffi.cast('void (*)(void *, uint32_t)',game+R.fn_lean)
    local reload=ffi.cast('void (*)(void *, uint32_t, bool)',game+R.fn_reload)
    local reload_eligible=ffi.cast('bool (*)(void *, uint32_t, bool, bool)',game+R.fn_reload_eligible)
    local input_mapping=ffi.cast('void *(*)(void *, uint64_t, bool)',game+R.fn_input_mapping)
    local input_inhibit=ffi.cast('void (*)(void *, uint64_t, uint32_t, float)',game+R.fn_input_inhibit)
    local input_unblock=ffi.cast('void (*)(void *, uint64_t)',game+R.fn_input_unblock)
    return {
        input_mapping=function(manager,action)
            return tonumber(ffi.cast('uintptr_t',input_mapping(ffi.cast('void *',manager),action,true)))
        end,
        input_inhibit=function(manager,action) input_inhibit(ffi.cast('void *',manager),action,1,-1.0) end,
        input_unblock=function(manager,action) input_unblock(ffi.cast('void *',manager),action) end,
        reload=function(manager,id) reload(ffi.cast('void *',manager),id,false) end,
        reload_eligible=function(manager,id)
            return reload_eligible(ffi.cast('void *',manager),id,false,false)
        end,
        lean=function(manager,id) lean(ffi.cast('void *',manager),id) end,
        start=function(manager,id,ability,network,speed)
            start(ffi.cast('void *',manager),id,ability,network,speed)
        end,
        consume=function(manager,id) consume(ffi.cast('void *',manager),id) end,
        count=function(manager,id) return tonumber(count(ffi.cast('void *',manager),id)) end,
        after=function(manager,id,n,enabled) after(ffi.cast('void *',manager),id,n,enabled) end
    }
end
