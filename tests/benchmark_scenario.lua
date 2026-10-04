-- Shared synthetic scenario setup. No actual game process or native calls.
local R=dofile('private/tests/mock_symbols.lua')
local D=dofile('private/tests/mock_fields.lua')
return function(s,case)
    if case=='c4_idle' or not case then return
    elseif case=='c4_volatile' then
        -- Worst case for retained snapshots: guarded bytes that decide nothing
        -- change on every update (an idle ability clock and a spare avatar flag).
        local used={[D.alive]=true,[D.seated]=true,[D.diving]=true,[D.prone]=true,[D.airborne]=true,
            [D.tactical_map]=true,[D.weapon_menu]=true}
        for _,flag in ipairs(D.blocked) do used[flag]=true end
        local spare=191;while used[spare] do spare=spare-1 end
        local at=s.avatar_flags+math.floor(spare/8);local n=0
        local clear=s.api.read(at,1):byte()%2^(spare%8)
        return function()
            n=n+1;s.phase(n%50)
            s.put(at,string.char(clear+(n%2)*2^(spare%8)))
        end
    elseif case=='no_mission' then s.u32(s.mode+8,0) -- aboard the ship
    elseif case=='crowded_bindings' then dofile('tests/binding_probe_fixture.lua')(s)
    elseif case=='other_weapon' then s.u32(s.state+0x1c,1)
    elseif case=='menu' then s.ui(11)
    elseif case=='release_aim' then s.mapping('deploy',1);s.button(1,true)
    elseif case=='tank_passenger' then
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
    else error('unknown benchmark scenario: '..tostring(case))end
end
