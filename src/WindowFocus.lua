-- Foreground ownership only; does not read or synthesize OS input events.
return function()
    local ffi=require('ffi')
    local k,u=WinApi.load()
    local pid=k.c4qa_GetCurrentProcessId()
    return function()
        local window=u.c4qa_GetForegroundWindow()
        if window==nil then return false end
        local owner=ffi.new('uint32_t[1]')
        return u.c4qa_GetWindowThreadProcessId(window,owner)~=0 and owner[0]==pid
    end
end

