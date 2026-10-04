-- Bounded OS reads only; compatibility is checked in loaded native code.
return function()
    local ffi=require('ffi')
    assert(ffi.os=='Windows' and ffi.abi('64bit'),'windows_x64_required')
    ffi.cdef [[
        void *GetModuleHandleA(const char *);
        void *GetCurrentProcess(void);
        int ReadProcessMemory(void *,const void *,void *,size_t,size_t *);
        uint64_t GetTickCount64(void);
    ]]
    local k=ffi.load('kernel32');local process=k.GetCurrentProcess();local api={}
    function api.time() return tonumber(k.GetTickCount64())/1000 end
    function api.module(name)
        local p=k.GetModuleHandleA(name)
        if p~=nil then return tonumber(ffi.cast('uintptr_t',p)) end
    end
    api.pointer=PointerValue.decode
    -- One bounded buffer for every read: its bytes are copied into the
    -- returned Lua string before the next read can start.
    local out,count=ffi.new('uint8_t[4096]'),ffi.new('size_t[1]')
    function api.read(address,size)
        assert(type(address)=='number' and address>=65536 and address+size<0x800000000000,'bad_read_address')
        assert(size>0 and size<=4096,'read_size_limit')
        if k.ReadProcessMemory(process,ffi.cast('const void *',address),out,size,count)==0
            or tonumber(count[0])~=size then return nil end
        return ffi.string(out,size)
    end
    return api
end
