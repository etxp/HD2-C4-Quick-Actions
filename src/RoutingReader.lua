-- One guarded read-only observation for UI and native input ownership.
-- No templates, ammo, reload or action capability: those remain in ActionReader.
local M={}
function M.snapshot(api,game,base)
    return base.snapshot(api,game,function(e,row)
        local read,ptr,u32=e.read,e.ptr,e.u32
        local identity=table.concat({e.hex(e.entity),e.hex(e.weapon),tostring(e.owner)},':')
        local cap={input_only=true,routing_only=true,identity=identity,same=e.checked}
        local wm=e.global(R.global_weapon)
        local wi=assert(e.lookup(wm+0x28,e.weapon_id,65536),'routing_weapon_missing')
        assert(wi<4096,'routing_weapon_index')
        assert(read(ptr(ptr(wm+0x40,true)+wi*8,true),24,true)==e.weapon,'routing_weapon_identity')
        local address=ptr(wm+0x50,true)+wi*40
        local flags=u32(read(address,4,true),0)
        local driver=e.global(R.global_fire_latch)
        local di=assert(e.lookup(driver+0x20,e.weapon_id,65536),'routing_driver_missing')
        assert(di<4096,'routing_driver_index')
        assert(read(ptr(ptr(driver+0x38,true)+di*8,true),24,true)==e.weapon,'routing_driver_identity')
        local held=read(ptr(driver+0x48,true)+di*8,8,true):byte(1)~=0
        row.weapon_driver_flags=string.format('%08x',flags)
        row.native_fire_held=held
        cap.weapon_plan={weapon_id=e.weapon_id,weapon=e.weapon,owner=e.owner,
            manager=wm,address=address,flags=flags,held=held,same=e.checked,identity=identity}
        row.test_avatar_allowed=AvatarScope.apply(e,row,cap,e.avatar_flags)
        cap.interrupt=not row.test_avatar_allowed or held
        return cap
    end,'routing')
end
return M
