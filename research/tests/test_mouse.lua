-- Synthetic memory only: ownership/restoration and physical edge policy.
local base=dofile('src/context_reader.lua')
local fixture=dofile('tests/action_fixture.lua')
local Gate=dofile('src/weapon_fire_gate.lua')
local Router=dofile('src/mouse_router.lua')
local function scenario()
    local s=fixture('rounds');s.u32(s.driver_state,0x1148);s.writes={};s.events={}
    function s.api.fire_gate_exchange(at,before,after)
        assert(base.u32(s.api.read(at,4),0)==before)
        s.writes[#s.writes+1]={at,before,after}
        if s.write_failure then return false,'fixture_write_failure' end
        s.u32(at,after)
        if s.readback_failure then return false,'fixture_readback_failure' end
        return true
    end
    s.gate=Gate.new(s.api,s.game,base,function(kind,row)
        s.events[#s.events+1]={kind,row};return not s.log_failure
    end)
    return s
end
local passed=0
local function test(name,f) f();passed=passed+1;print('PASS '..name) end
test('gate owns only selected local C4 and restores its flags without mode/ammo changes',function()
    local s=scenario();local before={}
    for k,v in pairs(s.memory) do before[k]=v end
    assert(s.gate.sync(true,true) and s.gate.active)
    for k,v in pairs(s.memory) do
        if v~=before[k] then assert(k==s.driver_state+1,'unrelated memory changed') end
    end
    for _=1,20 do assert(s.gate.sync(true,true)) end
    assert(#s.writes==1 and s.gate.stop() and #s.writes==2)
    for k,v in pairs(s.memory) do assert(v==before[k],'not restored') end
end)
test('non-C4, unknown flags and a preexisting mute are never owned or written',function()
    for _,condition in ipairs({'nonc4','unknown','muted'}) do
        local s=scenario()
        if condition=='nonc4' then s.u32(s.state+0x1c,1)
        else s.u32(s.driver_state,condition=='muted' and 0x148 or 0x108) end
        assert(not s.gate.sync(true,true) and #s.writes==0 and not s.gate.lease)
    end
end)
test('arming waits for both physical release and the native Fire latch to clear',function()
    local s=scenario();assert(not s.gate.sync(true,false) and #s.writes==0)
    s.put(s.fire_state,'\1');assert(not s.gate.sync(true,true) and #s.writes==0)
    s.put(s.fire_state,'\0');assert(s.gate.sync(true,true) and #s.writes==1)
end)
test('disarming while held mutes until release to avoid replaying vanilla Fire',function()
    local s=scenario();assert(s.gate.sync(true,true))
    assert(not s.gate.sync(false,false) and s.gate.lease and #s.writes==1)
    assert(not s.gate.sync(false,true) and not s.gate.lease and #s.writes==2)
end)
test('switching equipment restores the previous C4 even with a button held',function()
    local s=scenario();s.gate.sync(true,true);s.u32(s.state+0x1c,1)
    assert(not s.gate.sync(true,false) and not s.gate.lease)
    assert(base.u32(s.api.read(s.driver_state,4),0)==0x1148 and #s.writes==2)
end)
test('restore follows component compaction without touching the old address',function()
    local s=scenario();s.gate.sync(true,true)
    local map,registry,state=s.allocate(),s.allocate(),s.allocate()
    s.map(s.weapon_manager+0x28,map,{{s.wid,2}})
    s.ptr(s.weapon_manager+0x40,registry);s.ptr(registry+16,s.waddr)
    s.ptr(s.weapon_manager+0x50,state);s.u32(state+80,0x148)
    s.u32(s.driver_state,0xfeed)
    assert(s.gate.stop() and s.writes[2][1]==state+80)
    assert(base.u32(s.api.read(s.driver_state,4),0)==0xfeed)
end)
test('destroyed or reused entity and changed owner epoch cannot receive stale restore',function()
    for _,condition in ipairs({'reuse','gone','owner','manager','registry'}) do
        local s=scenario();s.gate.sync(true,true)
        if condition=='reuse' then s.put(s.waddr,s.other)
        elseif condition=='gone' then s.map(s.owner+0xf19a70,0x42000000,{{s.aid,3}})
        elseif condition=='owner' then s.ptr(s.game+0x276f0c0,s.owner+8)
        elseif condition=='manager' then s.ptr(s.game+0x276c390,s.weapon_manager+8)
        else
            local registry=s.api.pointer(s.api.read(s.weapon_manager+0x40,8))
            s.ptr(registry+8,s.owner+0xf31ad8+6*24)
        end
        assert(s.gate.stop() and not s.gate.lease and #s.writes==1)
    end
end)
test('failed write and failed readback retain enough ownership for rollback',function()
    for _,kind in ipairs({'write_failure','readback_failure'}) do
        local s=scenario();s[kind]=true
        assert(not pcall(s.gate.sync,true,true) and s.gate.lease)
        s[kind]=false;assert(s.gate.stop() and not s.gate.lease)
        assert(base.u32(s.api.read(s.driver_state,4),0)==0x1148)
    end
end)
test('transient unavailable memory retains restore ownership for retry',function()
    local s=scenario();s.gate.sync(true,true)
    s.intercept=function() return nil,true end
    assert(not s.gate.stop() and s.gate.lease and #s.writes==1)
    s.intercept=nil;assert(s.gate.stop() and #s.writes==2)
end)
test('foreign configuration changes are not overwritten during restore',function()
    local s=scenario();s.gate.sync(true,true);s.u32(s.driver_state,0x2148)
    assert(not s.gate.stop() and s.gate.lease and #s.writes==1)
    assert(base.u32(s.api.read(s.driver_state,4),0)==0x2148)
end)
test('logging failure and last-moment identity change prevent acquiring the gate',function()
    local s=scenario();s.log_failure=true
    assert(not pcall(s.gate.sync,true,true) and #s.writes==0)
    s=scenario()
    local gate=Gate.new(s.api,s.game,base,function(kind,row)
        if row.fire_gate_status=='acquire' then s.put(s.waddr,s.other) end
        return true
    end)
    assert(not pcall(gate.sync,true,true) and #s.writes==0)
end)
local up={down=false,pressed=false,released=true}
local press={down=true,pressed=true,released=false}
test('router uses edges, independent modes and full release after identity changes',function()
    local r=Router.new(function() return true end)
    r.sample('a',press,up);assert(not r.sample('a',press,up).detonate)
    r.sample('a',up,up);assert(r.sample('a',press,up).detonate)
    for _=1,100 do assert(not r.sample('a',press,up).detonate) end
    assert(not r.sample('b',press,up).detonate)
    r.sample('b',up,up);assert(r.sample('b',up,press).deploy)
    assert(not r.sample(nil,press,press).deploy)
end)
test('simultaneous mouse edges deterministically choose Detonate only',function()
    local events={};local r=Router.new(function(kind,row) events[#events+1]=row;return true end)
    r.sample('a',up,up);local out=r.sample('a',press,press)
    assert(out.detonate and not out.deploy and #events==1 and events[1].resolution=='DETONATE_PRIORITY')
end)
test('a complete click between samples is accepted once',function()
    local r=Router.new(function() return true end);r.sample('a',up,up)
    assert(r.sample('a',{down=false,pressed=true,released=true},up).detonate)
    assert(not r.sample('a',up,up).detonate)
end)
print('TOTAL '..passed..' EXP04 gate and router checks; synthetic memory only')
