-- Prone, dive and airborne transition flags are independent, not a combined pose.
-- Passenger admission follows the native role, never a vehicle/seat allowlist.
-- Unclassified action vetoes remain fail-closed until their semantics are verified.
local bit=require('bit')
local M={}
function M.apply(e,row,cap,av)
    local u32=e.u32
    local seated=AvatarFlags.has(av,D.seated)
    cap.seated=seated -- retained even when tactical-map UI vetoes seat admission
    local diving=not seated and AvatarFlags.has(av,D.diving)
    local prone=not seated and AvatarFlags.has(av,D.prone)
    row.avatar_action_scope=diving and 'NATIVE_DIVE' or prone and 'PRONE' or seated and 'UNSUPPORTED_VEHICLE' or 'GROUND'
    -- after the map key is released, so mouse pan/mark must not throw C4.
    if AvatarFlags.has(av,D.tactical_map) then
        row.avatar_action_scope='TACTICAL_MAP'
        return false
    end
    if AvatarFlags.has(av,D.weapon_menu) then
        row.avatar_action_scope='WEAPON_SETTINGS'
        return false
    end
    local vehicle
    if seated then
        local manager=e.global(R.global_vehicle)
        local index=assert(e.lookup(manager+0x20,e.id,65536),'vehicle_relation_missing')
        assert(index<4096,'vehicle_relation_index_limit')
        local address=e.ptr(manager+0x48,true)+index*64
        local relation=e.read(address,64,true)
        local id,config,role,seat=u32(relation,0),u32(relation,4),u32(relation,8),u32(relation,0x1c)
        row.vehicle_relation_hex=e.hex(relation)
        row.vehicle_id=id;row.vehicle_config=config;row.vehicle_role=role;row.vehicle_seat=seat
        row.vehicle_transition=relation:byte(0x31)~=0
        row.vehicle_leaned=relation:byte(0x32)~=0
        -- Role 3 is the native passenger role. Model numbers and seat indices
        -- are runtime data; they do not select a hardcoded vehicle profile.
        if role==3 and seat~=0xffffffff and relation:byte(0x31)<=1 and relation:byte(0x32)<=1 then
            local vi=assert(e.lookup(e.owner+D.entity_id_map,id,1048576),'vehicle_entity_missing')
            assert(vi<262144,'vehicle_entity_index_limit')
            local entity=e.read(e.owner+D.entity_array+vi*24,24,true)
            assert(u32(entity,8)==id,'vehicle_entity_identity_mismatch')
            assert(e.read(e.ptr(e.ptr(manager+0x38,true)+index*8,true),24,true)==e.entity,
                'vehicle_avatar_registry_mismatch')
            vehicle={manager=manager,avatar_id=e.id,vehicle_id=id,config=config,seat=seat,
                address=address,bytes=relation,owner=e.owner,avatar_entity=e.entity,vehicle_entity=entity,
                transition=row.vehicle_transition,leaned=row.vehicle_leaned,
                idle=not row.vehicle_transition and u32(relation,0x18)==0xffffffff
                    and u32(relation,0x20)==0xffffffff,
                identity=table.concat({tostring(manager),tostring(address),e.hex(entity),tostring(seat)},':')}
            cap.identity=cap.identity..':VEHICLE:'..tostring(config)..':'..vehicle.identity
            cap.vehicle=vehicle
            cap.vehicle_ready=vehicle.leaned and not vehicle.transition
            row.avatar_action_scope='VEHICLE_PASSENGER'
        end
    end
    if (seated and not vehicle) or not AvatarFlags.has(av,D.alive) then return false end
    for _,flag in ipairs(D.blocked) do
        local permitted=(not seated and (flag==D.diving or flag==D.prone or flag==D.airborne))
            or (vehicle~=nil and flag==D.seated)
        if not permitted and AvatarFlags.has(av,flag) then
            row.avatar_blocking_flag=flag
            return false
        end
    end
    return true
end
return M
