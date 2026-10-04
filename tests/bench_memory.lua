-- Benchmarks only. Builds synthetic C-backed pages; never reads game memory.
local ffi=require('ffi')
ffi.cdef[[
void qa_reset(void);
void qa_page_mode(int);
void qa_put(uintptr_t, const void *, size_t);
int qa_read(void *, const void *, void *, size_t, size_t *);
]]
local c=ffi.load('private/tests/bench_memory.so')
return function(s,k,image)
    c.qa_reset();c.qa_page_mode(1);c.qa_put(s.game,image,#image)
    -- Existing sparse fixture data overrides the synthetic native image.
    for at,byte in pairs(s.memory) do
        -- Legacy two-byte fake signature is unused by the current resolver.
        -- The old dictionary fixture falls back to the native image for the
        -- surrounding full read; do not overlay those two obsolete bytes.
        if at~=s.signature and at~=s.signature+1 then c.qa_put(at,byte,1) end
    end
    local oldput=s.put
    s.put=function(at,b) oldput(at,b);c.qa_put(at,b,#b) end
    k.ReadProcessMemory=c.qa_read
    local out,count=ffi.new('uint8_t[4096]'),ffi.new('size_t[1]')
    s.api.read=function(at,n)
        assert(n>0 and n<=4096)
        if c.qa_read(nil,ffi.cast('void *',at),out,n,count)==0 then return nil end
        return ffi.string(out,n)
    end
end
