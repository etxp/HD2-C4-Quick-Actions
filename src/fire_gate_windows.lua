-- The only EXP04 memory write: one byte of the selected, identity-checked
-- C4 Weapon flags. No executable pages, mode, ammo, or animation state writes.
return function(api)
    local ffi=require('ffi')
    assert(ffi.os=='Windows' and ffi.abi('64bit'),'windows_x64_required')
    ffi.cdef [[int WriteProcessMemory(void *,void *,const void *,size_t,size_t *);]]
    local k=ffi.load('kernel32')
    local process=k.GetCurrentProcess()
    function api.fire_gate_exchange(flags_address,before,after)
        assert(type(flags_address)=='number' and flags_address>=65536
            and flags_address+4<0x800000000000 and flags_address%4==0,'invalid_fire_gate_address')
        assert((before==0x1148 and after==0x148) or (before==0x148 and after==0x1148),
            'invalid_fire_gate_transition')
        local expected=before==0x1148 and '\72\17\0\0' or '\72\1\0\0'
        local target=after==0x1148 and '\17' or '\1'
        if api.read(flags_address,4)~=expected then return false,'fire_gate_compare_failed' end
        local count=ffi.new('size_t[1]')
        if k.WriteProcessMemory(process,ffi.cast('void *',flags_address+1),target,1,count)==0
            or tonumber(count[0])~=1 then return false,'fire_gate_write_failed' end
        local wanted=after==0x1148 and '\72\17\0\0' or '\72\1\0\0'
        return api.read(flags_address,4)==wanted,'fire_gate_readback'
    end
    return api
end
