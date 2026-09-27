local base_fixture=dofile('tests/context_fixture.lua')
local base=dofile('src/context_reader.lua')
local reader=dofile('src/action_reader.lua')
local function bytes(h) return h:gsub('..',function(x) return string.char(tonumber(x,16)) end) end
return function(ammo_path)
    local s=base_fixture()
    s.put(s.templates+256,bytes('090200000000000000000000000000003482df840000000014f02aa3c6abad38010100000000000008020000000000000000000000000000926c9d6c00000000f893414783433755000100000000000000000000420a0000'))
    s.u32(0x4a000000+0x3e0+0x340,10);s.u32(0x4a000000+0x3e0+0x344,0)
    s.u32(0x4b000000+16,0)
    local next_address=0x60000000
    function s.allocate()
        local at=next_address;next_address=next_address+0x1000;return at
    end
    local function manager(rva,map,registry,state,stride,entity,id)
        local m=s.allocate();s.ptr(s.game+rva,m)
        local table=s.allocate();s.map(m+map,table,{{id or s.wid,1}})
        if registry then local rp=s.allocate();s.ptr(m+registry,rp);s.ptr(rp+8,entity or s.waddr) end
        local sp=s.allocate();s.ptr(m+state,sp);s.zero(sp+stride,stride)
        return m,sp+stride
    end
    s.weapon_manager,s.driver_state=manager(0x276c390,0x28,0x40,0x50,40)
    s.u32(s.driver_state,0x408)
    s.driver,s.fire_state=manager(0x276c728,0x20,0x38,0x48,8)
    s.ability,s.ability_state=manager(0x276c370,0x18,0x30,0x38,0xe0)
    s.blocker,s.blocker_state=manager(0x276c3b8,0x28,nil,0x50,0x1b8)
    s.exclusions,s.exclusion_state=manager(0x276c788,0x20,nil,0x50,4)
    s.resources,s.resource_state=manager(0x276c7c0,0x20,0x38,0x48,36)
    s.provider=s.otherid+16;s.u32(s.resource_state,s.provider)
    s.counter,s.counter_state=manager(0x276c318,0x20,nil,0x50,8,nil,s.provider)
    s.u32(s.counter_state,4)
    s.rounds,s.rounds_state=manager(0x276ca00,0x28,0x40,0x50,24)
    local runtime=s.allocate();s.ptr(s.rounds+0x58,runtime)
    s.rounds_runtime=runtime+20;s.zero(s.rounds_runtime,20)
    s.u32(s.rounds_state+4,4);s.u32(s.rounds_state+0x10,54)
    s.rounds_override_map=s.allocate();s.map(s.rounds+0x68,s.rounds_override_map,{})
    s.rounds_templates=s.allocate();s.ptr(s.owner+0xf113a8,s.rounds_templates)
    s.zero(s.rounds_templates,46*16+0x84)
    -- Independent uint64 calculation: int('51f50d6321f52f3d',16) % 46 == 43.
    s.put(s.rounds_templates+43*16,bytes('3d2ff521630df551'))
    s.rounds_config=s.rounds_templates+0x2e0
    s.u32(s.rounds_config+0x40,54);s.u32(s.rounds_config+0x44,55)
    s.put(s.rounds_config+0x68,'\1')
    if ammo_path=='rounds' then s.u32(s.driver_state,0x108) end
    s.avatar_flags=s.avatar+0x53e880+0x1238
    s.zero(s.avatar_flags,24);s.u32(s.avatar_flags,2)
    s.api.module=function() return s.game end
    s.api.module_hash=function() return 'fixture_hash' end
    s.signature=s.game+0x1000;s.put(s.signature,'\1\2')
    s.layout={module_sha256='fixture_hash',signatures={{rva=0x1000,hex='0102'}}}
    function s.snap() return reader.snapshot(s.api,s.game,base) end
    function s.complete() s.put(s.ability_state+0x10,'\0') end
    s.calls={}
    s.native={
        start=function(manager,id,ability,network,speed)
            assert(manager==s.ability and id==s.wid and network==1 and speed==1.0)
            s.calls[#s.calls+1]={'start',ability,network,speed}
            s.u32(s.ability_state,ability);s.put(s.ability_state+0x10,'\1')
        end,
        consume=function(manager,id)
            assert(manager==s.weapon_manager and id==s.wid)
            s.calls[#s.calls+1]={'consume'}
            if ammo_path=='rounds' then
                -- Synthetic transitions only; this does not execute native code.
                local slot=base.u32(s.api.read(s.rounds_runtime+4,4),0)
                local at=s.rounds_state+4+slot*4
                local n=base.u32(s.api.read(at,4),0)
                local chambered=s.api.read(s.rounds_config+0x68,1)~='\0'
                local token=chambered and n>0 and (54+slot) or 0
                s.u32(s.rounds_state+0x10,token)
                if not chambered or token~=0 then assert(n>0);s.u32(at,n-1) end
                if chambered and token==0 then s.put(s.rounds_runtime+0x10,'\1') end
                return
            end
            local n=base.u32(s.api.read(s.counter_state,4),0);assert(n>0)
            s.u32(s.counter_state,n-1)
        end,
        count=function(manager,id)
            assert(manager==s.weapon_manager and id==s.wid)
            s.calls[#s.calls+1]={'count'}
            if ammo_path=='rounds' then
                local slot=base.u32(s.api.read(s.rounds_runtime+4,4),0)
                return base.u32(s.api.read(s.rounds_state+4+slot*4,4),0)+1
            end
            return base.u32(s.api.read(s.counter_state,4),0)+1
        end,
        after=function(manager,id,count,enabled)
            assert(manager==s.wd and id==s.wid and enabled==true)
            s.calls[#s.calls+1]={'after',count}
        end
    }
    function s.bind() return s.native end
    return s
end
