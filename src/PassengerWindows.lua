-- One data byte in a freshly identity-checked local passenger relation.
-- Protection and executable memory APIs are deliberately unavailable here.
return function(api)
    local ffi=require('ffi')
    local k=ffi.load('kernel32');local process=k.GetCurrentProcess()
    function api.passenger_exchange(address,expected,value)
        assert(type(address)=='number' and address>=65536 and address+64<0x800000000000
            and address%8==0 and type(expected)=='string' and #expected==64,'passenger_write_bounds')
        assert((value==0 or value==1) and expected:byte(0x31)==1-value
            and expected:byte(0x32)==1,'passenger_write_transition')
        assert(ContextReader.u32(expected,8)==3 and ContextReader.u32(expected,0x1c)~=0xffffffff
            and ContextReader.u32(expected,0x18)==0xffffffff
            and ContextReader.u32(expected,0x20)==0xffffffff,'passenger_write_not_idle_passenger')
        if api.read(address,64)~=expected then return false,'passenger_write_compare_failed' end
        local count=ffi.new('size_t[1]');local byte=string.char(value)
        if k.WriteProcessMemory(process,ffi.cast('void *',address+0x30),byte,1,count)==0
            or tonumber(count[0])~=1 then return false,'passenger_write_failed' end
        return api.read(address,64)==expected:sub(1,0x30)..byte..expected:sub(0x32),'passenger_write_readback'
    end
    return api
end
