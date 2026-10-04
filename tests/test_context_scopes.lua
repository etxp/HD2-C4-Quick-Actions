-- Scope only the data needed by UI/fire routing. Capabilities still reread all
-- identity and extension bytes; no saved address is trusted across snapshots.
local R=dofile('private/tests/mock_symbols.lua')
local D=dofile('private/tests/mock_fields.lua')
local reader=dofile('private/tests/modules/context_reader.lua')(R,D)
local fixture=dofile('tests/context_fixture.lua')
local function check(name,fn)fn();print('PASS '..name)end
local function capability(e)
    return {id=e.id,weapon_id=e.weapon_id,same=e.checked}
end
local function scoped(s,kind,extend)
    return reader[kind..'_snapshot'](s.api,s.game,extend or capability)
end
check('avatar UI observations do not read inventory or C4 descriptors',function()
    local s=fixture();local reads={};local original=s.api.read
    s.api.read=function(at,n)reads[at]=true;return original(at,n)end
    s.ptr(s.game+R.global_inventory,0);s.ptr(s.game+R.global_weapon_data,0)
    local row,why,cap=scoped(s,'avatar')
    assert(row and not why and cap and cap.id==s.aid and cap.weapon_id==nil)
    assert(not reads[s.game+R.global_inventory] and not reads[s.game+R.global_weapon_data])
    assert(not reads[s.owner+D.ability_templates] and cap.same())
end)
check('avatar scopes reject stale entity identity when revalidated',function()
    local s=fixture();local _,_,cap=scoped(s,'avatar');assert(cap and cap.same())
    s.u32(s.eaddr+8,s.aid+1);assert(not cap.same())
end)
check('avatar extension races discard the entire observation',function()
    local s=fixture()
    local row,why,cap=scoped(s,'avatar',function(e)
        s.u32(s.pm+0x3a8,s.unit+1)
        return capability(e)
    end)
    assert(row==nil and why=='context_changed_during_read' and cap==nil)
end)
check('avatar extension failures never return a partial capability',function()
    local s=fixture();local row,why,cap=scoped(s,'avatar',function(e)
        e.read(0x70000000,4,true)
        return capability(e)
    end)
    assert(row and not why and cap==nil and row.action_context_status=='rejected')
end)
check('selected C4 routing does not read unused weapon data or templates',function()
    local s=fixture();local reads={};local original=s.api.read
    s.api.read=function(at,n)reads[at]=true;return original(at,n)end
    s.ptr(s.game+R.global_weapon_data,0);s.ptr(s.owner+D.ability_templates,0)
    local row,why,cap=scoped(s,'selected')
    assert(row and not why and cap and cap.weapon_id==s.wid and cap.same())
    assert(not reads[s.game+R.global_weapon_data] and not reads[s.owner+D.ability_templates])
end)
check('selected scopes still reject unrelated and unowned weapons',function()
    local s=fixture();s.u32(s.state+0x1c,1)
    local row,_,cap=scoped(s,'selected');assert(row.current_weapon=='OTHER' and cap==nil)
    s.u32(s.state+0x1c,3);s.put(s.waddr+20,'\0')
    row,_,cap=scoped(s,'selected');assert(row.current_weapon=='C4_DETONATOR' and not row.weapon_owned and cap==nil)
end)
check('selected scope guards detect weapon switching and registry replacement',function()
    local s=fixture();local _,_,cap=scoped(s,'selected');assert(cap and cap.same())
    s.u32(s.state+0x1c,1);assert(not cap.same())
    s.u32(s.state+0x1c,3);_,_,cap=scoped(s,'selected');assert(cap and cap.same())
    s.put(0x44000000,s.other);assert(not cap.same())
end)
check('scoped readers keep the full action descriptor admission check',function()
    local s=dofile('tests/action_fixture.lua')('rounds')
    s.u32(s.templates+D.ability_capacity*16,999)
    local _,_,selected=scoped(s,'selected');assert(selected)
    local row,_,action=s.snap()
    assert(row and action==nil and row.action_context_error=='unsupported_c4_descriptors')
end)
check('scoped UI reads retain map flags without a selected weapon',function()
    local s=fixture();s.u32(s.state+0x1c,0)
    local flags=s.avatar+0x53e880+0x1238;s.zero(flags,24)
    s.u32(flags+math.floor(D.tactical_map/32)*4,2^(D.tactical_map%32))
    local avatar_flags=dofile('src/AvatarFlags.lua')
    local _,_,cap=scoped(s,'avatar',function(e)
        local bytes=e.read(e.avatar+0x53e880+e.avatar_index*0x1238,24,true)
        return {map=avatar_flags.has(bytes,D.tactical_map),same=e.checked}
    end)
    assert(cap and cap.map and cap.same())
    s.zero(flags,24);assert(not cap.same())
end)
check('narrow context scopes remove reads while full context remains unchanged',function()
    local s=fixture();s.read_calls=0;local full=reader.snapshot(s.api,s.game);assert(full)
    local full_reads=s.read_calls;s.read_calls=0
    assert(scoped(s,'selected'));local selected_reads=s.read_calls;s.read_calls=0
    assert(scoped(s,'avatar'));local avatar_reads=s.read_calls
    assert(avatar_reads<selected_reads and selected_reads<full_reads)
    print(string.format('SCOPE_READS avatar=%d selected=%d full=%d',avatar_reads,selected_reads,full_reads))
end)
local action_reader=dofile('private/tests/modules/action_reader.lua')(R,D)
local action_fixture=dofile('tests/action_fixture.lua')
local function input(s)return action_reader.input_snapshot(s.api,s.game,reader)end
local function flag(s,n)
    local at=s.avatar_flags+math.floor(n/32)*4
    s.u32(at,reader.u32(s.api.read(at,4),0)+2^(n%32))
