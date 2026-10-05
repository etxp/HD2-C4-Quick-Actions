-- Windows functions under this addon's own names. Every mod shares the game's
-- single LuaJIT VM, where the first ffi.cdef of a function name wins for all of
-- them, silently, even with another prototype. Private names cannot be bound to
-- another mod's plain Windows declaration; __asm__ keeps the real symbol.
-- Declaring the same text again is ignored, so reloading this module is safe.
local M={}
local DECLARATIONS=[[
    void *c4qa_GetModuleHandleA(const char *) __asm__("GetModuleHandleA");
    void *c4qa_GetCurrentProcess(void) __asm__("GetCurrentProcess");
    uint32_t c4qa_GetCurrentProcessId(void) __asm__("GetCurrentProcessId");
    uint64_t c4qa_GetTickCount64(void) __asm__("GetTickCount64");
    int c4qa_ReadProcessMemory(void *,const void *,void *,size_t,size_t *) __asm__("ReadProcessMemory");
    int c4qa_WriteProcessMemory(void *,void *,const void *,size_t,size_t *) __asm__("WriteProcessMemory");
    void *c4qa_GetForegroundWindow(void) __asm__("GetForegroundWindow");
    uint32_t c4qa_GetWindowThreadProcessId(void *,uint32_t *) __asm__("GetWindowThreadProcessId");
]]
-- kernel32 and user32 with the private names above declared.
function M.load()
    local ffi=require('ffi')
    assert(ffi.os=='Windows' and ffi.abi('64bit'),'windows_x64_required')
    ffi.cdef(DECLARATIONS)
    return ffi.load('kernel32'),ffi.load('user32')
end
return M
