-- Read-only C4 reload context. Configuration and owner are resolved from the
-- same native paths used by the manual reload command; no fixed reload ID.
local M={}
function M.apply(e,row,cap,base)
    if row.ammo_path~='weapon_rounds' then row.reload_context='unsupported_ammo_path';return end
    local read,ptr,u32,lookup=e.read,e.ptr,e.u32,e.lookup
    -- Historical name retained: this is the reload component that also owns
    -- the reload/exclusion flags already read by ActionReader.
    local manager=e.global(R.global_exclusions)
    local index=lookup(manager+0x20,e.weapon_id,65536)
    if not index then row.reload_context='component_absent';return end
    assert(index<4096,'reload_component_index')
    assert(read(ptr(ptr(manager+0x38,true)+index*8,true),24,true)==e.weapon,'reload_registry_mismatch')
    local owner=e.global(R.global_weapon_owner)
    local oi=assert(lookup(owner+0x18,e.weapon_id,65536),'reload_owner_missing')
    assert(oi<4096,'reload_owner_index')
    assert(u32(read(ptr(owner+0x38,true)+oi*4,4,true),0)==e.id,'reload_not_local_avatar')
    local ai=assert(lookup(cap.ability_manager+0x18,e.id,65536),'reload_avatar_ability_missing')
    assert(ai<4096,'reload_avatar_ability_index')
    assert(read(ptr(ptr(cap.ability_manager+0x30,true)+ai*8,true),24,true)==e.entity,'reload_avatar_registry')
    local avatar=read(ptr(cap.ability_manager+0x38,true)+ai*0xe0,32,true)
    assert(avatar:byte(17)<=1,'reload_avatar_active_flag')
    local config
    local override=lookup(manager+0x60,e.weapon_id,65536)
    if override then
        assert(override<4096,'reload_override_index')
        config=read(ptr(manager+0xa0,true)+override*D.reload_stride,D.reload_stride,true)
    else
        local templates=ptr(e.owner+D.reload_templates,true);local start=0
        for b=8,1,-1 do start=(start*256+e.weapon:byte(b))%D.reload_capacity end
        for probe=0,D.reload_capacity-1 do
            local entry=read(templates+((start+probe)%D.reload_capacity)*16,16,true)
            if e.resource(entry)=='0000000000000000' then break end
            if e.resource(entry)==row.current_weapon_resource then
                local ti=u32(entry,8);assert(ti<D.reload_capacity,'reload_template_index')
                config=read(templates+D.reload_capacity*16+ti*D.reload_stride,D.reload_stride,true);break
            end
        end
    end
    assert(config,'reload_config_missing')
    -- Follow native eligibility's branch order: C4 draws from the equipped
    -- backpack, whereas config +0x3c selects a different supply-unit path.
    -- A generic unit relation can point to the avatar and is NOT its backpack.
    local reserve=assert(row.rounds_reserve_count,'reload_reserve_missing')
    assert(reserve<0x80000000,'reload_invalid_ammo_count')
    local function resource_count(id)
        local ei=assert(lookup(e.owner+D.entity_id_map,id,1048576),'reload_supply_identity_missing')
        assert(ei<262144,'reload_supply_entity_index')
        local entity=read(e.owner+D.entity_array+ei*24,24,true)
        assert(u32(entity,8)==id,'reload_supply_identity_mismatch')
        local counters=e.global(R.global_resource_counter)
        local ci=lookup(counters+0x20,id,65536)
        row.reload_supply_entity_id=id
        if not ci then row.reload_supply_source='resource_counter_absent';return 0 end
        assert(ci<4096,'reload_supply_counter_index')
        assert(read(ptr(ptr(counters+0x38,true)+ci*8,true),24,true)==entity,
            'reload_supply_registry_mismatch')
        local count=u32(read(ptr(counters+0x50,true)+ci*8,4,true),0)
        assert(count<0x80000000,'reload_invalid_supply_count')
        return count
    end
    local supplied=0
    local backpacks=e.global(R.global_backpack_reload)
    local bi=lookup(backpacks+0x18,e.weapon_id,65536)
    if bi then
        assert(bi<4096,'reload_backpack_component_index')
        row.reload_supply_source='equipped_backpack'
        local id=assert(row.inventory_words['12'],'reload_backpack_slot_missing')
        row.reload_backpack_entity_id=id
        if id~=0 and id~=0xffffffff and id~=0x7fff then
            supplied=resource_count(id)
        else row.reload_supply_source='no_equipped_backpack' end
    elseif config:byte(0x3d)~=0 then
        row.reload_supply_source='no_supply_relation'
        local supplies=e.global(R.global_reload_supply)
        local si=lookup(supplies+0x18,e.weapon_id,65536)
        if si then
            assert(si<4096,'reload_supply_index')
            local unit=u32(read(ptr(supplies+0x38,true)+si*D.reload_supply_stride,4,true),0)
            row.reload_supply_unit=unit
            if unit~=0 then
                local id=lookup(e.owner+D.unit_entity_id_map,unit,1048576)
                assert(id and id~=0 and id~=0x7fff,'reload_supply_entity_missing')
                row.reload_supply_source='weapon_linked_resource_counter'
                supplied=resource_count(id)
            else row.reload_supply_source='no_supply_unit' end
        end
    else row.reload_supply_source='local_reserve_only' end
    row.reload_supply_count=supplied
    row.reload_spare_ammo=reserve+supplied
    assert(row.reload_spare_ammo<0x80000000,'reload_invalid_total_ammo')
    local ability=u32(config,4)
    -- The native eligibility routine has a special mutating branch for 0xb17;
    -- it must never be used as a read-only query for that configuration.
    assert(ability>0 and ability<16384 and ability~=0xb17,'unsupported_reload_ability')
    row.reload_context='verified';row.reload_config_hex=e.hex(config)
    row.reload_ability_id=ability;row.avatar_ability_id=u32(avatar,0)
    row.avatar_ability_active=avatar:byte(17)==1
    local clock_ok,clock=pcall(base.f32,avatar,8)
    if clock_ok and clock>=0 and clock<3600 then row.avatar_ability_time=clock end
    cap.reload={manager=manager,ability=ability,avatar_active=row.avatar_ability_active,
        avatar_ability=row.avatar_ability_id,avatar_time=row.avatar_ability_time,ammo=row.reload_spare_ammo,
        chamber_empty=row.rounds_chamber_token==0}
end
return M
