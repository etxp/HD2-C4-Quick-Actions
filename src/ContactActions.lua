-- Native ABI follows the original projectile impact branch. No new explosion
-- implementation, instruction patch, shared projectile template or ammo write.
return function(game,symbols)
    local ffi=require('ffi')
    assert(ffi.os=='Windows' and ffi.abi('64bit'),'windows_x64_required')
    local explode=ffi.cast('void (*)(void *, uint32_t, uint32_t, void *)',
        game+assert(symbols.contact_explode))
    local remote=ffi.cast('void (*)(void *, uint32_t)',game+assert(symbols.contact_remote_owner))
    return {
        explode=function(cap)explode(ffi.cast('void *',cap.manager),cap.id,cap.invalid_source,nil)end,
        remote=function(manager,weapon_id)remote(ffi.cast('void *',manager),weapon_id)end
    }
end
