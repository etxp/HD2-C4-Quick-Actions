-- Pause menus use the UI stack. Tactical map and weapon settings use
-- independent avatar flags, even with no cursor/stack entry. Read only.
local M={}
local bit=require('bit')
function M.new(api,game,base,observe)
    local function read(at,n)
        assert(type(at)=='number' and at>=65536 and at+n<0x800000000000,'ui_bad_address')
        local bytes=assert(api.read(at,n),'ui_read_unavailable')
        assert(#bytes==n,'ui_short_read')
        return bytes
    end
    local function avatar_ui()
        if observe then
            local ok,row=pcall(observe)
            return ok and row or {}
        end
        local ok,row,reason,extra=pcall(base.avatar_snapshot,api,game,function(e)
            local flags=e.read(e.avatar+0x53e880+e.avatar_index*0x1238,24,true)
            return {tactical_map_active=AvatarFlags.has(flags,D.tactical_map),
                weapon_menu_active=AvatarFlags.has(flags,D.weapon_menu)}
        end)
        return ok and extra or {}
    end
    -- A confirmed pointer/stack image is kept. While a new read of both is
    -- byte-identical to it (and the pointer is unchanged around the stack
    -- read), the parsed state is the same and needs no second stack read.
    local known
    -- quiet: return only the three decisions instead of a descriptive row.
    return function(quiet)
        local pointer=read(game+R.global_ui,8)
        local manager=assert(api.pointer(pointer),'ui_manager_unavailable')
        local bytes=read(manager+D.ui_shift+0x84,0x90)
        local state=known
        if state and state.pointer==pointer and state.bytes==bytes then
            assert(read(game+R.global_ui,8)==pointer,'ui_state_changed_during_read')
        else
            known=nil
            local u32=base.u32
            local primary,modal=u32(bytes,0),u32(bytes,4)
            local count,secondary,pending=u32(bytes,0x1c),u32(bytes,0x84),u32(bytes,0x8c)
            assert(count<=5 and secondary<=25,'ui_stack_capacity_changed')
            local stack={}
            local active=primary~=0 or modal~=0 or secondary~=0 or pending~=0
            for i=1,count do
                stack[i]=u32(bytes,8+(i-1)*4)
                active=active or stack[i]~=0
            end
            assert(read(game+R.global_ui,8)==pointer and read(manager+D.ui_shift+0x84,0x90)==bytes,
                'ui_state_changed_during_read')
            state={pointer=pointer,bytes=bytes,active=active,primary=primary,modal=modal,
                stack=table.concat(stack,','),count=count,secondary=secondary,pending=pending}
            known=state
        end
        -- A verified active UI stack already vetoes every action. Read avatar
        -- flags as soon as it closes, before rearming, not behind that veto.
        local avatar=not state.active and avatar_ui() or {}
        if quiet then
            return state.active,avatar.tactical_map_active==true,avatar.weapon_menu_active==true
        end
        return {native_ui_available=true,native_ui_active=state.active,
            native_ui_primary=state.primary,native_ui_modal=state.modal,native_ui_stack=state.stack,
            native_ui_stack_count=state.count,
            native_ui_secondary_count=state.secondary,native_ui_pending=state.pending,
            tactical_map_active=avatar.tactical_map_active==true,
            weapon_menu_active=avatar.weapon_menu_active==true}
    end
end
return M
