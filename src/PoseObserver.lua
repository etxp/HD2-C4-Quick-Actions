-- Read-only diagnostics. Capability checks are performed independently for
-- each action; diagnostic records never authorize a native transition.
local M={}
local bit=require('bit')
function M.new(api,game,base,emit)
    local sampled,last_emit,last_key=-math.huge,-math.huge,nil
    return function(now,flight_active)
        if not flight_active and now-sampled<50 then return end
        sampled=now
        -- Global managers and the local avatar do not exist during boot/load.
        -- Diagnostic reads must not disable the gameplay addon in that state.
        local ok,row,reason,pose=pcall(base.snapshot,api,game,function(e)
            local flags=e.read(e.avatar+0x53e880+e.avatar_index*0x1238,24,true)
            local input=e.avatar+0x150+e.avatar_index*0xa7aec+0x1b68
            local aim=e.read(input+8*32,8,true)
            local fire=e.read(input+9*32,8,true)
            local movement=e.read(input+14*32,8,true)
            local input15=e.read(input+15*32,8,true)
            local dive=e.read(input+17*32,8,true)
            local result={pose_flags=e.hex(flags),pose_avatar_id=e.id,pose_weapon_id=e.weapon_id,
                pose_input_8=e.hex(aim),pose_input_9=e.hex(fire),pose_input_14=e.hex(movement)}
            result.pose_input_15=e.hex(input15);result.pose_input_17=e.hex(dive)
            result.tactical_map_active=AvatarFlags.has(flags,D.tactical_map)
            result.weapon_menu_active=AvatarFlags.has(flags,D.weapon_menu)
            -- Keep raw fields as observations; seat semantics are not guessed.
            if AvatarFlags.has(flags,D.seated) then
                local seated,value=pcall(function()
                    local manager=e.global(R.global_vehicle)
                    local index=e.lookup(manager+0x20,e.id,65536)
                    if index then
                        assert(index<4096,'pose_relation_index_limit')
                        return e.hex(e.read(e.ptr(manager+0x48,true)+index*64,64,true))
                    end
                end)
                if seated then result.pose_seat_relation=value
                else result.pose_seat_unavailable=tostring(value) end
            end
            return result
        end)
        if not ok then reason=row;row=nil;pose=nil end
        pose=pose or {pose_unavailable=tostring(reason or (row and row.action_context_error) or 'no_local_c4')}
        local key=table.concat({tostring(pose.pose_flags),tostring(pose.pose_avatar_id),
            tostring(pose.pose_weapon_id),tostring(pose.pose_input_8),tostring(pose.pose_input_9),
            tostring(pose.pose_input_14),tostring(pose.pose_input_15),tostring(pose.pose_input_17),
            tostring(pose.pose_seat_relation),tostring(pose.pose_seat_unavailable),tostring(pose.pose_unavailable)},':')
        if key~=last_key or pose.pose_flags and now-last_emit>=1000 then
            pose.observation_only=true
            assert(emit('pose_context',pose),'pose_context_log_unavailable')
            last_key=key;last_emit=now
        end
    end
end
return M

