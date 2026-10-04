-- Fresh mapping bytes and native selected-device validation are mandatory even
-- when a positive bucket location was seen in a previous input snapshot.
local ffi=require('ffi')
local R=dofile('private/tests/mock_symbols.lua')
local D=dofile('private/tests/mock_fields.lua')
local base=dofile('private/tests/modules/context_reader.lua')(R,D)
local f=assert(io.open('src/AimInputState.lua','rb'));local source=f:read('*a');f:close()
local state=assert(loadstring('local R,D=...\nlocal GuardSpans=dofile("src/GuardSpans.lua")\n'..source))(R,D)
local scenario=dofile('tests/gamepad_entry_fixture.lua')
local crowded=dofile('tests/binding_probe_fixture.lua')
local function check(name,fn)fn();print('PASS '..name)end
local function fixture()
    _G.ModBindingsMenu={api=1,version=2,ready=function()return true end,
        register_binding=function()return true end,is_down=function()return false end}
    local s=scenario{entry='private/build/c4_quick_actions.off.lua',window=true,native_ui=true,
        aim_profile=true,before_load=function(s)crowded(s)end}
    for _=1,8 do s.tick()end
    assert(not s.module.disabled,s.module.status)
    local read=s.api.read;s.read_count=0
    s.api.read=function(...)s.read_count=s.read_count+1;return read(...)end
    s.hints={}
    local native={input_mapping=function(owner,action)
        return tonumber(ffi.cast('uintptr_t',s.native.input_mapping(owner,action,true)))
    end}
    function s.sample(hints)
        s.read_count=0
        local result=state.read(s.api,s.game,base,s.binding_probe.codes,native,nil,nil,hints)
        return result,s.read_count
    end
    function s.move(key,index)
        local p=s.binding_probe;local old=p.addresses[key]-8
        local count=base.u32(s.api.read(old+4,4),0)
        local parts={s.api.read(old,8)}
        for i=0,count-1 do parts[#parts+1]=s.api.read(old+8+i*20,20)end
        local at=p.buckets+index*328
        s.put(at,table.concat(parts));s.u32(old,0xffffffff);p.addresses[key]=at+8
    end
    return s
end
check('crowded mapping uses bounded positive hints without retaining mapping bytes',function()
    local s=fixture();local _,first=s.sample(s.hints);local p,reused=s.sample(s.hints)
    local q,uncached=s.sample()
    assert(first==uncached and reused<uncached/10)
    assert(state.policy(base,p)==state.policy(base,q))
    local n=0;for _ in pairs(s.hints.slots)do n=n+1 end;assert(n==3)
    assert(s.hints.mappings==nil)
    print(string.format('MEASURE crowded binding snapshot reads: uncached=%d hinted=%d',uncached,reused))
end)
check('trigger and device remaps in the same bucket are read immediately',function()
    local s=fixture();s.sample(s.hints)
    s.mapping('deploy',1);local p=s.sample(s.hints)
    local suppress,why=state.policy(base,p)
    assert(not suppress and why=='release_throw_aim_preserved')
    s.mapping('detonate',0,1);p=s.sample(s.hints)
    suppress,why=state.policy(base,p);assert(suppress and why=='detonate_overlap')
    s.mapping('detonate',0,1,2);p=s.sample(s.hints)
    suppress,why=state.policy(base,p);assert(not suppress and why=='release_throw_aim_preserved')
end)
for _,key in ipairs({'aim','deploy','detonate'})do
    check('moving '..key..' bucket falls back within the same snapshot',function()
        local s=fixture();s.sample(s.hints);s.move(key,230)
        local p=s.sample(s.hints);local q=s.sample()
        assert(s.hints.slots[key]==s.binding_probe.addresses[key]-8)
        assert(state.policy(base,p)==state.policy(base,q))
        local _,reused=s.sample(s.hints);assert(reused<100)
    end)
end
check('removed mapping is not a negative cache and is found on its next insertion',function()
    local s=fixture();s.sample(s.hints)
    local p=s.binding_probe;local old=p.addresses.deploy-8
    local code=s.api.read(old,4);s.u32(old,0xffffffff)
    assert(not pcall(s.sample,s.hints));assert(s.hints.slots.deploy==nil)
    s.put(old,code);local result=s.sample(s.hints)
    assert(result.deploy and s.hints.slots.deploy==old)
end)
check('fresh native hash header invalidates all remembered bucket locations',function()
    local s=fixture();s.sample(s.hints);local old=s.hints.slots
    s.u32(s.binding_probe.header+16,3)
    local p=s.sample(s.hints);assert(s.hints.slots~=old)
    assert(state.policy(base,p))
end)
check('replacing the native input owner discards the old three-role hint table',function()
    local s=fixture();s.sample(s.hints)
    local old=s.hints.slots;local owner=s.binding_probe.owner;local replacement=0x73000000
    for _,part in ipairs({{D.input_inhibit_count,4},{D.input_inhibit_map,20},
        {D.input_inhibit_rows,48},{808+32*(2*97+8),1},{D.input_bindings,20}})do
        s.put(replacement+part[1],assert(s.api.read(owner+part[1],part[2])))
    end
    s.ptr(s.game+R.global_input_owner,replacement)
    s.native.input_mapping=function(manager)
        assert(manager==replacement);return ffi.cast('void *',s.binding_probe.addresses.aim)
    end
    local p=s.sample(s.hints)
    assert(p.owner==replacement and s.hints.slots~=old)
end)
check('changing an MBM assignment code immediately locates the new binding',function()
    local s=fixture();s.sample(s.hints);local old=s.hints.slots
    local p=s.binding_probe;p.codes.deploy=11*65536+19
    s.u32(p.addresses.deploy-8,p.codes.deploy)
    local result=s.sample(s.hints)
    assert(result.deploy and s.hints.slots~=old and state.policy(base,result))
end)
check('replacing the native binding table invalidates addresses and returns new mappings',function()
    local s=fixture();s.sample(s.hints);local old=s.hints.slots
    local p=s.binding_probe;local replacement=0x74000000
    for index=0,255 do
        local at=p.buckets+index*328;local count=base.u32(s.api.read(at+4,4),0)
        s.put(replacement+index*328,assert(s.api.read(at,8)))
        for j=0,count-1 do
            s.put(replacement+index*328+8+j*20,assert(s.api.read(at+8+j*20,20)))
        end
    end
    for key,at in pairs(p.addresses)do p.addresses[key]=replacement+at-p.buckets end
    p.buckets=replacement;s.ptr(p.header,replacement)
    local result=s.sample(s.hints)
    assert(s.hints.slots~=old and result.aim and state.policy(base,result))
    assert(s.hints.slots.aim==p.addresses.aim-8)
end)
check('adding another mapping to a hinted bucket is observed immediately',function()
    local s=fixture();s.mapping('deploy',1);s.sample(s.hints)
    local p=s.binding_probe;local at=p.addresses.detonate
    s.u32(at-4,2)
    s.put(at+20,assert(s.api.read(p.addresses.aim,20)))
    local result=s.sample(s.hints)
    local suppress,why=state.policy(base,result)
    assert(#result.detonate==2 and suppress and why=='detonate_overlap')
end)
check('mapping mutations during native selection reject the hinted snapshot',function()
    local s=fixture();s.sample(s.hints)
    local original=s.native.input_mapping
    s.native.input_mapping=function(...)
        local at=s.binding_probe.addresses.deploy
        s.u32(at+8,1);return original(...)
    end
    local ok,why=pcall(s.sample,s.hints)
    assert(not ok and tostring(why):find('aim_snapshot_changed',1,true),tostring(why))
end)
check('native selected pointer outside verified aim bucket is still rejected',function()
    local s=fixture();s.sample(s.hints)
    s.native.input_mapping=function()return ffi.cast('void *',s.binding_probe.addresses.aim+20)end
    local ok,why=pcall(s.sample,s.hints)
    assert(not ok and tostring(why):find('aim_selected_mapping_outside_bucket',1,true),tostring(why))
end)
-- Retained observation: reused only while every guarded byte compares equal.
local function retained(s)
    s.sample(s.hints);s.sample(s.hints)
    assert(s.hints.cache,'hint-located observation was not retained')
    return s.sample(s.hints)
end
check('a retained observation is revalidated with far fewer reads and no retained decision',function()
    local s=fixture();local _,probing=s.sample(s.hints);local hinted,located=s.sample(s.hints)
    local reused,reads=s.sample(s.hints)
    assert(reads<located and located<probing)
    for _,key in ipairs({'owner','count','held'})do assert(reused[key]==hinted[key],key)end
    assert(reused.aim==hinted.aim and reused.deploy==hinted.deploy and reused.detonate==hinted.detonate)
    assert(state.policy(base,reused)==state.policy(base,hinted))
    print(string.format('MEASURE input observation reads: probing=%d hint-located=%d retained=%d',probing,located,reads))
end)
check('the engine is asked for its selected mapping on every retained use',function()
    local s=fixture();retained(s)
    local original=s.native.input_mapping;local asked=0
    s.native.input_mapping=function(...)asked=asked+1;return original(...)end
    for _=1,5 do s.sample(s.hints)end;assert(asked==5)
    -- A device switch with no memory change is honoured immediately.
    s.native.input_mapping=function()return ffi.cast('void *',0)end
    local p=s.sample(s.hints);assert(p.aim==nil and s.hints.cache)
    local suppress,why=state.policy(base,p);assert(not suppress and why=='no_active_aim_mapping')
end)
check('retained observation: every remap, held state and inhibition change is seen at once',function()
    local s=fixture();retained(s)
    s.mapping('detonate',0,1);local p=s.sample(s.hints)
    local suppress,why=state.policy(base,p);assert(suppress and why=='detonate_overlap')
    retained(s);s.put(s.aim_state,'\1');assert(s.sample(s.hints).held==true)
    retained(s);s.put(s.aim_state,'\0');assert(s.sample(s.hints).held==false)
    retained(s);s.set_mask(1);p=s.sample(s.hints);assert(p.mask and p.mask.mode==1)
    retained(s);s.set_mask(0);p=s.sample(s.hints);assert(p.mask and p.mask.mode==0)
end)
check('retained observation: changed MBM codes are never served from the old record',function()
    local s=fixture();retained(s)
    local p=s.binding_probe;p.codes.deploy=11*65536+19
    s.u32(p.addresses.deploy-8,p.codes.deploy)
    local result=s.sample(s.hints);assert(result.deploy and state.policy(base,result))
end)
check('retained observation: a mapping changed during native selection is rejected',function()
    local s=fixture();retained(s)
    local original=s.native.input_mapping
    s.native.input_mapping=function(...)
        s.u32(s.binding_probe.addresses.deploy+8,1);return original(...)
    end
    local ok,why=pcall(s.sample,s.hints)
    assert(not ok and tostring(why):find('aim_snapshot_changed',1,true),tostring(why))
end)
check('retained observation: a selected pointer outside the verified bucket is rejected',function()
    local s=fixture();retained(s)
    s.native.input_mapping=function()return ffi.cast('void *',s.binding_probe.addresses.aim+20)end
    local ok,why=pcall(s.sample,s.hints)
    assert(not ok and tostring(why):find('aim_selected_mapping_outside_bucket',1,true),tostring(why))
end)
check('retained observation: a replaced input owner is followed before the native query',function()
    local s=fixture();retained(s)
    local owner=s.binding_probe.owner;local replacement=0x73000000
    for _,part in ipairs({{D.input_inhibit_count,4},{D.input_inhibit_map,20},
        {D.input_inhibit_rows,48},{808+32*(2*97+8),1},{D.input_bindings,20}})do
        s.put(replacement+part[1],assert(s.api.read(owner+part[1],part[2])))
    end
    s.ptr(s.game+R.global_input_owner,replacement)
    s.native.input_mapping=function(manager)
        assert(manager==replacement,'native query used the stale owner')
        return ffi.cast('void *',s.binding_probe.addresses.aim)
    end
    assert(s.sample(s.hints).owner==replacement)
end)
check('Aim and Fire gates are reread together once per phase and each still sees its own change',function()
    -- Page-granular memory, as in a real process: one page is one readable span.
    _G.C4FixturePages=true;local s=fixture();_G.C4FixturePages=nil
    dofile('src/ReadMemo.lua')(s.api)
    local native={input_mapping=function(owner,action)
        return tonumber(ffi.cast('uintptr_t',s.native.input_mapping(owner,action,true)))
    end}
    local group=state.group()
    local aim_hints,fire_hints={group=group},{group=group}
    local fire_spec={action=D.input_fire_action,code=D.input_fire_code,index=9,tag='fire_input',fire=true}
    local function aim()return state.read(s.api,s.game,base,s.binding_probe.codes,native,nil,nil,aim_hints)end
    local function fire()return state.read(s.api,s.game,base,true,native,fire_spec,nil,fire_hints)end
    s.api.memo_begin()
    for _=1,3 do aim();fire() end
    assert(aim_hints.cache and fire_hints.cache)
    -- A new phase: one shared sweep, then the Fire gate needs no read at all.
    s.api.memo_end();s.api.memo_begin()
    s.read_count=0;aim();local together=s.read_count
    s.read_count=0;local p=fire();assert(s.read_count==0 and p.held==false,'Fire gate read its pages again')
    -- The engine query never follows spans left by an earlier call: a second
    -- Aim read in the same phase rereads memory first and sees a remap at once.
    s.mapping('detonate',0,1)
    s.read_count=0;local q=aim();assert(s.read_count>0,'native query followed stale phase spans')
    local suppress,why=state.policy(base,q);assert(suppress and why=='detonate_overlap')
    s.mapping('detonate',0,0);aim();aim()
    -- Without a phase there is nothing to share and each gate rereads alone.
    s.api.memo_end();s.read_count=0;fire();assert(s.read_count>0)
    s.api.memo_begin()
    -- A change to only the Fire record is seen by the Fire gate in that phase.
    s.put(s.fire_input_state,'\1');aim();assert(fire().held==true)
    s.api.memo_end();s.api.memo_begin()
    s.put(s.fire_input_state,'\0');s.put(s.aim_state,'\1')
    assert(aim().held==true and fire().held==false)
    -- A native mutation discards the phase spans: the next use rereads.
    s.put(s.aim_state,'\0');aim();fire();s.api.memo_reset()
    s.put(s.fire_input_state,'\1');assert(fire().held==true,'stale phase span survived a mutation')
    s.api.memo_end()
    print(string.format('MEASURE shared input sweep: aim+fire reads per phase=%d',together))
end)
