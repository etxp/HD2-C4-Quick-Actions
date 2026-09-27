local ffi=require('ffi')
local E=dofile('src/CollisionEvents.lua')
local function pack(n,size)
    local b={};for i=1,size do b[i]=string.char(n%256);n=math.floor(n/256)end;return table.concat(b)
end
local function unhex(h)return (h:gsub('..',function(x)return string.char(tonumber(x,16))end))end
local function record(kind,payload)return pack(#payload,4)..pack(kind,4)..payload end
local function collision(kind,a,b)
    return record(E.contact_type,pack(kind,4)..pack(12,4)..pack(13,4)..pack(a,4)..pack(b,4)..string.rep('\0',32))
end
local payload=record(0x7dc7cfba,string.rep('\0',28))..collision(0,100,200)..collision(2,200,100)
local parsed=E.decode(payload)
assert(parsed.records==3 and #parsed.contacts==2 and parsed.contacts[1].unit_a==100)
assert(parsed.contacts[2].kind==2 and parsed.types['7dc7cfba']==1)
assert(#E.decode('').contacts==0)
print('PASS only native collision event type is decoded; overlaps and empty streams do not imply contact')
for _,bad in ipairs({payload:sub(1,-2),payload:sub(1,4),record(E.contact_type,string.rep('\0',51)),
    record(E.contact_type,string.rep('\0',257)),string.rep(record(1,''),4097),string.rep('x',262145)})do
    assert(not pcall(E.decode,bad))
end
print('PASS truncated payloads, incompatible contact layouts and oversized streams rejected')
local function fixture()
    local mem={};local s={game=0x10000,root=0x20000,physics=0x30000,events=0x40000,
        getter=0x50000,begin=0x51000,next=0x52000,worlds=0x60000,stream=0x70000,buffer=0x80000}
    function s.put(at,b)for i=1,#b do mem[at+i-1]=b:sub(i,i)end end
    local function read(at,n)
        assert(n<=4096);local b={}
        for i=0,n-1 do if not mem[at+i]then return end;b[#b+1]=mem[at+i]end
        return table.concat(b)
    end
    s.api={read=function(at,n)
        local b=read(at,n);if s.on_read then s.on_read(at,n)end;return b
    end,pointer=function(b)
        if not b or #b<8 then return end
        local n=tonumber(ffi.cast('const uint64_t *',b)[0]);if n>=65536 then return n end
    end}
    function s.ptr(at,value)s.put(at,pack(value,8))end
    function s.u32(at,value)s.put(at,pack(value,4))end
    s.symbols={global_contact_physics_api=8,global_contact_events_api=16,global_contact_world=24}
    s.ptr(s.game+8,s.physics);s.ptr(s.game+16,s.events);s.ptr(s.game+24,s.root)
    s.ptr(s.physics+0x38,s.getter);s.ptr(s.events+0x20,s.begin);s.ptr(s.events+0x28,s.next)
    s.put(s.getter,unhex('8bc1488d0d')..pack(s.worlds-s.getter-9,4)..unhex('4869c0b0000000488b0408c3'))
    s.put(s.begin,unhex('c70200000000c3'))
    -- Fixed contract fixture; no private game capture is required or executed.
    local code=unhex('448b0a488bc1443b09720333c0c3498bc9480348088b410441894008488d41084989008b01418d490803c8b801000000890ac3')
    s.put(s.next,code)
    s.u32(s.root+0x10f0,2);s.ptr(s.worlds+2*0xb0,s.stream)
    s.u32(s.stream,#payload);s.u32(s.stream+4,8192);s.ptr(s.stream+8,s.buffer);s.put(s.buffer,payload)
    function s.create()return E.new(s.api,s.game,s.symbols)end
    return s
end
local s=fixture();local live=s.create();local result=assert(live.snapshot())
assert(result.records==3 and result.world_index==2 and result.contacts[1].unit_b==200)
print('PASS iterator contract fixture validates runtime pointer/table traversal')
s.u32(s.stream,0);s.ptr(s.stream+8,0)
assert(live.snapshot().records==0)
print('PASS empty stream never interprets stale buffer capacity or dereferences a null buffer')
for _,field in ipairs({'getter','begin','next'})do
    s=fixture();live=s.create();s.put(s[field],'\0');assert(not pcall(live.snapshot))
end
s=fixture();live=s.create();s.ptr(s.physics+0x38,s.next);assert(not pcall(live.snapshot))
print('PASS changed getter/iterator code and replaced API function pointers rejected')
s=fixture();live=s.create();s.u32(s.root+0x10f0,0xffffffff)
local row,why=live.snapshot();assert(not row and why=='physics_world_unavailable')
print('PASS missing physics world remains unavailable without reading arbitrary table slots')
for _,mutation in ipairs({'header','same_size_payload','world','stream','root'})do
    s=fixture();live=s.create()
    s.on_read=function(at)
        if at~=s.buffer then return end;s.on_read=nil
        if mutation=='header' then s.u32(s.stream,0)
        elseif mutation=='same_size_payload' then s.put(s.buffer+12,'\1')
        elseif mutation=='world' then s.u32(s.root+0x10f0,1)
        elseif mutation=='stream' then s.ptr(s.worlds+2*0xb0,s.buffer)
        else s.ptr(s.game+24,s.buffer) end
    end
    row,why=live.snapshot();assert(not row and why=='event_stream_changed_during_read',mutation)
end
print('PASS torn same-size payloads, buffer reuse and world changes discarded')
for _,invalid in ipairs({{10,9},{262145,262145},{0,16777217}})do
    s=fixture();live=s.create();s.u32(s.stream,invalid[1]);s.u32(s.stream+4,invalid[2])
    assert(not pcall(live.snapshot))
end
print('PASS used/capacity bounds checked before buffer allocation')
local f=assert(io.open('src/CollisionEvents.lua'));local text=f:read('*a');f:close()
for _,word in ipairs({'ffi.cast','api.write','VirtualProtect','CreateThread'})do assert(not text:find(word,1,true))end
print('PASS event reader has no native-call, mutation, hook or worker-thread surface')
