-- Reserve the selected passenger relation while its C4 Deploy is active.
-- The native lean request rejects busy relations. The verified seater updater
-- does not advance a transition whose pending node is INVALID. Acquire ONLY
-- from a completed, leaned-out, idle relation; do not invent a seat transition.
-- No executable writes, input injection, animation calls or timers are used.
local M={}
local bit=require('bit')
function M.new(api,game,base,verify,emit)
    local self={lease=nil,status='idle'}
    local function publish(status,reason)
        self.status=status
        assert(emit('passenger_hold',{passenger_hold_status=status,
            passenger_hold_active=self.lease~=nil,reason=reason}),'passenger_hold_log_unavailable')
    end
    -- Resolve the saved avatar/vehicle afresh, even after switching weapons.
    -- Never restore a stale address following component compaction or respawn.
    local function saved(lease)
        local guards={}
        local function read(at,n)
            assert(type(at)=='number' and at>=65536 and at+n<0x800000000000
                and n>0 and n<=64 and #guards<400,'passenger_hold_read_bounds')
            local value=assert(api.read(at,n),'passenger_hold_read_unavailable')
            assert(#value==n,'passenger_hold_short_read')
            guards[#guards+1]={at,value};return value
        end
        local function ptr(at)return assert(api.pointer(read(at,8)),'passenger_hold_pointer')end
        local function lookup(at,id,limit)
            local h=read(at,20);local n,empty,mult=base.u32(h,8),base.u32(h,12),base.u32(h,16)
            assert(n<=limit and (n==0 or bit.band(n,n-1)==0),'passenger_hold_map')
            if n==0 or id==empty or id==0xffffffff then return nil end
            local p=assert(api.pointer(h),'passenger_hold_map_pointer')
            for i=0,math.min(n,128)-1 do
                local b=read(p+((base.product_low(id,mult)+i)%n)*8,8)
                local key,index=base.u32(b,0),base.u32(b,4)
                if key==id then return index~=0xffffffff and index or nil end
                if key==empty then return nil end
            end
            error('passenger_hold_probe_limit')
        end
        local manager,owner=ptr(game+R.global_vehicle),ptr(game+R.global_owner)
        if manager~=lease.manager or owner~=lease.owner then return nil,'world_changed' end
        local ai=lookup(owner+D.entity_id_map,lease.avatar_id,1048576)
        local vi=lookup(owner+D.entity_id_map,lease.vehicle_id,1048576)
        if not ai or not vi then return nil,'entity_gone' end
        assert(ai<262144 and vi<262144,'passenger_hold_entity_index')
        if read(owner+D.entity_array+ai*24,24)~=lease.avatar_entity
            or read(owner+D.entity_array+vi*24,24)~=lease.vehicle_entity then return nil,'entity_reused' end
        local index=lookup(manager+0x20,lease.avatar_id,65536)
        if not index then return nil,'relation_gone' end
        assert(index<4096,'passenger_hold_relation_index')
        if read(ptr(ptr(manager+0x38)+index*8),24)~=lease.avatar_entity then return nil,'registry_changed' end
        local address=ptr(manager+0x48)+index*64
        local bytes=read(address,64)
        for _,g in ipairs(guards) do assert(api.read(g[1],#g[2])==g[2],'passenger_hold_context_changed') end
        return {address=address,bytes=bytes}
    end
    function self.stop(reason)
        local lease=self.lease;if not lease then return true end
        local ok,p,why=pcall(saved,lease)
        if not ok then self.status=tostring(p);return false,self.status end
        if p and p.bytes==lease.expected then
            local restored,err=api.passenger_exchange(p.address,lease.expected,0)
            if not restored then self.status=err;return false,err end
        elseif p and p.bytes~=lease.original then
            -- Exit/seat changes and native transitions own their new state.
            -- Clearing their busy flag would interrupt the engine's transition.
            why='relation_changed_by_engine'
        end
        self.lease=nil
        publish('released',why or reason)
        return true
    end
    function self.ready(cap)
        assert(not self.lease,'passenger_hold_already_owned')
        local v=assert(cap.vehicle,'passenger_hold_no_vehicle')
        assert(not cap.interrupt and v.leaned and not v.transition,'passenger_hold_not_ready')
        assert(base.u32(v.bytes,0x18)==0xffffffff and base.u32(v.bytes,0x20)==0xffffffff
            and v.bytes:sub(0x29,0x30)==string.rep('\0',8)
            and v.bytes:sub(0x33,0x34)=='\0\0','passenger_hold_transition_not_idle')
        return v
    end
    function self.acquire(cap,now)
        local v=self.ready(cap)
        assert(cap.active and cap.ability_id==521,'passenger_hold_deploy_not_active')
        verify();assert(cap.same(),'passenger_hold_acquire_context_changed')
        publish('acquire','until_native_deploy_finishes')
        local expected=v.bytes:sub(1,0x30)..'\1'..v.bytes:sub(0x32)
        self.lease={manager=v.manager,owner=v.owner,avatar_id=v.avatar_id,vehicle_id=v.vehicle_id,
            avatar_entity=v.avatar_entity,vehicle_entity=v.vehicle_entity,identity=cap.identity,
            original=v.bytes,expected=expected,start=now}
        local ok,why=api.passenger_exchange(v.address,v.bytes,1)
        assert(ok,why)
        publish('holding')
    end
    function self.sync(enabled,cap,now)
        local lease=self.lease;if not lease then return end
        local reason
        if not enabled then reason='controls_interrupted'
        elseif not cap or cap.identity~=lease.identity then reason='context_changed'
        elseif cap.interrupt then reason='avatar_interrupted'
        elseif not cap.active or cap.ability_id~=521 then reason='native_deploy_finished_or_replaced'
        elseif now-lease.start>=8000 then reason='native_deploy_timeout'
        elseif not cap.vehicle or cap.vehicle.bytes~=lease.expected then reason='relation_changed' end
        if reason then local ok,why=self.stop(reason);assert(ok,why) end
    end
    return self
end
return M
