-- Data-only compare/write. Call sites restrict addresses to verified C4 label
-- fields or signature-resolved writable cache slots; never change protection.
return function(api)
    local ffi=require('ffi');local k=ffi.load('kernel32');local process=k.GetCurrentProcess()
    local pinned={}
    return {
        text=function(text)
            local buffer=ffi.new('char[?]',#text+1,text);pinned[#pinned+1]=buffer
            local pointer=ffi.new('uintptr_t[1]',ffi.cast('uintptr_t',buffer))
            return {buffer=buffer,bytes=ffi.string(pointer,8)}
        end,
        exchange=function(at,expected,value)
            assert(type(at)=='number' and at>=65536 and at+#value<0x800000000000 and
                (#value==4 or #value==8) and #expected==#value and at%#value==0,'mode_label_write_bounds')
            if api.read(at,#expected)~=expected then return false end
            local count=ffi.new('size_t[1]')
            if k.WriteProcessMemory(process,ffi.cast('void *',at),value,#value,count)==0 or
                tonumber(count[0])~=#value then return false end
            return api.read(at,#value)==value
        end
    }
end
