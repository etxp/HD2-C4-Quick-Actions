local scenario=dofile('tests/gamepad_entry_fixture.lua')
local R=dofile('private/tests/mock_symbols.lua')
local D=dofile('private/tests/mock_fields.lua')
local bit=require('bit')
local function check(name,fn) fn();print('PASS '..name) end
local function fresh(missing,extra)
    local values={deploy=false,detonate=false}
    local registered={}
    _G.ModBindingsMenu=not missing and {api=1,version=2,ready=function()return true end,
        register_binding=function(id,label,slot,options)
            assert(slot==0 and options.category=='HD2 C4 Quick Actions')
            assert(label=='Throw C4' or label=='Detonate C4')
            registered[id]=true;return true
        end,is_down=function(id)return values[id:match('%.([^%.]+)$')] end} or nil
    local options={entry='private/build/c4_quick_actions.lua',window=true,native_ui=true,pad_profile='xbox'}
    for k,v in pairs(extra or {}) do options[k]=v end
    local s=scenario(options)
    s.values=values;s.registered=registered
    for i=1,8 do s.tick() end
    assert(not s.module.disabled,s.module.status)
    function s.press(action)values[action]=true;s.tick();values[action]=false;s.tick() end
    function s.pose_flags(flags)
        s.zero(s.avatar_flags,24);s.u32(s.avatar_flags,2)
        for _,flag in ipairs(flags) do
            local address=s.avatar_flags+math.floor(flag/32)*4
            local raw=s.api.read(address,4);local a,b,c,d=raw:byte(1,4)
            s.u32(address,a+b*256+c*65536+d*16777216+2^(flag%32))
        end
    end
    return s
