local ffi=require('ffi')
local R=dofile('private/tests/mock_symbols.lua')
local D=dofile('private/tests/mock_fields.lua')
local base=dofile('private/tests/modules/context_reader.lua')(R,D)
local function module(name)
    local f=assert(io.open('src/'..name..'.lua'));local text=f:read('*a');f:close()
    return assert(loadstring('return function(D) '..text..' end'))()(D)
end
local reader=module('ContactReader')
return function()
    local s=dofile('tests/action_fixture.lua')('rounds');s.D=D;s.base=base;s.reader=reader
    s.symbols={global_contact_owner=R.global_owner,global_contact_remote=0x300008,
        global_contact_world=0x300010,global_contact_explosive=0x300018,
        global_contact_invalid_source=0x300020,global_contact_manual_label=0x300028,
        global_contact_contact_label=0x300030}
    s.root=s.allocate();s.remote=s.allocate();s.explosive=s.allocate()
    s.ptr(s.game+s.symbols.global_contact_world,s.root)
    s.ptr(s.game+s.symbols.global_contact_remote,s.remote)
    s.ptr(s.game+s.symbols.global_contact_explosive,s.explosive)
    s.u32(s.game+s.symbols.global_contact_invalid_source,0x7fff)
    s.zero(s.game+s.symbols.global_contact_manual_label,16)
    s.registry=s.allocate();s.links=s.allocate();s.xregistry=s.allocate();s.network=s.allocate()
    s.ptr(s.remote+0x38,s.registry);s.ptr(s.remote+0x48,s.links)
    s.ptr(s.explosive+0x50,s.xregistry);s.ptr(s.explosive+0x68,s.network)
    s.charges={};s.effects={};s.logs={};s.events={root=s.root,contacts={}}
    local function bytes(h)return(h:gsub('..',function(v)return string.char(tonumber(v,16))end))end
    function s.entity(id,unit,owned)
        return bytes('67dd12837d21759b')..ffi.string(ffi.new('uint32_t[4]',id,unit,17,owned==false and 0 or 1),16)
    end
    function s.rebuild()
        local remote,entities,units,xs={},{{s.wid,5},{s.otherid,6},{s.aid,3}},{},{}
        s.map(s.owner+D.entity_unit_map,s.allocate(),{{s.unit,3},{0xabc,5},{0xdef,6}})
        s.u32(s.remote+0x10,#s.charges)
        for i,c in ipairs(s.charges)do
            c.entity=c.entity or s.entity(c.id,c.unit,c.owned)
            c.address=s.owner+D.entity_array+(20+i)*24
            s.put(c.address,c.entity);s.ptr(s.registry+(i-1)*8,c.address)
            s.u32(s.links+(i-1)*8,c.foreign and 0xdef or 0xabc);s.u32(s.links+(i-1)*8+4,0)
            s.ptr(s.xregistry+(i-1)*8,c.address);s.zero(s.network+(i-1)*56,56)
            c.flag=s.network+(i-1)*56+1;s.put(c.flag,c.requested and '\1' or '\0')
            remote[#remote+1]={c.id,i-1};entities[#entities+1]={c.id,20+i}
            units[#units+1]={c.unit,c.id};xs[#xs+1]={c.id,i-1}
        end
        local n=8;while n<#entities*2 do n=n*2 end
        s.map(s.remote+0x20,s.allocate(),remote,n)
        s.map(s.owner+D.entity_id_map,s.allocate(),entities,n)
        s.map(s.owner+D.unit_entity_id_map,s.allocate(),units,n)
        s.map(s.explosive+0x38,s.allocate(),xs,n)
    end
    function s.add(id,opts)
        local c={id=id,unit=0x400000+id};for k,v in pairs(opts or {})do c[k]=v end
        s.charges[#s.charges+1]=c;s.rebuild();return c
    end
    function s.mode(mode)s.u32(0x4b000000+16,mode=='CONTACT' and 0x100 or 0)end
    function s.collide(c,kind,side)
        local u=type(c)=='table' and c.unit or c
        return {kind=kind or 0,unit_a=side=='b' and 0 or u,unit_b=side=='b' and u or 0,raw=string.rep('\0',64)}
    end
    function s.selected()
        local _,_,cap=reader.selected(s.api,s.game,base,s.symbols);return cap
    end
    function s.tracked(lease,events)return reader.tracked(s.api,s.game,base,s.symbols,lease,events)end
    s.backend={selected=s.selected,tracked=s.tracked,events=function()return s.events end,
        verify=function()assert(not s.bad_code,'changed code')end,
        explode=function(cap)
            assert(cap.manager==s.explosive and cap.invalid_source==0x7fff)
            s.effects[#s.effects+1]=cap.id
            for _,c in ipairs(s.charges)do if c.id==cap.id then c.requested=true;s.put(c.flag,'\1')end end
        end}
    function s.emit(kind,fields)
        if s.log_failure then return false end
        s.logs[#s.logs+1]={kind=kind,fields=fields};return true
    end
    s.controller=dofile('src/ContactController.lua').new(s.backend,s.emit)
    function s.throw(now,mode)
        s.mode(mode or 'CONTACT');s.controller.prepare(now);s.controller.commit(now)
        assert(not s.controller.disabled)
    end
    s.rebuild();return s
end
