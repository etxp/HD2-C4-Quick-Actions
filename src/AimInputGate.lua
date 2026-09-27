-- Own the selected native input inhibition record while local C4 needs it.
-- Never edit mapping records, camera/pose state or executable code.
local M={}
function M.new(api,game,base,backend,profile,emit,spec)
    spec=spec or {action=D.input_aim_action,code=D.input_aim_code,index=8,tag="aim_gate"}
    local tag=spec.tag
    local behavior=spec.fire and "native_fire_input_behavior" or "native_aim_behavior"
    local self={lease=nil,status='starting'}
    local native=backend.input
    local function publish(status,reason)
        if self.status==status and self.reason==reason then return end
        self.status=status;self.reason=reason
        assert(emit(tag,{[tag..'_status']=status,[tag..'_reason']=reason,
            [behavior]=self.lease and 'SUPPRESSED' or 'ORIGINAL',
            [tag..'_owned']=self.lease~=nil}),'aim_gate_log_unavailable')
    end
    local function read(codes)
        return AimInputState.read(api,game,base,codes,native,spec)
    end
    function self.stop()
        local lease=self.lease;if not lease then return true end
        local ok,p=pcall(read)
        if not ok then return false,tostring(p) end
        if p.owner==lease.owner and p.mask and (p.mask.bytes==lease.expected or
            lease.pending and p.mask.mode==1 and p.mask.bytes:sub(17,24)==string.rep('\0',8)) then
            backend.verify();assert(p.same(),'aim_restore_context_changed')
            native.input_unblock(p.owner,spec.action)
            local q=read();assert(q.owner==p.owner and q.mask and q.mask.mode==0,'aim_restore_failed')
        end
        -- Other engine/mod inhibition owns its changes; never clear those.
        self.lease=nil;return true
    end
    local function step(enabled,now)
        if not enabled then
            local ok,why=self.stop();assert(ok,why);publish('inactive');return
        end
        local row,_,cap=backend.snapshot()
        if not cap or cap.interrupt then
            local ok,why=self.stop();assert(ok,why);publish('outside_c4');return
        end
        local codes=spec.fire or profile(now)
        if not codes then
            local ok,why=self.stop();assert(ok,why);publish('unavailable','mbm_assignments_missing');return
        end
        backend.verify()
        local p=read(codes)
        local suppress,reason=true,'mbm_owns_c4_fire'
        if not spec.fire then suppress,reason=AimInputState.policy(base,p) end
        if self.lease and (self.lease.owner~=p.owner or self.lease.identity~=cap.identity
            or not p.mask or p.mask.bytes~=self.lease.expected) then
            local ok,why=self.stop();assert(ok,why)
            p=read(codes)
        end
        if not suppress then
            local ok,why=self.stop();assert(ok,why);publish('preserved',reason);return
        end
        if self.lease then publish('owned',reason);return end
        if p.mask and p.mask.mode~=0 then publish('external_inhibition');return end
        -- Do not enter while native Aim is latched: acquire at a released
        -- baseline, before the next physical activation can reach Aim.
        if p.held then publish(spec.fire and 'waiting_for_fire_release' or 'waiting_for_aim_release');return end
        assert(p.mask or p.count<D.input_inhibit_capacity,'aim_inhibition_full')
        publish('acquire',reason)
        assert(cap.same() and p.same(),'aim_acquire_context_changed')
        self.lease={owner=p.owner,identity=cap.identity,pending=true}
        native.input_inhibit(p.owner,spec.action)
        local q=read()
        assert(q.owner==p.owner and q.mask and q.mask.mode==1
            and q.mask.bytes:sub(17,24)==string.rep('\0',8),'aim_acquire_failed')
        self.lease.expected=q.mask.bytes
        self.lease.pending=false
        publish('owned',reason)
    end
    function self.sync(enabled,now)
        local ok,why=pcall(step,enabled,now)
        if not ok then
            local restored,ok,reason=pcall(self.stop)
            publish('unavailable',tostring(why)..((not restored or not ok) and '; restore: '..tostring(reason or ok) or ''))
        end
    end
    function self.fields()
        return {[tag..'_status']=self.status,[tag..'_reason']=self.reason,
            [tag..'_owned']=self.lease~=nil,[behavior]=self.lease and 'SUPPRESSED' or 'ORIGINAL'}
    end
    return self
end
return M
