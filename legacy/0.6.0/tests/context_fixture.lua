-- Shared synthetic memory fixture; no game process access.
local ffi=require('ffi')
local reader=dofile('src/context_reader.lua')
local function bytes(h) return h:gsub('..',function(x) return string.char(tonumber(x,16)) end) end
local function word(n) return ffi.string(ffi.new('uint32_t[1]',n),4) end
local function pointer(n) return ffi.string(ffi.new('uint64_t[1]',n),8) end
local function fixture()
    local s={memory={},read_calls=0,game=0x10000000,owner=0x20000000,avatar=0x30000000,
        pm=0x31000000,mode=0x32000000,inv=0x33000000,wd=0x34000000,
        aid=0x8100000f,wid=0x9100001f,otherid=0x91000020,unit=0x12345}
    function s.put(at,b) for i=1,#b do s.memory[at+i-1]=b:sub(i,i) end end
    function s.zero(at,n) s.put(at,string.rep('\0',n)) end
    function s.u32(at,n) s.put(at,word(n)) end
    function s.ptr(at,n) s.put(at,pointer(n)) end
    function s.map(at,data,items,n)
        n=n or 8
        s.put(at,pointer(data)..word(n)..word(0xffffffff)..word(0xfedcba91))
        for i=0,n-1 do s.put(data+i*8,word(0xffffffff)..word(0xffffffff)) end
        for _,item in ipairs(items) do
            local product=ffi.new('uint64_t',item[1])*ffi.new('uint64_t',0xfedcba91)
            local index=tonumber(ffi.cast('uint32_t',product))%n
            while s.memory[data+index*8]~='\255' do index=(index+1)%n end
            s.put(data+index*8,word(item[1])..word(item[2]))
        end
    end
    local function entity(hash,id,unit)
        return bytes(hash):reverse()..word(id)..word(unit)..word(0)..word(1)
    end
    s.player=entity('4d1c334d294dfa97',s.aid,s.unit)
    s.weapon=entity('51f50d6321f52f3d',s.wid,0xabc)
    s.other=entity('1111111122222222',s.otherid,0xdef)
    for rva,value in pairs({[0x276c3d0]=s.mode,[0x276c190]=s.pm,[0x276f0c0]=s.owner,
        [0x276ca30]=s.avatar,[0x276c468]=s.inv,[0x276c9f0]=s.wd}) do s.ptr(s.game+rva,value) end
    s.zero(s.mode,0x44);s.u32(s.mode+8,1);s.u32(s.mode+0x40,3)
    s.u32(s.pm+0x84,2);s.u32(s.pm+0x88,2);s.ptr(s.pm+0xe8,0x40000000)
    s.put(0x40000000,s.player);s.u32(s.pm+0x3a8,s.unit)
    s.map(s.owner+0xf21a88,0x41000000,{{s.unit,3}})
    s.map(s.owner+0xf19a70,0x42000000,{{s.wid,5},{s.otherid,6},{s.aid,3}})
    s.eaddr=s.owner+0xf31ad8+3*24;s.waddr=s.owner+0xf31ad8+5*24
    s.put(s.eaddr,s.player);s.put(s.waddr,s.weapon);s.put(s.owner+0xf31ad8+6*24,s.other)
    s.map(s.avatar+0xf8,0x43000000,{{s.aid,1}});s.u32(s.avatar+0x6c,2)
    s.ptr(s.avatar+0x110+8,0x44000000);s.put(0x44000000,s.player)
    s.map(s.inv+0x28,0x45000000,{{s.aid,2}});s.u32(s.inv+0x14,3)
    s.ptr(s.inv+0x40,0x46000000);s.ptr(0x46000000+16,s.eaddr)
    s.ptr(s.inv+0x50,0x47000000);s.state=0x47000000+96;s.zero(s.state,48)
    s.u32(s.state,s.otherid);s.u32(s.state+8,s.wid);s.u32(s.state+0x1c,3)
    s.map(s.wd+0x30,0x48000000,{{s.wid,1}});s.u32(s.wd+0x1c,2)
    s.ptr(s.wd+0x48,0x49000000);s.ptr(0x49000000+8,s.waddr)
    s.ptr(s.wd+0x58,0x4a000000);s.zero(0x4a000000+0x3e0+0x340,16)
    s.u32(0x4a000000+0x3e0+0x340,11);s.u32(0x4a000000+0x3e0+0x344,10)
    s.ptr(s.wd+0x60,0x4b000000);s.zero(0x4b000000+12,12);s.u32(0x4b000000+16,0x900)
    s.ptr(s.wd+0x50,0x4c000000);s.zero(0x4c000000+2,2)
    s.templates=0x4d000000;s.ptr(s.owner+0xf11888,s.templates);s.zero(s.templates,256+0x58)
    s.put(s.templates+13*16,bytes('51f50d6321f52f3d'):reverse()..word(0)..word(0))
    s.u32(s.templates+256,333);s.u32(s.templates+260,334)
    s.u32(s.templates+256+40,666);s.u32(s.templates+260+40,667)
    s.api={}
    function s.api.read(at,n)
        s.read_calls=s.read_calls+1
        if s.intercept then local v,used=s.intercept(at,n);if used then return v end end
        local a={}
        for i=0,n-1 do if not s.memory[at+i] then return nil end;a[#a+1]=s.memory[at+i] end
        return table.concat(a)
    end
    function s.api.pointer(b)
        if not b or #b<8 then return nil end
        local v=ffi.new('uint64_t[1]');ffi.copy(v,b,8)
        local n=tonumber(v[0]);if n>=65536 and n<0x800000000000 then return n end
    end
    function s.snap() return reader.snapshot(s.api,s.game) end
    return s
end
return fixture
