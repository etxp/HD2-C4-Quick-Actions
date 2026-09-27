-- Build 24826606: 0x738be0 tests Weapon flags bit 12 before dispatching
-- the normal C4 Fire edge through 0x7cd310. EXP04 temporarily owns only
-- this bit of the exact local C4 instance; actions still use the native ABI.
local M={}
local bit=require('bit')
local NORMAL,MUTED=0x1148,0x148

function M.new(api,game,base,emit,verify)
    local self={lease=nil,active=false,status='idle',identity=nil}
    local function publish(status,extra)
        if self.status==status and not extra then return end
        self.status=status
        local fields={fire_gate_status=status,fire_gate_active=self.active,
            native_fire_route='Weapon.flags.bit12',native_aim_behavior='UNCHANGED'}
        for k,v in pairs(extra or {}) do fields[k]=v end
        assert(emit('fire_gate',fields),'fire_gate_log_unavailable')
    end
    local function current()
        return base.snapshot(api,game,function(e,row)
            local wm=e.global(0x276c390)
            local wi=assert(e.lookup(wm+0x28,e.weapon_id,65536),'fire_gate_component_missing')
            assert(wi<4096,'fire_gate_index_limit')
            assert(e.read(e.ptr(e.ptr(wm+0x40,true)+wi*8,true),24,true)==e.weapon,
                'fire_gate_registry_mismatch')
            local address=e.ptr(wm+0x50,true)+wi*40
            local flags=e.u32(e.read(address,4,true),0)
            row.weapon_driver_flags=string.format('%08x',flags)
            assert(flags==NORMAL or flags==MUTED,'fire_gate_unsupported_flags')
            -- Acquire only after vanilla Fire was released. Muting the driver
            -- while its edge latch is true would retain a stale Fire state.
            local driver=e.global(0x276c728)
            local di=assert(e.lookup(driver+0x20,e.weapon_id,65536),'fire_gate_driver_missing')
            assert(di<4096,'fire_gate_driver_index_limit')
            assert(e.read(e.ptr(e.ptr(driver+0x38,true)+di*8,true),24,true)==e.weapon,
                'fire_gate_driver_identity_mismatch')
            local held=e.read(e.ptr(driver+0x48,true)+di*8,1,true):byte()~=0
            return {weapon_id=e.weapon_id,weapon=e.weapon,owner=e.owner,manager=wm,
                address=address,flags=flags,held=held,same=e.checked,
                identity=table.concat({e.hex(e.entity),e.hex(e.weapon),tostring(e.owner)},':')}
        end)
    end
    -- Restoration must survive inventory changes and component compaction.
    -- Resolve the saved entity again instead of trusting an old state address.
    local function saved(lease)
        local guards,reads={},0
        local function read(at,n)
            assert(type(at)=='number' and at>=65536 and at+n<0x800000000000,'fire_gate_bad_address')
            reads=reads+1;assert(reads<=400 and n>0 and n<=32,'fire_gate_restore_budget')
            local b=assert(api.read(at,n),'fire_gate_restore_read_unavailable')
            assert(#b==n,'fire_gate_restore_short_read');guards[#guards+1]={at,b};return b
        end
        local function ptr(at) return assert(api.pointer(read(at,8)),'fire_gate_restore_bad_pointer') end
        local function lookup(at,key)
            local h=read(at,20);local n,empty,mult=base.u32(h,8),base.u32(h,12),base.u32(h,16)
            assert(n<=1048576 and (n==0 or bit.band(n,n-1)==0),'fire_gate_restore_map')
            if n==0 or key==empty or key==0xffffffff then return nil end
            local p=assert(api.pointer(h),'fire_gate_restore_map_pointer')
            for i=0,math.min(n,128)-1 do
                local b=read(p+((base.product_low(key,mult)+i)%n)*8,8)
                local k,index=base.u32(b,0),base.u32(b,4)
                if k==key then return index~=0xffffffff and index or nil end
                if k==empty then return nil end
            end
            error('fire_gate_restore_probe_limit')
        end
        local wm,owner=ptr(game+0x276c390),ptr(game+0x276f0c0)
        if wm~=lease.manager or owner~=lease.owner then return nil,'entity_epoch_gone' end
        local ei=lookup(owner+0xf19a70,lease.weapon_id)
        if not ei then return nil,'entity_gone' end
        assert(ei<262144,'fire_gate_restore_entity_index')
        if read(owner+0xf31ad8+ei*24,24)~=lease.weapon then return nil,'entity_reused' end
        local wi=lookup(wm+0x28,lease.weapon_id)
        if not wi then return nil,'component_gone' end
        assert(wi<4096,'fire_gate_restore_index')
        if read(ptr(ptr(wm+0x40)+wi*8),24)~=lease.weapon then return nil,'registry_reused' end
        local address=ptr(wm+0x50)+wi*40
        local flags=base.u32(read(address,4),0)
        for _,g in ipairs(guards) do assert(api.read(g[1],#g[2])==g[2],'fire_gate_restore_changed') end
        return {address=address,flags=flags}
    end
    function self.stop()
        self.active=false;self.identity=nil
        local lease=self.lease
        if not lease then return true end
        local ok,p,reason=pcall(saved,lease)
        if not ok then self.status=tostring(p);return false,self.status end
        if not p then self.lease=nil;self.status=reason;return true end
        if p.flags==MUTED then
            local restored,why=api.fire_gate_exchange(p.address,MUTED,NORMAL)
            if not restored then self.status=why;return false,why end
        elseif p.flags~=NORMAL then
            -- Do not overwrite a configuration change from the engine/mods.
            self.status='fire_gate_restore_configuration_changed';return false,self.status
        end
        self.lease=nil;self.status='restored';return true
    end
    function self.sync(enabled,released)
        self.active=false;self.identity=nil
        if not enabled and not self.lease then publish('disarmed');return false end
        local ok,row,why,plan=pcall(current)
        if not ok then why=row;row=nil end
        if not enabled or not plan then
            -- If disarming while a button is held on this C4, release the
            -- mute only after both mouse buttons are up. Do not replay it as
            -- vanilla Fire when F6/menu/focus turns routing off.
            if not enabled and plan and self.lease and plan.identity==self.lease.identity and not released then
                publish('waiting_for_mouse_release');return false
            end
            local restored,reason=self.stop();assert(restored,reason)
            publish(not enabled and 'disarmed' or row and row.action_context_error or why or 'outside_c4')
            return false
        end
        if self.lease and self.lease.identity~=plan.identity then
            local restored,reason=self.stop();assert(restored,reason)
        end
        if not self.lease then
            if plan.flags~=NORMAL then publish('preexisting_fire_gate_not_owned');return false end
            if not released or plan.held then publish('waiting_for_released_baseline');return false end
            if verify then verify() end
            -- Log intent before a data mutation, just as action calls do.
            publish('acquire',{selected_entity_id=plan.weapon_id,flags_before='00001148',flags_after='00000148'})
            assert(plan.same(),'fire_gate_acquire_context_changed')
            self.lease=plan -- retain restoration ownership even on a failed readback
            local written,reason=api.fire_gate_exchange(plan.address,NORMAL,MUTED)
            assert(written,reason)
        elseif plan.flags~=MUTED then
            error('fire_gate_changed_while_owned')
        end
        self.active=true;self.identity=plan.identity
        publish('owned');return true
    end
    function self.fields()
        return {fire_gate_active=self.active,fire_gate_status=self.status,
            fire_gate_restore_pending=self.lease~=nil and not self.active,
            native_aim_behavior='UNCHANGED'}
    end
    return self
end
return M
