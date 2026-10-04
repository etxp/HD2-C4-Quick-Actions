-- Shared synthetic reload setup for regression tests and benchmarks.
local R=dofile('private/tests/mock_symbols.lua')
local D=dofile('private/tests/mock_fields.lua')
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
return reload_setup
