-- Windows declarations shared with other mods. Run in the game's LuaJIT under
-- a Windows host (scripts/check_wine.py); it calls the real kernel32/user32 on
-- this process's own memory only.
--   arg[1]  folder of the modules under test (default src)
--   arg[2]  'hostile': another mod declared these Windows functions first,
--           with other prototypes (the first ffi.cdef of a name wins)
--           'loader':  only the six plain declarations of Bingus Shared Loader
--           v18/v19 come first
--           'none':    nothing is declared before this addon
local SRC=arg[1] or 'src'
local MODE=arg[2] or 'none'
local ffi=require('ffi')
assert(ffi.os=='Windows' and ffi.abi('64bit'),'run this under the Windows host')
local function check(name,fn)fn();print('PASS '..name)end

-- Bingus Shared Loader v18/v19 declares exactly these plain names for other mods.
ffi.cdef[[
int CreateDirectoryA(const char *path, void *security);
uint32_t GetLastError(void);
uint32_t GetModuleFileNameA(void *module, char *filename, uint32_t size);
void *FindFirstFileA(const char *pattern, void *data);
int FindNextFileA(void *handle, void *data);
int FindClose(void *handle);
]]
if MODE=='hostile' then
    -- Plausible declarations from other mods, all different from this
    -- addon's: 32-bit DWORD sizes, HANDLE as an integer, a textbook struct.
    ffi.cdef[[
    typedef struct { void *BaseAddress; void *AllocationBase; uint32_t AllocationProtect;
                     size_t RegionSize; uint32_t State; uint32_t Protect; uint32_t Type; } MEMORY_BASIC_INFORMATION;
    size_t VirtualQuery(const void *address, MEMORY_BASIC_INFORMATION *info, size_t length);
    int ReadProcessMemory(intptr_t process, const void *address, void *buffer, uint32_t size, uint32_t *read);
    int WriteProcessMemory(intptr_t process, void *address, const void *buffer, uint32_t size, uint32_t *written);
    intptr_t GetCurrentProcess(void);
    int GetCurrentProcessId(void);
    void *GetModuleHandleA(const char *name, int unused);
    uint32_t GetTickCount64(void);
    intptr_t GetForegroundWindow(void);
    uint32_t GetWindowThreadProcessId(intptr_t window, uint32_t *process);
    ]]
end

-- The runtime's modules see each other as upvalues; here they are globals.
_G.D={fire_normal=0x2148,fire_muted=0x148}
_G.ContextReader={u32=function(b,o)local a,c,d,e=b:byte(o+1,o+4);return a+c*256+d*65536+e*16777216 end}
_G.PointerValue=dofile(SRC..'/PointerValue.lua')
local f=io.open(SRC..'/WinApi.lua')
if f then f:close();_G.WinApi=dofile(SRC..'/WinApi.lua') end
local WindowsRead=dofile(SRC..'/WindowsRead.lua')
local FireGateWindows=dofile(SRC..'/FireGateWindows.lua')
local PassengerWindows=dofile(SRC..'/PassengerWindows.lua')
local ModeLabelWindows=dofile(SRC..'/ModeLabelWindows.lua')
local WindowFocus=dofile(SRC..'/WindowFocus.lua')

local api
check('reads, the module handle and the clock work through the real kernel32 ('..MODE..')',function()
    api=PassengerWindows(FireGateWindows(WindowsRead()))
    local block=ffi.new('uint8_t[4096]');for i=0,4095 do block[i]=i%251 end
    local at=tonumber(ffi.cast('uintptr_t',block))
    assert(api.read(at,4096)==ffi.string(block,4096),'read returned other bytes')
    assert(api.read(at+17,8)==ffi.string(block+17,8))
    assert(api.module('kernel32.dll'),'module handle missing')
    assert(api.module('no-such-module-c4qa.dll')==nil)
    assert(api.time()>0)
    assert(api.read(0x7ff012340000,8)==nil,'an unmapped page was readable')
end)
check('the Fire flag exchange writes exactly one byte of its own buffer',function()
    local flags=ffi.new('uint8_t[8]',{0x48,0x21,0,0,0xaa,0xbb,0xcc,0xdd})
    local at=tonumber(ffi.cast('uintptr_t',flags))
    local ok=api.fire_gate_exchange(at,D.fire_normal,D.fire_muted)
    assert(ok and flags[1]==0x01 and flags[0]==0x48 and flags[4]==0xaa and flags[7]==0xdd)
    ok=api.fire_gate_exchange(at,D.fire_muted,D.fire_normal)
    assert(ok and flags[1]==0x21)
    local refused=api.fire_gate_exchange(at,D.fire_muted,D.fire_normal)
    assert(not refused,'exchange ignored a changed source')
end)
check('the passenger exchange writes exactly its lean byte',function()
    local row=ffi.new('uint8_t[72]')
    local function u32(o,v)for i=0,3 do row[o+i]=math.floor(v/256^i)%256 end end
    u32(8,3);u32(0x1c,2);u32(0x18,0xffffffff);u32(0x20,0xffffffff);row[0x31]=1
    local base=tonumber(ffi.cast('uintptr_t',row));local at=base+(8-base%8)%8
    local expected=ffi.string(ffi.cast('uint8_t *',at),64)
    assert(api.passenger_exchange(at,expected,1))
    local now=ffi.string(ffi.cast('uint8_t *',at),64)
    assert(now:byte(0x31)==1 and now:sub(1,0x30)==expected:sub(1,0x30) and now:sub(0x32)==expected:sub(0x32))
end)
check('the mode label writer compares and writes its own data only',function()
    local writer=ModeLabelWindows(api)
    local text=writer.text('MANUAL / 手動引爆');assert(#text.bytes==8)
    local slot=ffi.new('uint64_t[2]');local at=tonumber(ffi.cast('uintptr_t',slot))
    assert(writer.exchange(at,string.rep('\0',8),text.bytes))
    assert(ffi.string(slot,8)==text.bytes and slot[1]==0)
    assert(not writer.exchange(at,string.rep('\0',8),text.bytes),'exchange ignored a changed source')
end)
check('the foreground check runs',function()
    local focus=WindowFocus();local value=focus()
    assert(value==true or value==false)
end)