end
local function passenger(s,config,role)
    local manager=s.allocate();s.ptr(s.game+R.global_vehicle,manager)
    s.map(manager+0x20,s.allocate(),{{s.aid,1}})
    local registry=s.allocate();s.ptr(manager+0x38,registry);s.ptr(registry+8,s.eaddr)
    local states=s.allocate();s.ptr(manager+0x48,states);local relation=states+64;s.zero(relation,64)
    local id=s.otherid+100
    s.u32(relation,id);s.u32(relation+4,config);s.u32(relation+8,role);s.u32(relation+0x1c,2)
    s.u32(relation+0x18,0xffffffff);s.u32(relation+0x20,0xffffffff)
    s.map(s.owner+D.entity_id_map,0x42000000,{{s.wid,5},{s.otherid,6},{s.aid,3},{id,7}})
    local entity=s.owner+D.entity_array+7*24;s.zero(entity,24);s.put(entity,'VEHICLE!');s.u32(entity+8,id)
    flag(s,D.seated)
end
for _,case in ipairs({'ground','prone','diving','airborne','map','weapon_menu','dead','ragdoll','native_fire','frv','tank','driver'})do
    check('input observation preserves full avatar/identity vetoes: '..case,function()
        local s=action_fixture('rounds')
        if case=='dead'then s.zero(s.avatar_flags,24)
        elseif case=='native_fire'then s.put(s.fire_state,'\1')
        elseif case=='frv'then passenger(s,1,3)
        elseif case=='tank'then passenger(s,43,3)
        elseif case=='driver'then passenger(s,43,1)
        elseif case~='ground'then
            flag(s,assert(({prone=D.prone,diving=D.diving,airborne=D.airborne,
                map=D.tactical_map,weapon_menu=D.weapon_menu,ragdoll=14})[case]))
        end
        local _,_,full=s.snap();local _,_,light=input(s)
        assert(full and light and full.identity==light.identity and full.interrupt==light.interrupt)
        assert(light.input_only and light.ability_manager==nil and light.weapon_id==nil and light.reload==nil)
        assert(full.same() and light.same())
    end)
