-- Offline synthetic CPU/allocation measurements, never a game FPS prediction.
-- The fixture records mock native calls; contact execution is covered separately
-- by test_contact_actions.lua, not this frame-cost benchmark.
local scenario=dofile('tests/gamepad_entry_fixture.lua')
local R=dofile('private/tests/mock_symbols.lua')
local D=dofile('private/tests/mock_fields.lua')
local entry=arg[1] or 'private/build/c4_quick_actions.summary.lua'
local frames=tonumber(arg[2]) or 300
local soak=arg[3]=='soak'
local function passenger(s)
    local manager=s.allocate();s.ptr(s.game+R.global_vehicle,manager)
    s.map(manager+0x20,s.allocate(),{{s.aid,1}})
    local registry=s.allocate();s.ptr(manager+0x38,registry);s.ptr(registry+8,s.eaddr)
    local states=s.allocate();s.ptr(manager+0x48,states);local row=states+64;s.zero(row,64)
    s.u32(row+0x18,0xffffffff);s.u32(row+0x20,0xffffffff)
    local id=s.otherid+100;s.u32(row,id);s.u32(row+4,43);s.u32(row+8,3);s.u32(row+0x1c,2)
    s.map(s.owner+D.entity_id_map,0x42000000,{{s.wid,5},{s.otherid,6},{s.aid,3},{id,7}})
    local entity=s.owner+D.entity_array+7*24;s.zero(entity,24);s.put(entity,'VEHICLE!');s.u32(entity+8,id)
    s.zero(s.avatar_flags,24);s.u32(s.avatar_flags,2)
    s.u32(s.avatar_flags+math.floor(D.seated/32)*4,2^(D.seated%32))
end
for _,case in ipairs({'c4_idle','crowded_bindings','other_weapon','menu','release_aim','tank_passenger'})do
 _G.ModBindingsMenu={api=1,version=2,ready=function()return true end,register_binding=function()return true end,is_down=function()return false end}
 local s=scenario{entry=entry,window=true,native_ui=true,aim_profile=true}
 if soak then dofile('tests/reload_fixture.lua')(s) end
 for _=1,8 do s.tick()end
 if case=='crowded_bindings' then dofile('tests/binding_probe_fixture.lua')(s)
 elseif case=='other_weapon' then s.u32(s.state+0x1c,1)
 elseif case=='menu'then s.ui(11)
 elseif case=='release_aim'then s.mapping('deploy',1);s.button(1,true)
 elseif case=='tank_passenger'then passenger(s)end
 for _=1,8 do s.tick()end
 local old=s.api.read;local calls,bytes=0,0
 s.api.read=function(at,n)calls=calls+1;bytes=bytes+n;return old(at,n)end
 collectgarbage('collect');local kb=collectgarbage('count')
 if not soak then collectgarbage('stop')end
 local started=os.clock()
 for i=1,frames do
    s.tick()
    if soak and i%500==0 then
        -- Remove the fixture's deliberately retained logs/call history only.
        -- Runtime ownership and recovery state is never cleared here.
        s.lines={};s.calls={};s.writes={};s.passenger_writes={}
        collectgarbage('collect')
        print(string.format('HEAP %s frame=%d retained_KiB=%.2f',case,i,collectgarbage('count')))
    end
 end
 local elapsed=os.clock()-started;local allocated=collectgarbage('count')-kb;collectgarbage('restart')
 assert(not s.module.disabled,s.module.status)
 print(string.format('RESULT {"scenario":"%s","frames":%d,"read_calls_per_frame":%.3f,"read_bytes_per_frame":%.3f,"mock_ms_per_frame":%.6f,"allocation_KiB_per_frame":%.3f,"soak":%s}',case,frames,calls/frames,bytes/frames,elapsed*1000/frames,allocated/frames,tostring(soak)))
 assert(_G.shutdown()=='shutdown-original')
end
