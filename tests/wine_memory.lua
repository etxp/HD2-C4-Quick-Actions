-- OFFLINE ONLY. Private standalone host allocates ordinary read/write pages
-- holding invented fixture data. No game process, executable pages or hooks.
local ffi=require('ffi')
assert(ffi.os=='Windows','offline_windows_host_required')
ffi.cdef[[
void *VirtualAlloc(void *,size_t,unsigned long,unsigned long);
void *GetCurrentProcess(void);
int ReadProcessMemory(void *,const void *,void *,size_t,size_t *);
]]
local kernel=ffi.load('kernel32')
return function(s,k,image)
    local pages={}
    local function put(at,b)
        for page=math.floor(at/65536)*65536,at+#b-1,65536 do
            if not pages[page] then
                local p=kernel.VirtualAlloc(ffi.cast('void *',page),65536,0x3000,0x04)
                assert(p~=nil and tonumber(ffi.cast('uintptr_t',p))==page,'fixture_address_unavailable')
                pages[page]=p
            end
        end
        ffi.copy(ffi.cast('void *',at),b,#b)
    end
    put(s.game,image)
    for at,byte in pairs(s.memory) do
        if at~=s.signature and at~=s.signature+1 then put(at,byte) end
    end
    local oldput=s.put
    s.put=function(at,b) oldput(at,b);put(at,b) end
    k.ReadProcessMemory=kernel.ReadProcessMemory
    local process=kernel.GetCurrentProcess()
    local out,count=ffi.new('uint8_t[4096]'),ffi.new('size_t[1]')
    s.api.read=function(at,n)
        assert(n>0 and n<=4096)
        if kernel.ReadProcessMemory(process,ffi.cast('void *',at),out,n,count)==0 then return nil end
        return ffi.string(out,n)
    end
end