end
check('input observation skips ammunition, ability and reload state reads',function()
    local s=action_fixture('rounds');local seen={};local read=s.api.read
    s.api.read=function(at,n)seen[at]=true;return read(at,n)end
    local _,_,cap=input(s);assert(cap and cap.same())
    for _,symbol in ipairs({'global_ability','global_rounds','global_exclusions','global_weapon_owner','global_backpack_reload'})do
        assert(not seen[s.game+R[symbol]],symbol)
    end
end)
check('input observation keeps descriptor, function and weapon-kind admission',function()
    for _,change in ipairs({
        function(s)s.u32(s.templates+D.ability_capacity*16,999)end,
        function(s)s.u32(0x4a000000+D.weapon_data_stride+D.weapon_types,12)end,
        function(s)s.u32(s.driver_state,0)end})do
        local s=action_fixture('rounds');change(s)
        local row,_,cap=input(s);assert(row and row.action_context_status=='rejected' and cap==nil)
    end
end)
check('input observation rechecks Fire and avatar veto bytes before reuse',function()
    local s=action_fixture('rounds');local _,_,cap=input(s);assert(cap and cap.same())
    s.put(s.fire_state,'\1');assert(not cap.same())
    _,_,cap=input(s);assert(cap and cap.interrupt and cap.same())
    flag(s,D.tactical_map);assert(not cap.same())
end)
check('retained routing and full snapshots are revalidated after every mutator and phase',function()
    local file=assert(io.open('src/ActionBackend.lua'));local source=file:read('*a');file:close()
    local resolver={resolve=function()return {symbols={},fields={},verify=function()end}end}
    local passenger_hold={new=function()return {stop=function()return true end}end}
    local construct=assert(loadstring('return function(NativeResolver,SnapshotCache,PassengerHold,RoutingReader)\nlocal R,D\n'..source..'\nend'))()
    local full,input_reads,full_checks,input_checks,changed=0,0,0,0,false
    local function current()return not changed end
    local reader_mock={snapshot=function()
            full=full+1
            return {},nil,{same=current},function()full_checks=full_checks+1;return current()end
        end,
        input_snapshot=function()
            input_reads=input_reads+1
            return {},nil,{same=current},function()input_checks=input_checks+1;return current()end
        end}
    local backend_module=construct(resolver,dofile('src/SnapshotCache.lua'),passenger_hold,
        {snapshot=reader_mock.input_snapshot})
    local native={}
    for _,name in ipairs({'start','consume','after','lean','reload','input_inhibit','input_unblock'})do native[name]=function()end end
    local api={module=function()return 0x10000000 end,fire_gate_exchange=function()end,passenger_exchange=function()end}
    local backend=backend_module.new(api,reader_mock,{}, {},function()return native end,function()return true end)
    local function pair()
        backend.snapshot();backend.snapshot();backend.input_snapshot();backend.input_snapshot()
    end
    -- The first walk guards its bytes; uses in the same phase share it.
    backend.begin_phase('before');pair()
    assert(full==1 and input_reads==1 and full_checks==0 and input_checks==0)
    -- Every mutator forces exactly one complete guard comparison per snapshot
    -- before it is used again; unchanged bytes never need a second walk.
    local expected=0
    local function revalidated()
        expected=expected+1;pair()
        assert(full==1 and input_reads==1 and full_checks==expected and input_checks==expected)
    end
    for _,name in ipairs({'start','consume','after','lean','reload','input_inhibit','input_unblock'})do native[name]();revalidated()end
    api.fire_gate_exchange();revalidated();api.passenger_exchange();revalidated()
    backend.invalidate();revalidated();backend.end_phase();backend.begin_phase('after');revalidated()
    -- A changed guard discards the entry and the walk is repeated.
    changed=true;backend.invalidate()
    backend.snapshot();backend.input_snapshot()
    assert(full==2 and input_reads==2)
    -- Outside a phase nothing is retained or reused.
    changed=false;backend.end_phase();pair();assert(full==4 and input_reads==4)
    assert(not pcall(backend.execute,'DETONATE',{input_only=true},0))
end)
local scenario=dofile('tests/gamepad_entry_fixture.lua')
local function runtime()
    local values={deploy=false,detonate=false}
    _G.ModBindingsMenu={api=1,version=2,ready=function()return true end,
        register_binding=function()return true end,is_down=function(id)return values[id:match('%.([^%.]+)$')]end}
    local s=scenario{entry='private/build/c4_quick_actions.off.lua',window=true,native_ui=true,aim_profile=true}
    s.values=values
    for _=1,8 do s.tick()end
    assert(not s.module.disabled and s.mask_mode()==1 and s.fire_mask_mode()==1)
    return s
end
for _,failure in ipairs({'unsupported_ammo','unreadable_ammo'})do
    check('full context '..failure..' releases input masks after original update',function()
        local s=runtime()
        s.original_hook=function()
            s.original_hook=nil
            if failure=='unsupported_ammo'then s.u32(s.rounds_runtime+4,2)
            else s.intercept=function(at,n)if at==s.rounds_state and n==24 then return nil,true end end end
        end
        s.tick()
        assert(not s.module.disabled,s.module.status)
        assert(s.mask_mode()==0 and s.fire_mask_mode()==0,'invalid full context retained input inhibition')
        for _=1,3 do s.tick()end
        assert(s.mask_mode()==0 and s.fire_mask_mode()==0,'invalid full context reacquired input inhibition')
        assert(s.inhibit_calls==1 and s.fire_inhibit_calls==1)
        s.intercept=nil;s.u32(s.rounds_runtime+4,0);s.tick()
        assert(s.mask_mode()==1 and s.fire_mask_mode()==1,'valid context did not resume')
        assert(_G.shutdown()=='shutdown-original')
    end)
end
check('missing reload-only context does not release valid C4 input ownership',function()
    local s=runtime();local _,_,cap=s.snap();assert(cap and not cap.reload)
    for _=1,4 do s.tick()end
    assert(s.mask_mode()==1 and s.fire_mask_mode()==1)
    assert(s.inhibit_calls==1 and s.fire_inhibit_calls==1)
    assert(_G.shutdown()=='shutdown-original')
end)
check('faulted action still releases input masks when full context later fails',function()
    local s=runtime()
    s.native.start=function()end -- native action does not enter its promised lifecycle
    s.values.deploy=true;s.tick();s.values.deploy=false
    assert(not s.module.disabled,s.module.status)
    s.original_hook=function()s.original_hook=nil;s.u32(s.rounds_runtime+4,2)end
    s.tick()
    assert(not s.module.disabled,s.module.status)
    assert(s.mask_mode()==0 and s.fire_mask_mode()==0,'fault skipped authoritative context rejection')
    s.u32(s.rounds_runtime+4,0)
    assert(_G.shutdown()=='shutdown-original')
end)
