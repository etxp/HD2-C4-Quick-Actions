-- Foreground ownership only; does not read or synthesize OS input events.
return function()
    local ffi=require('ffi')
    ffi.cdef [[
        uint32_t GetCurrentProcessId(void);
        void *GetForegroundWindow(void);
        uint32_t GetWindowThreadProcessId(void *,uint32_t *);
    ]]
    local k,u=ffi.load('kernel32'),ffi.load('user32')
    local pid=k.GetCurrentProcessId()
    return function()
        local window=u.GetForegroundWindow()
        if window==nil then return false end
        local owner=ffi.new('uint32_t[1]')
        return u.GetWindowThreadProcessId(window,owner)~=0 and owner[0]==pid
    end
end
