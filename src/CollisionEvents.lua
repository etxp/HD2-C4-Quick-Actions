-- Read the engine's EventStream without advancing its cursor or calling it.
-- Layout comes from the getter/begin/next bodies read from the running engine.
local M={}
local function u32(b,o)
    local a,c,d,e=b:byte(o+1,o+4);assert(e,'event_short_integer')
    return a+c*256+d*65536+e*16777216
end
local function unhex(h)return (h:gsub('..',function(x)return string.char(tonumber(x,16))end))end
local NEXT=unhex('448b0a488bc1443b09720333c0c3498bc9480348088b410441894008488d41084989008b01418d490803c8b801000000890ac3')
local BEGIN=unhex('c70200000000c3')
M.contact_type=0x9e1f9efd
function M.decode(bytes)
    assert(#bytes<=262144,'event_byte_budget')
    local contacts,types={},{};local at,count=0,0
    while at<#bytes do
        assert(at+8<=#bytes,'event_truncated_header')
        local size,kind=u32(bytes,at),u32(bytes,at+4)
        assert(at+8+size<=#bytes,'event_truncated_payload')
        count=count+1;assert(count<=4096,'event_record_budget')
        local key=string.format('%08x',kind);types[key]=(types[key] or 0)+1
        if kind==M.contact_type then
            assert(size>=0x34 and size<=256,'event_contact_size')
            local p=bytes:sub(at+9,at+8+size)
            contacts[#contacts+1]={kind=u32(p,0),actor_a=u32(p,4),actor_b=u32(p,8),
                unit_a=u32(p,12),unit_b=u32(p,16),raw=p}
        end
        at=at+8+size
    end
    return {contacts=contacts,types=types,records=count,bytes=#bytes}
end
function M.new(api,game,symbols)
    local function read(at,n)
        assert(type(at)=='number' and at>=65536 and at+n<0x800000000000,'event_address')
        local b=assert(api.read(at,n),'event_read_unavailable');assert(#b==n,'event_short_read');return b
    end
    local function ptr(at)return assert(api.pointer(read(at,8)),'event_pointer_unavailable')end
    local physics=ptr(game+assert(symbols.global_contact_physics_api))
    local events=ptr(game+assert(symbols.global_contact_events_api))
    local getter,begin,next_event=ptr(physics+0x38),ptr(events+0x20),ptr(events+0x28)
    local code=read(getter,21)
    assert(code:sub(1,5)==unhex('8bc1488d0d') and
        code:sub(10)==unhex('4869c0b0000000488b0408c3'),'event_getter_layout_changed')
    local displacement=u32(code,5)
    if displacement>=0x80000000 then displacement=displacement-4294967296 end
    local worlds=getter+9+displacement
    assert(read(begin,#BEGIN)==BEGIN,'event_begin_layout_changed')
    assert(read(next_event,#NEXT)==NEXT,'event_iterator_layout_changed')
    local self={}
    function self.verify()
        assert(ptr(game+symbols.global_contact_physics_api)==physics and
            ptr(game+symbols.global_contact_events_api)==events,'event_api_changed')
        assert(ptr(physics+0x38)==getter and ptr(events+0x20)==begin and
            ptr(events+0x28)==next_event,'event_function_changed')
        assert(read(getter,#code)==code and read(begin,#BEGIN)==BEGIN and
            read(next_event,#NEXT)==NEXT,'event_code_changed')
    end
    function self.snapshot()
        self.verify()
        local root=ptr(game+assert(symbols.global_contact_world))
        local index_bytes=read(root+0x10f0,4);local index=u32(index_bytes,0)
        if index>=4 then return nil,'physics_world_unavailable' end
        local slot=worlds+index*0xb0;local stream=ptr(slot)
        local header=read(stream,16)
        local used,capacity=u32(header,0),u32(header,4)
        assert(used<=capacity and used<=262144 and capacity<=16*1024*1024,'event_stream_budget')
        local buffer=used>0 and assert(api.pointer(header:sub(9)),'event_buffer_unavailable')
        local function contents()
            local parts={}
            for at=0,used-1,4096 do parts[#parts+1]=read(buffer+at,math.min(4096,used-at)) end
            return table.concat(parts)
        end
        local bytes=contents()
        -- Physics can run concurrently. Reject torn/replaced buffers, including
        -- a same-length rewrite; never use stale capacity bytes as live events.
        if contents()~=bytes or read(stream,16)~=header or ptr(slot)~=stream or
            read(root+0x10f0,4)~=index_bytes or ptr(game+symbols.global_contact_world)~=root then
            return nil,'event_stream_changed_during_read'
        end
        local result=M.decode(bytes);result.world_index=index;result.root=root;result.stream=stream
        return result
    end
    self.verify()
    return self
end
return M
