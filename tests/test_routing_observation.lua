local R=dofile('private/tests/mock_symbols.lua')
local D=dofile('private/tests/mock_fields.lua')
local base=dofile('private/tests/modules/context_reader.lua')(R,D)
local route=dofile('private/tests/modules/routing_reader.lua')(R,D)
local action=dofile('private/tests/modules/action_reader.lua')(R,D)
local fixture=dofile('tests/action_fixture.lua')
local bit=require('bit')
local function check(name,fn)fn();print('PASS '..name)end
local function flag(s,n)
    local at=s.avatar_flags+math.floor(n/32)*4
    s.u32(at,bit.bor(base.u32(s.api.read(at,4),0),2^(n%32)))
end
local function snap(s)return route.snapshot(s.api,s.game,base)end
for _,case in ipairs({'ground','prone','dive','airborne','map','weapon_menu','dead','ragdoll','native_fire','tank'})do
    check('routing preserves action input identity and avatar veto: '..case,function()
        local s=fixture('rounds')
        if case=='dead'then s.zero(s.avatar_flags,24)
        elseif case=='native_fire'then s.put(s.fire_state,'\1')
        elseif case=='tank'then dofile('tests/benchmark_scenario.lua')(s,'tank_passenger')
        elseif case~='ground'then flag(s,({prone=D.prone,dive=D.diving,airborne=D.airborne,
            map=D.tactical_map,weapon_menu=D.weapon_menu,ragdoll=D.blocked[1]})[case])end
        local row,why,cap=snap(s);assert(row and not why and cap)
        local full,reason,original=action.input_snapshot(s.api,s.game,base);assert(full and not reason and original)
        assert(cap.input_only and cap.routing_only and not cap.reload and not cap.ability_manager)
        assert(cap.identity==original.identity and cap.interrupt==original.interrupt)
        assert(row.test_avatar_allowed==full.test_avatar_allowed)
        assert(cap.same() and cap.weapon_plan.same())
    end)
end
check('map and weapon settings are observed while another or no weapon is selected',function()
    for _,slot in ipairs({0,1})do
        for _,n in ipairs({D.tactical_map,D.weapon_menu})do
            local s=fixture('rounds');s.u32(s.state+0x1c,slot);flag(s,n)
            local row,why,cap=snap(s);assert(row and not why and not cap)
            assert(row[n==D.tactical_map and 'tactical_map_active' or 'weapon_menu_active'])
        end
    end
end)
check('idle routing never reads ability descriptors, ammo, reload or native action state',function()
    local s=fixture('rounds');local seen={};local original=s.api.read
    s.api.read=function(at,n)seen[at]=true;return original(at,n)end
    local row,_,cap=snap(s);assert(row and cap)
    for _,at in ipairs({s.game+R.global_weapon_data,s.owner+D.ability_templates,
        s.rounds_state,s.rounds_runtime,s.rounds_config,s.ability_state,
        s.game+R.global_blocker,s.game+R.global_exclusions})do assert(not seen[at])end
end)
check('routing guards retain exact UI, selection, driver and registry source bytes',function()
    local s=fixture('rounds')
    for _,at in ipairs({s.avatar_flags,s.state,s.state+0x1c,s.driver_state,s.fire_state,s.eaddr,s.waddr})do
        local old=s.api.read(at,1);local _,_,cap=snap(s);assert(cap and cap.same())
        s.put(at,string.char((old:byte()+1)%256))
        assert(not cap.same() and not cap.weapon_plan.same());s.put(at,old)
    end
end)
check('routing snapshots cannot authorize native actions even when selected identity is valid',function()
    local s=fixture('rounds');local _,_,cap=snap(s);assert(cap and cap.input_only)
    local f=assert(io.open('src/ActionBackend.lua'));local text=f:read('*a');f:close()
    local module=assert(loadstring('return function(NativeResolver,SnapshotCache,RoutingReader,PassengerHold) local R,D\n'..text..'\nend'))()(
        {resolve=function()return {symbols=R,fields=D,verify=function()end}end},
        dofile('src/SnapshotCache.lua'),route,
        {new=function()return {stop=function()return true end}end})
    s.api.fire_gate_exchange=function()end;s.api.passenger_exchange=function()end
    for _,n in ipairs({'lean','reload','input_inhibit','input_unblock'})do s.native[n]=function()error('unexpected mutation')end end
    local b=module.new(s.api,action,base,{},function()return s.native end,function()return true end)
    assert(not pcall(b.execute,'DETONATE',cap,0))
    assert(not pcall(b.execute,'DEPLOY',cap,0))
    assert(not pcall(b.reload,cap))
    assert(not pcall(b.prepare_deploy,cap))
    assert(#s.calls==0)
end)