end
for _,pointer in ipairs({'\96\238\89\194\246\127\0\0','\96\238\89\50\255\111\0\0'}) do
    check('relocated native pointer table still registers both MBM actions and executes C4',function()
        local s=fresh(false,{native_pointer_value=pointer})
        assert(s.registered['etxp.c4_quick_actions.deploy'] and s.registered['etxp.c4_quick_actions.detonate'])
        s.press('deploy');assert(#s.calls==4 and s.calls[1][2]==521)
        s.finish();s.press('detonate');assert(s.calls[5][2]==520)
    end)
end
check('MBM-only two stable bindings execute native C4 actions',function()
    local s=fresh();assert(s.flags()==0x148)
    assert(s.registered['etxp.c4_quick_actions.deploy'] and s.registered['etxp.c4_quick_actions.detonate'])
    s.press('deploy');assert(#s.calls==4 and s.calls[1][2]==521)
    s.finish();s.press('detonate');assert(s.calls[5][2]==520)
end)
check('physical mouse and triggers have no direct C4 route',function()
    local s=fresh();s.button(0,true);s.button(0,false);s.button(1,true);s.button(1,false)
    s.trigger('left',0.8);s.trigger('left',0);s.trigger('right',0.8);s.trigger('right',0)
    assert(#s.calls==0 and #s.vanilla==0)
end)
check('missing MBM leaves native fire ownership alone',function()
    local s=fresh(true);assert(s.flags()==0x2148 and #s.calls==0)
end)
check('both actions in one activation prefer detonation',function()
    local s=fresh();s.values.deploy=true;s.values.detonate=true;s.tick()
    assert(#s.calls==1 and s.calls[1][2]==520)
end)
for _,pose in ipairs({{'prone',D.prone},{'dive',D.diving},{'airborne',D.airborne},{'airborne dive',D.diving,D.airborne}}) do
    check(pose[1]..' permits throw and detonate without requiring combined pose flags',function()
        local s=fresh();local flags={};for i=2,#pose do flags[#flags+1]=pose[i] end
        s.pose_flags(flags);s.press('deploy');assert(#s.calls==4,s.module.status)
        s.finish();s.press('detonate');assert(s.calls[5][2]==520)
    end)
end
for _,block in ipairs({'UI','map','death','unclassified interrupt'}) do
    check(block..' blocks MBM actions',function()
        local s=fresh()
        if block=='UI' then s.ui(11)
        elseif block=='map' then s.pose_flags{D.tactical_map}
        elseif block=='death' then s.zero(s.avatar_flags,24)
        else s.pose_flags{D.blocked[1]} end
        s.press('deploy');s.press('detonate');assert(#s.calls==0)
    end)
end
check('opening UI during engine update discards the sampled activation',function()
    local s=fresh();s.original_hook=function()s.ui(11);s.original_hook=nil end
    s.press('deploy');assert(#s.calls==0)
    s.ui();for _=1,10 do s.tick() end;assert(#s.calls==0)
    s.press('deploy');assert(#s.calls==4)
end)
check('held activation across focus loss needs release and a fresh activation',function()
    local s=fresh();s.focused=false;s.values.deploy=true;s.tick();s.focused=true
    for _=1,10 do s.tick() end;assert(#s.calls==0)
    s.values.deploy=false;s.tick();s.press('deploy');assert(#s.calls==4)
end)
check('API reset while activation held does not throw',function()
    local s=fresh();local old=_G.ModBindingsMenu
    _G.ModBindingsMenu=nil;s.tick();s.values.deploy=true;_G.ModBindingsMenu=old;s.tick()
    for _=1,10 do s.tick() end;assert(#s.calls==0)
    s.values.deploy=false;s.tick();s.press('deploy');assert(#s.calls==4)
end)
local function seat(s,config,seat,role)
    local manager=s.allocate();s.ptr(s.game+R.global_vehicle,manager)
    s.map(manager+0x20,s.allocate(),{{s.aid,1}})
    local registry=s.allocate();s.ptr(manager+0x38,registry);s.ptr(registry+8,s.eaddr)
    local states=s.allocate();s.ptr(manager+0x48,states);local row=states+64;s.zero(row,64)
    s.u32(row+0x18,0xffffffff);s.u32(row+0x20,0xffffffff)
    s.seat_row=row;s.seat_manager=manager;s.seat_registry=registry
    local id=s.otherid+100;s.u32(row,id);s.u32(row+4,config);s.u32(row+8,role or 3);s.u32(row+0x1c,seat)
    s.map(s.owner+D.entity_id_map,0x42000000,{{s.wid,5},{s.otherid,6},{s.aid,3},{id,7}})
    local entity=s.owner+D.entity_array+7*24;s.zero(entity,24);s.put(entity,'VEHICLE!');s.u32(entity+8,id)
    s.pose_flags{D.seated};s.lean_calls=0
    function s.leaned(value,transition)s.put(row+0x30,transition and '\1' or '\0');s.put(row+0x31,value and '\1' or '\0')end
    s.native.lean=function(m,a)
        assert(m==manager and a==s.aid);s.lean_calls=s.lean_calls+1;s.leaned(true,true)
    end
end
-- Exercise every current engine switch entry, including both tank variants.
for config=1,45 do for _,index in ipairs({2,3}) do
    check('vehicle '..config..' passenger '..index..' waits for native lean then throws',function()
        local s=fresh();seat(s,config,index);s.press('deploy')
        assert(s.lean_calls==1 and #s.calls==0,s.module.status)
        for _=1,10 do s.tick() end;assert(#s.calls==0 and s.lean_calls==1)
        s.leaned(true,false);s.tick();assert(#s.calls==4)
        s.finish();s.press('detonate');assert(s.calls[5][2]==520)
    end)
end end
check('passenger admission has no seat-number whitelist',function()
    local s=fresh();seat(s,12,9);s.press('deploy');assert(s.lean_calls==1)
    s.leaned(true,false);s.tick();assert(#s.calls==4)
end)
for _,config in ipairs({27,43,44,99}) do
    check('unleaned passenger detonates independently of model '..config,function()
        local s=fresh();seat(s,config,2);s.press('detonate')
        assert(s.lean_calls==0 and #s.calls==1 and s.calls[1][2]==520)
    end)
end
for _,role in ipairs({0,1,2}) do
    check('non-passenger role '..role..' does not enter passenger flow',function()
        local s=fresh();seat(s,43,2,role);s.press('deploy');s.press('detonate')
        assert(s.lean_calls==0 and #s.calls==0)
    end)
end
for _,v in ipairs({{43,0},{43,1},{99,2}}) do
    check('engine reports no lean for '..v[1]..' seat '..v[2]..' without blocking detonation',function()
        local s=fresh();seat(s,v[1],v[2]);s.press('deploy')
        assert(s.lean_calls==0 and #s.calls==0 and not s.module.disabled)
        s.press('detonate');assert(#s.calls==1 and s.calls[1][2]==520)
    end)
end
check('already leaned passenger throws without toggling back inside',function()
    local s=fresh();seat(s,43,2);s.leaned(true,false);s.press('deploy')
    assert(s.lean_calls==0 and #s.calls==4)
end)
for _,interrupt in ipairs({'UI','map','seat change','weapon change'}) do
    check(interrupt..' cancels pending passenger throw',function()
        local s=fresh();seat(s,43,2);s.press('deploy');assert(s.lean_calls==1)
        if interrupt=='UI' then s.ui(11)
        elseif interrupt=='map' then s.pose_flags{D.seated,D.tactical_map}
        elseif interrupt=='seat change' then seat(s,43,3)
        else s.u32(s.state+0x1c,0) end
        s.leaned(true,false);for _=1,10 do s.tick() end
        assert(#s.calls==0)
    end)
end
-- Actual failing session's passenger poses, stripped of IDs and personal data.
for _,case in ipairs(dofile('tests/tank_passenger_poses.lua')) do
    check('recorded tank passenger pose '..case.label..' permits detonation',function()
        local s=fresh();seat(s,43,case.seat);s.leaned(case.leaned,case.transition)
        s.pose_flags(case.flags);s.press('detonate')
        assert(#s.calls==1 and s.calls[1][2]==520,s.module.status)
    end)
end
check('weapon switching releases C4 fire lease and cancels queued input',function()
    local s=fresh();s.press('deploy');s.press('deploy');s.u32(s.state+0x1c,0);s.tick()
    assert(s.flags()==0x2148)
    s.button(0,true);assert(s.vanilla[#s.vanilla]=='OTHER_WEAPON')
    s.button(0,false);s.u32(s.state+0x1c,3);s.finish();assert(#s.calls==4)
end)

local function throwing()
    local s=fresh();seat(s,43,2);s.leaned(true,false)
    s.original_seat=s.api.read(s.seat_row,64)
    s.press('deploy')
    assert(not s.module.disabled,s.module.status)
    assert(s.api.read(s.seat_row+0x30,2)=='\1\1',s.module.status)
    assert(#s.passenger_writes==1 and #s.calls==4)
    return s
end
local function released(s)
    assert(s.api.read(s.seat_row,64)==s.original_seat,'passenger state not restored')
    assert(#s.passenger_writes==2 and s.passenger_writes[2].byte=='\0')
end
check('release-to-throw keeps the whole native ability leaned out, with no fixed release delay',function()
    local s=throwing()
    -- Model the verified native lean command's busy check, with physical Aim up.
    s.original_hook=function()
        if s.api.read(s.seat_row+0x30,1)=='\0' then s.leaned(false,false) end
    end
    for _=1,90 do s.tick();assert(s.api.read(s.seat_row+0x31,1)=='\1') end
    assert(#s.calls==4 and #s.passenger_writes==1 and s.lean_calls==0)
    s.complete();s.tick()
    assert(s.api.read(s.seat_row+0x30,2)=='\0\0' and #s.passenger_writes==2)
    assert(not s.module.disabled,s.module.status)
end)
check('finishing a throw restores only busy state and preserves the native aim/lean state',function()
    local s=throwing();s.complete();s.tick();released(s)
    assert(s.api.read(s.seat_row+0x31,1)=='\1' and #s.calls==4)
end)
for _,cause in ipairs({'UI','map','focus','weapon','pose','ability replaced','MBM missing'}) do
    check(cause..' releases an ongoing passenger throw reservation',function()
        local s=throwing()
        if cause=='UI' then s.ui(11)
        elseif cause=='map' then s.pose_flags{D.seated,D.tactical_map}
        elseif cause=='focus' then s.focused=false
        elseif cause=='weapon' then s.u32(s.state+0x1c,0)
        elseif cause=='pose' then s.pose_flags{D.seated,D.blocked[1]}
        elseif cause=='ability replaced' then s.u32(s.ability_state,520)
        else _G.ModBindingsMenu=nil end
        s.tick();released(s);assert(#s.calls==4)
    end)
end
check('shutdown restores the passenger byte and chains the original callback',function()
    local s=throwing();assert(shutdown()=='shutdown-original');released(s)
end)
check('original update errors restore the passenger byte before propagating',function()
    local s=throwing();s.original_error=true
    local ok,why=pcall(s.tick);assert(not ok and tostring(why):find('fixture_original_error',1,true))
    released(s)
end)
check('stuck native ability has an eight-second release watchdog',function()
    local s=throwing();s.tick(8.1);released(s)
end)
check('temporary write failure retries restoration while disabled',function()
    local s=throwing();s.fail_passenger_writes=true;s.complete();s.tick()
    assert(s.module.disabled and s.api.read(s.seat_row+0x30,1)=='\1')
    s.fail_passenger_writes=false;s.tick()
    assert(s.api.read(s.seat_row,64)==s.original_seat)
end)
check('temporary read failure retries restoration while disabled',function()
    local s=throwing();s.fail_reads=true;s.tick();assert(s.module.disabled)
    s.fail_reads=false;s.tick();released(s)
end)
check('component compaction restores the re-resolved row, never its old address',function()
    local s=throwing();local old=s.seat_row;local moved=s.allocate()
    s.put(moved,s.api.read(old,64));s.zero(old,64)
    s.ptr(s.seat_manager+0x48,moved-64);s.seat_row=moved
    s.tick();released(s);assert(s.api.read(old,64)==string.rep('\0',64))
end)
check('native seat transition takes ownership and is never overwritten by cleanup',function()
    local s=throwing();s.u32(s.seat_row+0x18,3);s.u32(s.seat_row+0x20,17)
    local next_state=s.api.read(s.seat_row,64);s.tick()
    assert(s.api.read(s.seat_row,64)==next_state and #s.passenger_writes==1)
    assert(s.lines[#s.lines]:find('relation_changed_by_engine',1,true) or not s.module.disabled)
end)
check('world replacement prevents restoration into obsolete entity storage',function()
    local s=throwing();s.ptr(s.game+R.global_vehicle,s.allocate());s.tick()
    assert(#s.passenger_writes==1)
end)
check('reused avatar entity prevents stale restoration',function()
    local s=throwing();s.put(s.eaddr,'REUSED!!');s.tick();assert(#s.passenger_writes==1)
end)
check('passenger detonation and on-foot throws never reserve the seat',function()
    local s=fresh();s.press('deploy');assert(#s.passenger_writes==0)
    s=fresh();seat(s,43,2);s.leaned(true,false);s.press('detonate');assert(#s.passenger_writes==0)
end)
check('invalid pending seat animation prevents acquiring a passenger reservation',function()
    local s=fresh();seat(s,43,2);s.leaned(true,false);s.u32(s.seat_row+0x20,17)
    s.press('deploy');assert(#s.passenger_writes==0 and #s.calls==0)
end)
check('changed native code revokes admission before native calls or passenger writes',function()
    local s=fresh();seat(s,43,2);s.leaned(true,false);s.bad_code=true;s.press('deploy')
    assert(#s.calls==0 and #s.passenger_writes==0)
end)

local function reload_setup(s,path)
    local ffi=require('ffi')
    -- Same component as the existing exclusion flags, as in the real capture.
    s.reload_manager=s.exclusions
    s.map(s.reload_manager+0x20,s.allocate(),{{s.wid,1}})
    local registry=s.allocate();s.ptr(s.reload_manager+0x38,registry);s.ptr(registry+8,s.waddr)
    s.map(s.reload_manager+0x60,s.allocate(),{})
    local templates=s.allocate();s.ptr(s.owner+D.reload_templates,templates)
    s.zero(templates,D.reload_capacity*16+D.reload_stride)
    -- Exact uint64 resource modulo 498, independently computed in Python.
    s.put(templates+227*16,s.weapon:sub(1,8));s.u32(templates+227*16+8,0)
    s.reload_config=templates+D.reload_capacity*16;s.reload_id=0xb0b
    s.u32(s.reload_config,0x101) -- live config permits the normal C4 reload path
    s.u32(s.reload_config+4,s.reload_id)
    -- Match the live C4 profile: selected magazine and local reserve stay zero;
    -- spare charges live in the equipped backpack, while the generic supply
    -- relation points to the avatar (which has no resource counter).
    s.u32(s.rounds_state+4,0);s.u32(s.rounds_state+16,55)
    s.reload_supply=s.allocate();s.ptr(s.game+R.global_reload_supply,s.reload_supply)
    s.map(s.reload_supply+0x18,s.allocate(),{{s.wid,1}})
    local supply_rows=s.allocate();s.ptr(s.reload_supply+0x38,supply_rows)
    s.supply_row=supply_rows+D.reload_supply_stride;s.u32(s.supply_row,0xdef)
    s.map(s.owner+D.unit_entity_id_map,s.allocate(),{{0xdef,path=='supply' and s.otherid or s.aid}})
    s.backpack_reload=s.allocate();s.ptr(s.game+R.global_backpack_reload,s.backpack_reload)
    s.map(s.backpack_reload+0x18,s.allocate(),path=='supply' and {} or {{s.wid,1}})
    s.u32(s.state+12,s.otherid)
    if path=='supply' then s.put(s.reload_config+0x3c,'\1') end
    s.map(s.counter+0x20,s.allocate(),{{s.otherid,1}})
    local cr=s.allocate();s.ptr(s.counter+0x38,cr);s.ptr(cr+8,s.owner+D.entity_array+6*24)
    s.spare_state=s.counter_state;s.u32(s.spare_state,6)
    local owners=s.allocate();s.ptr(s.game+R.global_weapon_owner,owners)
    s.map(owners+0x18,s.allocate(),{{s.wid,1}})
    s.reload_owner_state=s.allocate();s.ptr(owners+0x38,s.reload_owner_state);s.u32(s.reload_owner_state+4,s.aid)
    s.map(s.ability+0x18,s.allocate(),{{s.wid,1},{s.aid,2}})
    local ar=assert(s.api.pointer(s.api.read(s.ability+0x30,8)));s.ptr(ar+16,s.eaddr)
    s.avatar_ability_state=s.ability_state+0xe0;s.zero(s.avatar_ability_state,0xe0)
    s.reload_calls=0;s.reload_queries=0;s.reload_allowed=true
    function s.phase(n)
        s.put(s.ability_state+8,ffi.string(ffi.new('float[1]',n/60),4))
    end
    function s.avatar_action(id,active,time)
        s.u32(s.avatar_ability_state,id);s.put(s.avatar_ability_state+16,active and '\1' or '\0')
        s.put(s.avatar_ability_state+8,ffi.string(ffi.new('float[1]',time or 0),4))
    end
    s.native.reload_eligible=function(manager,id,ignore_action,ignore_owned)
        assert(manager==s.reload_manager and id==s.wid and ignore_action==false and ignore_owned==false)
        s.reload_queries=s.reload_queries+1;return s.reload_allowed
    end
    s.native.reload=function(manager,id,force)
        assert(manager==s.reload_manager and id==s.wid and force==false)
        s.reload_calls=s.reload_calls+1
        s.u32(s.avatar_ability_state,s.reload_id);s.put(s.avatar_ability_state+16,'\1')
    end
    s.tick()
    local row,_,cap=s.snap();assert(cap and cap.reload,row and row.reload_context or 'no reload context')
    return s
end
check('on-foot reload starts after native release phase, never from Lua elapsed time alone',function()
    local s=reload_setup(fresh());s.press('deploy');assert(s.reload_calls==0)
    s.tick(0.7);assert(s.reload_calls==0) -- native clock is deliberately still zero
    s.phase(9);s.tick();assert(s.reload_calls==0)
    s.phase(10.1);s.tick();assert(s.reload_calls==1 and s.reload_queries==1)
    for _=1,20 do s.tick() end;assert(s.reload_calls==1)
    assert(#s.calls==4 and #s.passenger_writes==0 and not s.module.disabled,s.module.status)
end)
check('paused native ability never authorizes early reload',function()
    local s=reload_setup(fresh());s.press('deploy');s.phase(15);s.put(s.ability_state+17,'\1')
    s.tick();assert(s.reload_calls==0)
    s.put(s.ability_state+17,'\0');s.tick();assert(s.reload_calls==1)
end)
check('passenger reload waits for full throw and releases lean reservation first',function()
    local s=reload_setup(fresh());seat(s,43,2);s.leaned(true,false);s.press('deploy')
    s.phase(15);s.tick();assert(s.reload_calls==0 and s.api.read(s.seat_row+0x30,1)=='\1')
    s.complete();s.tick();assert(s.reload_calls==0 and s.api.read(s.seat_row+0x30,1)=='\0')
    for _=1,3 do s.tick(0.1) end;assert(s.reload_calls==1)
end)
check('native reload veto is respected and a later eligible frame can proceed',function()
    local s=reload_setup(fresh());s.reload_allowed=false;s.press('deploy');s.phase(11)
    s.tick();assert(s.reload_calls==0 and s.reload_queries==1)
    s.reload_allowed=true;s.tick();assert(s.reload_calls==1)
end)
check('completed short throw still offers one native reload',function()
    local s=reload_setup(fresh());s.press('deploy');s.complete();s.tick();assert(s.reload_calls==1)
end)
check('exhausted ammunition does not query or request a reload',function()
    local s=reload_setup(fresh());s.u32(s.spare_state,0)
    s.press('deploy');s.phase(11);s.tick();s.complete();s.tick()
    assert(s.reload_calls==0 and s.reload_queries==0)
end)
check('empty then resupplied automatically reloads the chamber once',function()
    local s=reload_setup(fresh());s.u32(s.spare_state,0);s.u32(s.rounds_state+16,0);s.tick()
    s.u32(s.spare_state,4);s.tick();assert(s.reload_calls==1)
    s.put(s.avatar_ability_state+16,'\0') -- player cancels native reload before chambering
    for _=1,20 do s.tick() end;assert(s.reload_calls==1,'cancelled reload repeated')
end)
check('resupply with an already loaded chamber does not reload',function()
    local s=reload_setup(fresh());s.u32(s.spare_state,0);s.tick()
    s.u32(s.spare_state,4);s.tick();assert(s.reload_calls==0)
end)
for _,cause in ipairs({'UI','map','focus','weapon','avatar action','MBM','detonate'}) do
    check(cause..' interrupts the auto-reload opportunity without replay',function()
        local s=reload_setup(fresh());s.press('deploy')
        local oldmbm=_G.ModBindingsMenu
        if cause=='UI' then s.ui(11)
        elseif cause=='map' then s.pose_flags{D.tactical_map}
        elseif cause=='focus' then s.focused=false
        elseif cause=='weapon' then s.u32(s.state+0x1c,0)
        elseif cause=='avatar action' then s.u32(s.avatar_ability_state,333);s.put(s.avatar_ability_state+16,'\1')
        elseif cause=='MBM' then _G.ModBindingsMenu=nil
        else s.values.detonate=true end
        s.tick();s.values.detonate=false;s.ui();s.pose_flags{};s.focused=true
        s.u32(s.state+0x1c,3);s.put(s.avatar_ability_state+16,'\0');_G.ModBindingsMenu=oldmbm
        s.phase(11);for _=1,10 do s.tick() end;assert(s.reload_calls==0)
    end)
end
check('resupply waits for the already-running action before requesting one reload',function()
    local s=reload_setup(fresh());s.u32(s.spare_state,0);s.u32(s.rounds_state+16,0);s.tick()
    s.u32(s.avatar_ability_state,333);s.put(s.avatar_ability_state+16,'\1')
    s.u32(s.spare_state,4);s.tick();s.put(s.avatar_ability_state+16,'\0');s.tick()
    assert(s.reload_calls==1)
end)
check('a queued next throw can benefit from auto reload but a queued detonation takes priority',function()
    local s=reload_setup(fresh());s.press('deploy');s.press('deploy');s.phase(11);s.tick()
    assert(s.reload_calls==1)
    s=reload_setup(fresh());s.press('deploy');s.press('detonate');s.phase(11);s.tick()
    assert(s.reload_calls==0)
end)
check('reload context identity mismatch disables only auto reload',function()
    local s=reload_setup(fresh());s.u32(s.reload_owner_state+4,s.otherid)
    s.press('deploy');s.phase(11);s.tick()
    assert(#s.calls==4 and s.reload_calls==0 and not s.module.disabled,s.module.status)
end)
check('special mutating eligibility branch is rejected before a native query',function()
    local s=reload_setup(fresh());s.u32(s.reload_config+4,0xb17)
    s.press('deploy');s.phase(11);s.tick();assert(s.reload_queries==0 and s.reload_calls==0 and #s.calls==4)
end)
check('native reload already started by the engine is not duplicated',function()
    local s=reload_setup(fresh());s.press('deploy');s.phase(11)
    s.u32(s.avatar_ability_state,s.reload_id);s.put(s.avatar_ability_state+16,'\1');s.tick()
    assert(s.reload_queries==0 and s.reload_calls==0)
end)
check('native code mutation blocks an auto reload',function()
    local s=reload_setup(fresh());s.press('deploy');s.phase(11);s.bad_code=true;s.tick()
    assert(s.reload_calls==0 and s.reload_queries==0 and s.module.disabled)
end)
check('pre-call log flush failure blocks an auto reload',function()
    local s=reload_setup(fresh());s.press('deploy');s.phase(11);s.flush_failure=true;s.tick()
    assert(s.reload_queries==1 and s.reload_calls==0 and s.module.disabled)
end)
check('invalid native clock never triggers early reload or disables ordinary C4 actions',function()
    local s=reload_setup(fresh());s.press('deploy');s.u32(s.ability_state+8,0x7fc00000);s.tick()
    assert(s.reload_calls==0 and not s.module.disabled,s.module.status)
    s.complete();s.tick();assert(s.reload_calls==1)
end)
check('native eligibility timeout expires without a later replay',function()
    local s=reload_setup(fresh());s.reload_allowed=false;s.press('deploy');s.phase(11);s.tick()
    assert(s.reload_queries==1);s.tick(1.6);s.reload_allowed=true;s.tick()
    assert(s.reload_queries==1 and s.reload_calls==0)
end)
check('per-entity reload override is resolved with its own ability ID',function()
    local s=reload_setup(fresh());local configs=s.allocate()
    s.ptr(s.reload_manager+0xa0,configs);s.zero(configs+80,80);s.reload_id=0x790
    s.u32(configs+80+4,s.reload_id)
    s.map(s.reload_manager+0x60,s.allocate(),{{s.wid,1}})
    s.press('deploy');s.phase(11);s.tick();assert(s.reload_calls==1)
end)

check('live C4 reads the equipped backpack instead of the generic avatar supply relation',function()
    local s=reload_setup(fresh());local row,_,cap=s.snap()
    assert(row.rounds_magazine_count==0 and row.rounds_reserve_count==0)
    assert(s.api.read(s.reload_config+0x3c,1)=='\0')
    assert(row.reload_supply_count==6 and row.reload_spare_ammo==6 and cap.reload.ammo==6)
    assert(row.reload_supply_source=='equipped_backpack' and row.reload_supply_unit==nil)
    assert(row.reload_supply_entity_id==s.otherid)
end)
check('selected magazine growth is not mistaken for receiving spare ammunition',function()
    local s=reload_setup(fresh());s.u32(s.spare_state,0);s.u32(s.rounds_state+16,0);s.tick()
    s.u32(s.rounds_state+4,4);s.tick();assert(s.reload_calls==0 and s.reload_queries==0)
end)
check('generic supply relation is ignored when config disables it and no backpack branch exists',function()
    local s=reload_setup(fresh(),'supply');s.put(s.reload_config+0x3c,'\0')
    local row,_,cap=s.snap()
    assert(cap.reload.ammo==0 and row.reload_supply_source=='local_reserve_only')
    s.press('deploy');s.complete();s.tick();assert(s.reload_calls==0)
end)
check('enabled generic supply branch still resolves its own resource entity',function()
    local s=reload_setup(fresh(),'supply');local row,_,cap=s.snap()
    assert(cap.reload.ammo==6 and row.reload_supply_source=='weapon_linked_resource_counter')
    s.press('deploy');s.complete();s.tick();assert(s.reload_calls==1)
end)
check('a missing backpack is empty and does not fall back to the avatar unit relation',function()
    local s=reload_setup(fresh());s.u32(s.state+12,0)
    local row,_,cap=s.snap()
    assert(cap.reload.ammo==0 and row.reload_supply_source=='no_equipped_backpack')
    s.press('deploy');s.complete();s.tick();assert(s.reload_calls==0 and not s.module.disabled)
end)
check('replacing the equipped backpack invalidates the previously read reload context',function()
    local s=reload_setup(fresh());local _,_,cap=s.snap();assert(cap.same())
    s.u32(s.state+12,0);assert(not cap.same())
end)
check('positive backpack ammo never bypasses native backpack compatibility veto',function()
    local s=reload_setup(fresh());s.reload_allowed=false
    s.press('deploy');s.complete();s.tick();assert(s.reload_queries>0 and s.reload_calls==0)
end)
check('backpack replenishment is logged at its actual transition',function()
    local s=reload_setup(fresh());s.u32(s.spare_state,0);s.u32(s.rounds_state+16,0);s.tick()
    s.u32(s.spare_state,4);s.tick()
    local found=false
    for _,line in ipairs(s.lines) do
        if line:find('reload_ammo_observed',1,true) and line:find('"reload_spare_ammo":4',1,true)
            and line:find('equipped_backpack',1,true) then found=true end
    end
    assert(found and s.reload_calls==1)
end)
check('actual local reserve works when there is no external supply relation',function()
    local s=reload_setup(fresh());s.map(s.backpack_reload+0x18,s.allocate(),{})
    s.u32(s.rounds_runtime,3);local row,_,cap=s.snap()
    assert(cap.reload.ammo==3 and row.reload_supply_count==0)
    s.press('deploy');s.complete();s.tick();assert(s.reload_calls==1)
end)
check('local and external spare ammunition are counted once each',function()
    local s=reload_setup(fresh());s.u32(s.rounds_runtime,2)
    local row,_,cap=s.snap();assert(cap.reload.ammo==8 and row.rounds_magazine_count==0)
end)
for _,vehicle in ipairs({27,43,44}) do
    check('zero-magazine passenger resupply requests one reload for vehicle '..vehicle,function()
        local s=reload_setup(fresh());seat(s,vehicle,2);s.leaned(true,false)
        s.u32(s.spare_state,0);s.u32(s.rounds_state+16,0);s.tick()
        s.u32(s.spare_state,4);s.tick();assert(s.reload_calls==0)
        for _=1,3 do s.tick(0.1) end;assert(s.reload_calls==1)
        for _=1,10 do s.tick() end;assert(s.reload_calls==1)
    end)
end
for _,cause in ipairs({'UI','map','focus','weapon'}) do
    check('resupply during '..cause..' is not replayed afterward',function()
        local s=reload_setup(fresh());s.u32(s.spare_state,0);s.u32(s.rounds_state+16,0);s.tick()
        if cause=='UI' then s.ui(11)
        elseif cause=='map' then s.pose_flags{D.tactical_map}
        elseif cause=='focus' then s.focused=false
        else s.u32(s.state+0x1c,0) end
        s.tick();s.u32(s.spare_state,4);s.tick()
        s.ui();s.pose_flags{};s.focused=true;s.u32(s.state+0x1c,3)
        for _=1,10 do s.tick() end;assert(s.reload_calls==0)
    end)
end
check('a changed supply counter invalidates the previously read capability',function()
    local s=reload_setup(fresh());local _,_,cap=s.snap();assert(cap.same())
    s.u32(s.spare_state,5);assert(not cap.same())
end)
for _,cause in ipairs({'unit mapping','entity identity','counter registry','invalid count'}) do
    check('invalid reload supply '..cause..' preserves ordinary C4 actions',function()
        local s=reload_setup(fresh(),cause=='unit mapping' and 'supply' or nil)
        if cause=='unit mapping' then s.map(s.owner+D.unit_entity_id_map,s.allocate(),{})
        elseif cause=='entity identity' then s.u32(s.owner+D.entity_array+6*24+8,s.aid)
        elseif cause=='counter registry' then
            local registry=assert(s.api.pointer(s.api.read(s.counter+0x38,8)));s.ptr(registry+8,s.eaddr)
        else s.u32(s.spare_state,0xffffffff) end
        local row,_,cap=s.snap();assert(cap and not cap.reload and row.reload_context~='verified')
        s.press('deploy');s.complete();s.tick()
        assert(#s.calls==4 and s.reload_calls==0 and not s.module.disabled,s.module.status)
    end)
end

local function resupply_during_action()
    local s=reload_setup(fresh());s.u32(s.spare_state,0);s.u32(s.rounds_state+16,0);s.tick()
    s.avatar_action(2067,true,0.1);s.u32(s.spare_state,6);s.tick()
    assert(s.reload_calls==0 and s.reload_queries==0)
    return s
end
check('live resupply action finishes before one reload and is never interrupted',function()
    local s=resupply_during_action();s.avatar_action(2067,true,0.3);s.tick()
    assert(s.reload_calls==0)
    s.avatar_action(2067,false,0.5);s.tick();assert(s.reload_calls==1)
    s.avatar_action(s.reload_id,false,0.1);s.tick();assert(s.reload_calls==1)
end)
for _,cause in ipairs({'UI','map','focus','weapon','detonate','different action','same action restarted'}) do
    check('deferred resupply is cancelled by '..cause,function()
        local s=resupply_during_action()
        if cause=='UI' then s.ui(11)
        elseif cause=='map' then s.pose_flags{D.tactical_map}
        elseif cause=='focus' then s.focused=false
        elseif cause=='weapon' then s.u32(s.state+0x1c,0)
        elseif cause=='detonate' then s.values.detonate=true
        elseif cause=='different action' then s.avatar_action(333,true,0.2)
        else s.avatar_action(2067,true,0) end
        s.tick();s.values.detonate=false;s.ui();s.pose_flags{};s.focused=true;s.u32(s.state+0x1c,3)
        s.avatar_action(2067,false,0.6);s.complete();for _=1,5 do s.tick() end
        assert(s.reload_calls==0 and not s.module.disabled,s.module.status)
    end)
end
check('deferred resupply expires without forcing or replaying a long action',function()
    local s=resupply_during_action();s.tick(8.1);s.avatar_action(2067,false,0.6);s.tick()
    assert(s.reload_calls==0)
end)
check('deferred resupply does not restart a native reload that the player cancels',function()
    local s=resupply_during_action();s.avatar_action(s.reload_id,true,0);s.tick()
    s.avatar_action(s.reload_id,false,0.1);s.tick();assert(s.reload_calls==0)
end)
local function early_passenger_reload(config)
    local s=reload_setup(fresh());seat(s,config or 43,2);s.leaned(true,false);s.press('deploy')
    s.phase(30);s.avatar_action(s.reload_id,true,0);s.tick()
    assert(s.reload_calls==0 and s.reload_queries==0)
    return s
end
for _,config in ipairs({27,43,44}) do
    check('early native reload does not discard post-throw passenger opportunity '..config,function()
        local s=early_passenger_reload(config);s.complete();s.tick();assert(s.reload_calls==0)
        s.avatar_action(s.reload_id,false,0.02);s.leaned(false,true);s.tick()
        assert(s.reload_calls==0 and s.reload_queries==0)
        s.leaned(false,false);s.tick();assert(s.reload_calls==0)
        for _=1,3 do s.tick(0.1) end;assert(s.reload_calls==1)
        s.avatar_action(s.reload_id,false,0.02);for _=1,5 do s.tick() end
        assert(s.reload_calls==1,'interrupted mod reload was repeated')
    end)
end
check('successful early native passenger reload needs no additional request',function()
    local s=early_passenger_reload();s.u32(s.rounds_state+16,55);s.tick()
    s.complete();s.avatar_action(s.reload_id,false,0.5);s.tick();assert(s.reload_calls==0)
end)
check('manual reload already running before passenger throw is not retried',function()
    local s=reload_setup(fresh());seat(s,43,2);s.leaned(true,false)
    s.avatar_action(s.reload_id,true,0.1);s.press('deploy');s.complete()
    s.avatar_action(s.reload_id,false,0.2);s.tick();assert(s.reload_calls==0)
end)
check('another native reload after the early attempt cancels the retained opportunity',function()
    local s=early_passenger_reload();s.avatar_action(s.reload_id,false,0.01);s.tick()
    s.avatar_action(s.reload_id,true,0);s.tick();s.complete();s.avatar_action(s.reload_id,false,0.1);s.tick()
    assert(s.reload_calls==0)
end)
for _,cause in ipairs({'UI','map','weapon','avatar action','detonate'}) do
    check('retained passenger opportunity still yields to '..cause,function()
        local s=early_passenger_reload()
        if cause=='UI' then s.ui(11)
        elseif cause=='map' then s.pose_flags{D.tactical_map,D.seated}
        elseif cause=='weapon' then s.u32(s.state+0x1c,0)
        elseif cause=='avatar action' then s.avatar_action(333,true,0)
        else s.values.detonate=true end
        s.tick();s.values.detonate=false;s.ui();s.pose_flags{D.seated};s.u32(s.state+0x1c,3)
        s.complete();s.avatar_action(s.reload_id,false,0.1);s.leaned(false,false);s.tick()
        assert(s.reload_calls==0)
    end)
end
check('seat transition alone delays post-throw reload without needing an early native attempt',function()
    local s=reload_setup(fresh());seat(s,43,2);s.leaned(true,false);s.press('deploy')
    s.complete();s.leaned(false,true);s.tick();assert(s.reload_calls==0)
    s.leaned(false,false);s.tick();assert(s.reload_calls==0)
    for _=1,3 do s.tick(0.1) end;assert(s.reload_calls==1)
end)
check('reload decision logs carry the fresh active flag rather than cached action fields',function()
    local s=early_passenger_reload();local found=false
    for _,line in ipairs(s.lines) do
        if line:find('waiting_for_native_vehicle_reload',1,true) and line:find('"avatar_ability_active":true',1,true)
            and line:find('reload_sample_at_ms',1,true) then found=true end
    end
    assert(found)
end)

for _,config in ipairs({27,43,44,71}) do
    check('live idle gap before passenger retract never starts reload '..config,function()
        local s=early_passenger_reload(config)
        s.complete();s.avatar_action(s.reload_id,false,0);s.tick()
        assert(s.reload_calls==0 and s.reload_queries==0,'requested in lease release gap')
        s.tick(0.02);assert(s.reload_queries==0)
        s.leaned(false,true);s.tick(0.02);s.tick(0.6)
        assert(s.reload_queries==0,'requested during retract')
        s.leaned(false,false);s.tick();s.tick(0.2);assert(s.reload_queries==0)
        s.tick(0.06);assert(s.reload_calls==1)
        s.avatar_action(s.reload_id,false,0);for _=1,5 do s.tick(0.1) end
        assert(s.reload_calls==1,'cancelled reload repeated')
    end)
end
check('stable held lean-out can reload without requiring return inside',function()
    local s=early_passenger_reload();s.complete();s.avatar_action(s.reload_id,false,0);s.tick()
    s.tick(0.2);assert(s.reload_calls==0);s.tick(0.06)
    assert(s.reload_calls==1 and s.api.read(s.seat_row+0x31,1)=='\1')
end)
check('lean changes restart stability even if a transition was between samples',function()
    local s=early_passenger_reload();s.complete();s.avatar_action(s.reload_id,false,0);s.tick()
    s.tick(0.2);s.leaned(false,false);s.tick(0.1);assert(s.reload_queries==0)
    s.tick(0.2);assert(s.reload_queries==0);s.tick(0.06);assert(s.reload_calls==1)
end)
for _,offset in ipairs({0x18,0x20}) do
    check('pending seat animation prevents reload with busy already clear '..offset,function()
        local s=early_passenger_reload();s.complete();s.avatar_action(s.reload_id,false,0)
        s.leaned(true,false);s.u32(s.seat_row+offset,123)
        s.tick();s.tick(0.6);assert(s.reload_queries==0)
        s.u32(s.seat_row+offset,0xffffffff);s.tick();s.tick(0.2);s.tick(0.06)
        assert(s.reload_calls==1)
    end)
end
check('a long update alone cannot establish passenger seat stability',function()
    local s=early_passenger_reload();s.complete();s.avatar_action(s.reload_id,false,0);s.tick()
    s.tick(0.6);assert(s.reload_queries==0);s.tick();assert(s.reload_calls==1)
end)
for _,cause in ipairs({'UI','map','focus','weapon','avatar action','detonate','seat','MBM'}) do
    check('passenger settling remains interruptible by '..cause,function()
        local s=early_passenger_reload();s.complete();s.avatar_action(s.reload_id,false,0);s.tick()
        local mbm=_G.ModBindingsMenu
        if cause=='UI' then s.ui(11)
        elseif cause=='map' then s.pose_flags{D.tactical_map,D.seated}
        elseif cause=='focus' then s.focused=false
        elseif cause=='weapon' then s.u32(s.state+0x1c,0)
        elseif cause=='avatar action' then s.avatar_action(333,true,0)
        elseif cause=='detonate' then s.values.detonate=true
        elseif cause=='seat' then s.u32(s.seat_row+0x1c,3)
        else _G.ModBindingsMenu=nil end
        s.tick();s.values.detonate=false;s.ui();s.pose_flags{D.seated};s.focused=true
        s.u32(s.state+0x1c,3);s.u32(s.seat_row+0x1c,2);_G.ModBindingsMenu=mbm
        s.avatar_action(s.reload_id,false,0);s.complete();for _=1,10 do s.tick(0.1) end
        assert(s.reload_calls==0 and not s.module.disabled,s.module.status)
    end)
end
check('passenger resupply also waits for stable seat',function()
    local s=reload_setup(fresh());seat(s,43,2);s.leaned(false,false)
    s.u32(s.spare_state,0);s.u32(s.rounds_state+16,0);s.tick()
    s.u32(s.spare_state,4);s.tick();assert(s.reload_queries==0)
    s.tick(0.2);s.tick(0.06);assert(s.reload_calls==1)
end)
check('endlessly moving passenger seat expires without a later reload',function()
    local s=early_passenger_reload();s.complete();s.avatar_action(s.reload_id,false,0)
    s.leaned(false,true);s.tick();s.tick(8.1);s.leaned(false,false)
    for _=1,5 do s.tick(0.1) end;assert(s.reload_calls==0)
end)

local function aimed(setup)
    return fresh(false,{aim_profile=true,aim_setup=setup})
end
for trigger=0,8 do
    check('throw overlap respects native trigger '..trigger,function()
        local s=aimed(function(s)s.mapping('deploy',trigger)end)
        local release=trigger==1 or trigger==7
        assert(s.mask_mode()==(release and 0 or 1))
        s.button(1,true);assert((s.aim_ticks>0)==release)
        s.press('deploy');assert(#s.calls==4,'MBM throw lost')
    end)
    check('detonation overlap suppresses even release trigger '..trigger,function()
        local s=aimed(function(s)s.mapping('deploy',1);s.mapping('detonate',trigger)end)
        assert(s.mask_mode()==1);s.button(1,true);assert(s.aim_ticks==0)
        s.press('detonate');assert(s.calls[1][2]==520)
    end)
end
for _,device in ipairs({0,2,3}) do
    check('keyboard/controller identity and release trigger '..device,function()
        local s=aimed(function(s)
            s.mapping('aim',0,7,device);s.mapping('deploy',0,7,device)
        end)
        assert(s.mask_mode()==1)
        s.mapping('deploy',1,7,device);s.tick();assert(s.mask_mode()==0)
        s.mapping('detonate',1,7,device);s.tick();assert(s.mask_mode()==1)
    end)
end
check('different device, control and device slot preserve independent Aim',function()
    local s=aimed();assert(s.mask_mode()==1)
    s.mapping('deploy',0,1,2);s.tick();assert(s.mask_mode()==0)
    s.mapping('deploy',0,2);s.tick();assert(s.mask_mode()==0)
    s.mapping('aim',0,1,1,0);s.mapping('deploy',0,1,1,1);s.tick();assert(s.mask_mode()==0)
    s.mapping('deploy',0,1,1,255);s.tick();assert(s.mask_mode()==1)
end)
for _,cause in ipairs({'UI','map','focus','weapon','MBM','shutdown','log','original_error'}) do
    check('Aim inhibition restores on '..cause,function()
        local s=aimed();assert(s.mask_mode()==1 and s.inhibit_calls==1)
        if cause=='UI' then s.ui(11)
        elseif cause=='map' then s.pose_flags{D.tactical_map}
        elseif cause=='focus' then s.focused=false
        elseif cause=='weapon' then s.u32(s.state+0x1c,0)
        elseif cause=='MBM' then _G.ModBindingsMenu=nil
        elseif cause=='shutdown' then shutdown()
        elseif cause=='log' then s.log_failure=true;s.values.deploy=true
        else s.original_error=true end
        if cause~='shutdown' then pcall(s.tick) end
        assert(s.mask_mode()==0 and s.unblock_calls==1,'Aim lease was not restored')
    end)
end
check('externally replaced inhibition survives cleanup',function()
    local s=aimed();s.set_mask(2,3000);s.ui(11);s.tick()
    assert(s.mask_mode()==2 and s.unblock_calls==0)
end)
check('existing inhibition is not acquired or cleared',function()
    local s=aimed(function(s)s.set_mask(2)end)
    assert(s.mask_mode()==2 and s.inhibit_calls==0)
    shutdown();assert(s.mask_mode()==2 and s.unblock_calls==0)
end)
check('bad trigger snapshot degrades Aim feature without removing MBM actions',function()
    local s=aimed();s.mapping('deploy',9);s.tick()
    assert(s.mask_mode()==0 and not s.module.disabled)
    s.press('deploy');assert(#s.calls==4)
end)
check('Aim gate follows remap and does not reacquire until latched Aim releases',function()
    local s=aimed(function(s)s.mapping('deploy',1)end)
    s.button(1,true);s.mapping('deploy',0);s.tick();assert(s.mask_mode()==0)
    s.button(1,false);s.tick();assert(s.mask_mode()==1)
end)
check('inhibit post-call failure restores the pending lease',function()
    local s=aimed(function(s)
        local original=s.native.input_inhibit
        s.native.input_inhibit=function(...)original(...);error('fixture_after_native_failure')end
    end)
    assert(s.mask_mode()==0 and s.unblock_calls>0 and not s.module.disabled)
end)
check('full passenger throw and automatic reload survive Aim suppression',function()
    local s=reload_setup(aimed());seat(s,43,2);s.leaned(true,false);s.press('deploy')
    assert(s.mask_mode()==1 and s.api.read(s.seat_row+0x30,1)=='\1')
    s.complete();s.leaned(false,false);s.tick()
    for _=1,6 do s.tick(0.1) end
    assert(s.reload_calls==1 and s.mask_mode()==1)
end)
check('persisted MBM assignments reject duplicates collisions and invalid ranges',function()
    local profile=dofile('src/MBMProfile.lua')
    local a='etxp.c4_quick_actions.deploy\t10\t0\n'
    local b='etxp.c4_quick_actions.detonate\t10\t2\n'
    assert(profile.parse(a..b).deploy==10*65536)
    for _,v in ipairs({a,a..a..b,a..b:gsub('\t2','\t0'),a..b:gsub('\t10','\t8')}) do
        assert(not pcall(profile.parse,v))
    end
end)

for _,trigger in ipairs({0,1,2}) do
    check('left mouse MBM throw suppresses native Fire locomotion input '..trigger,function()
        local s=aimed(function(s)s.mapping('deploy',trigger,0);s.mapping('detonate',0,1)end)
        assert(s.fire_mask_mode()==1 and s.fire_inhibit_calls==1)
        s.button(0,true);s.press('deploy');s.button(0,false)
        assert(#s.calls==4 and s.sprint_breaks==0 and #s.vanilla==0)
        s.finish();s.button(0,true);s.press('deploy');s.button(0,false)
        assert(#s.calls==8 and s.sprint_breaks==0)
    end)
end
check('controller Fire suppression preserves MBM throw and release Aim exception',function()
    local s=aimed(function(s)s.mapping('deploy',1)end)
    s.trigger('right',0.8);s.press('deploy')
    assert(#s.calls==4 and s.sprint_breaks==0 and s.fire_mask_mode()==1)
    assert(s.mask_mode()==0);s.button(1,true);assert(s.aim_ticks>0)
end)
for _,cause in ipairs({'UI','map','focus','weapon','MBM','shutdown','error'}) do
    check('native Fire input restores on '..cause,function()
        local s=aimed();assert(s.fire_mask_mode()==1)
        if cause=='UI' then s.ui(11)
        elseif cause=='map' then s.pose_flags{D.tactical_map}
        elseif cause=='focus' then s.focused=false
        elseif cause=='weapon' then s.u32(s.state+0x1c,0)
        elseif cause=='MBM' then _G.ModBindingsMenu=nil
        elseif cause=='shutdown' then shutdown()
        else s.original_error=true end
        if cause~='shutdown' then pcall(s.tick) end
        assert(s.fire_mask_mode()==0 and s.fire_unblock_calls==1)
        if cause=='weapon' then s.button(0,true);assert(s.vanilla[1]=='OTHER_WEAPON') end
    end)
end
check('external Fire inhibition is not cleared or replaced',function()
    local s=aimed();s.u32(s.fire_row,2);s.ui(11);s.tick()
    assert(s.fire_mask_mode()==2 and s.fire_unblock_calls==0)
end)

local function passenger_reload_requested()
    local s=reload_setup(fresh());seat(s,43,2);s.leaned(true,false);s.press('deploy')
    s.complete();s.leaned(false,false)
    for _=1,6 do s.tick(0.1) end
    assert(s.reload_calls==1)
    return s
end
local function exit_and_settle(s)
    s.complete();s.avatar_action(s.reload_id,false,0);s.pose_flags{};s.tick()
    s.tick(0.1);assert(s.reload_calls<=1,'requested before stable dismount')
    for _=1,3 do s.tick(0.1) end
end
for _,cause in ipairs({'reload cancelled','UI','map','focus','exit ability'}) do
    check('interrupted passenger reload gets exactly one fresh request after dismount '..cause,function()
        local s=passenger_reload_requested();s.avatar_action(s.reload_id,false,0)
        if cause=='UI' then s.ui(11)
        elseif cause=='map' then s.pose_flags{D.seated,D.tactical_map}
        elseif cause=='focus' then s.focused=false
        elseif cause=='exit ability' then s.avatar_action(333,true,0) end
        s.tick();s.ui();s.pose_flags{D.seated};s.focused=true
        s.avatar_action(s.reload_id,false,0)
        for _=1,10 do s.tick(0.1) end;assert(s.reload_calls==1,'retried while seated')
        exit_and_settle(s);assert(s.reload_calls==2)
        s.avatar_action(s.reload_id,false,0)
        for _=1,15 do s.tick(0.1) end;assert(s.reload_calls==2,'repeated a cancelled dismount reload')
    end)
end
check('exit before passenger reload request preserves one new on-foot opportunity',function()
    local s=reload_setup(fresh());seat(s,27,2);s.leaned(true,false);s.press('deploy')
    s.ui(11);s.tick();s.complete();s.leaned(false,false);s.ui()
    exit_and_settle(s);assert(s.reload_calls==1)
end)
check('successful passenger reload does not trigger another reload on exit',function()
    local s=passenger_reload_requested();s.u32(s.rounds_state+16,54);s.tick()
    exit_and_settle(s);assert(s.reload_calls==1)
end)
check('dismount recovery cannot interrupt a continuing exit ability',function()
    local s=passenger_reload_requested();s.pose_flags{};s.avatar_action(333,true,0)
    for _=1,10 do s.tick(0.1) end;assert(s.reload_calls==1)
    s.avatar_action(333,false,0);s.tick();s.tick(0.1);assert(s.reload_calls==1)
    s.tick(0.2);assert(s.reload_calls==2)
end)
check('long tactical-map use in the vehicle is not mistaken for a dismount',function()
    local s=passenger_reload_requested();s.avatar_action(s.reload_id,false,0)
    s.pose_flags{D.seated,D.tactical_map};s.tick();s.tick(10)
    assert(s.reload_calls==1)
    s.pose_flags{D.seated};s.tick();exit_and_settle(s);assert(s.reload_calls==2)
end)
check('remaining in a different passenger seat does not retry an interrupted reload',function()
    local s=passenger_reload_requested();s.avatar_action(s.reload_id,false,0)
    seat(s,43,3);s.leaned(false,false)
    for _=1,12 do s.tick(0.1) end;assert(s.reload_calls==1)
    exit_and_settle(s);assert(s.reload_calls==2)
end)
check('native reload veto after exit is bounded and does not force reload',function()
    local s=passenger_reload_requested();s.reload_allowed=false
    exit_and_settle(s);assert(s.reload_calls==1)
    for _=1,20 do s.tick(0.1) end
    local queries=s.reload_queries;s.reload_allowed=true
    for _=1,10 do s.tick(0.1) end
    assert(s.reload_calls==1 and s.reload_queries==queries)
end)
check('late chamber consumption still records passenger recovery',function()
    local m=dofile('src/PassengerReloadRecovery.lua').new(function()return true end)
    local cap={reload_identity='avatar:weapon',vehicle={},active=true,ability_id=521,
        reload={ammo=3,chamber_empty=false,avatar_active=false}}
    m.arm(cap);assert(m.pending)
    assert(not m.observe({},cap,true,0,false) and m.pending)
    cap.reload.chamber_empty=true;m.observe({},cap,true,100,false)
    cap.active=false;cap.vehicle=nil
    assert(not m.observe({},cap,true,200,false))
    assert(not m.observe({},cap,true,300,false))
    assert(m.observe({},cap,true,500,false) and not m.pending)
end)
for _,cause in ipairs({'new avatar','new weapon','other weapon','no ammo','driver seat','detonate'}) do
    check('dismount recovery rejects '..cause,function()
        local s=passenger_reload_requested();s.avatar_action(s.reload_id,false,0)
        if cause=='new avatar' then s.u32(s.eaddr+12,s.unit+1)
        elseif cause=='new weapon' then s.u32(s.waddr+12,0xaaaa)
        elseif cause=='other weapon' then s.u32(s.state+0x1c,1);s.tick();s.u32(s.state+0x1c,3)
        elseif cause=='no ammo' then s.u32(s.spare_state,0)
        elseif cause=='driver seat' then seat(s,43,0,1);s.tick()
        end
        s.pose_flags{}
        if cause=='detonate' then s.values.detonate=true;s.tick();s.values.detonate=false end
        for _=1,10 do s.tick(0.1) end
        assert(s.reload_calls==1)
    end)
end

-- dev.17 live report: nine selector clicks started Deploy, consumed the
-- chamber, then were replaced by native action 2636 without a projectile.
-- All nine had avatar bit 86; ordinary UI stack/cursor remained empty.
for _,action in ipairs({'deploy','detonate'}) do
    check('weapon settings consumes no C4 from MBM '..action..' and preserves native selector',function()
        local s=fresh();local rounds=s.api.read(s.rounds_state,24);local runtime=s.api.read(s.rounds_runtime,20)
        s.put(s.avatar_flags,('\x0a\x04\0\0\0\0\x04\0\x01\x84\x40'..string.rep('\0',13)))
        s.u32(0x4b000000+16,0x100);s.press(action)
        assert(#s.calls==0 and s.api.read(s.rounds_state,24)==rounds and s.api.read(s.rounds_runtime,20)==runtime)
        assert(s.api.read(0x4b000000+16,4)=='\0\1\0\0')
        assert(table.concat(s.lines):find('weapon_settings_open',1,true) and not s.module.disabled,s.module.status)
        s.pose_flags{};for _=1,6 do s.tick()end;assert(#s.calls==0)
        s.press('deploy');assert(#s.calls==4 and s.calls[1][2]==521)
    end)
end
check('weapon settings opening within engine update discards same-frame activation',function()
    local s=fresh();local rounds=s.api.read(s.rounds_state,24)
    s.original_hook=function()s.pose_flags{D.weapon_menu};s.u32(0x4b000000+16,0x100);s.original_hook=nil end
    s.press('deploy');assert(#s.calls==0 and s.api.read(s.rounds_state,24)==rounds)
    s.pose_flags{};for _=1,6 do s.tick()end;assert(#s.calls==0)
    s.press('deploy');assert(#s.calls==4)
end)
check('holding MBM activation through weapon-menu close does not replay it',function()
    local s=fresh();s.pose_flags{D.weapon_menu};s.values.deploy=true;s.tick();s.pose_flags{}
    for _=1,8 do s.tick()end;assert(#s.calls==0)
    s.values.deploy=false;for _=1,6 do s.tick()end;assert(#s.calls==0)
    s.press('deploy');assert(#s.calls==4)
end)
check('release activation on the update closing weapon settings is discarded',function()
    local s=fresh();s.pose_flags{D.weapon_menu};s.tick()
    s.original_hook=function()s.pose_flags{};s.original_hook=nil end
    s.values.deploy=true;s.tick();s.values.deploy=false
    for _=1,8 do s.tick()end;assert(#s.calls==0)
    s.press('deploy');assert(#s.calls==4)
end)
check('opening weapon settings clears a previously queued throw',function()
    local s=fresh();s.press('deploy');s.press('deploy');assert(#s.calls==4)
    s.pose_flags{D.weapon_menu};s.tick();s.complete();s.pose_flags{}
    for _=1,8 do s.tick()end;assert(#s.calls==4)
end)
check('weapon settings blocks automatic reload during resupply',function()
    local s=reload_setup(fresh());s.u32(s.rounds_state+16,0);s.u32(s.spare_state,0);s.tick()
    s.pose_flags{D.weapon_menu};s.u32(s.spare_state,4)
    for _=1,8 do s.tick(0.1)end;assert(s.reload_calls==0 and #s.calls==0)
end)
check('native action capability independently vetoes weapon settings',function()
    local s=dofile('tests/action_fixture.lua')('rounds')
    s.put(s.avatar_flags+10,'\x40')
    local row,why,cap=s.snap();assert(cap and cap.interrupt and cap.blocked,tostring(why))
    assert(row.avatar_action_scope=='WEAPON_SETTINGS')
end)
