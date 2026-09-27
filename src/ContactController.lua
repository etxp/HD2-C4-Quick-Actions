-- One immutable mode per accepted throw; existing/manual charges are never
-- armed retroactively. Automatic impacts are independent of player input/UI.
local M={}
function M.new(backend,emit)
    local self={scopes={},prepared=nil,disabled=false}
    local function report(kind,row)assert(emit(kind,row),'contact_log_unavailable')end
    local function safe(fn,...)
        if self.disabled then return end
        local ok,a,b=pcall(fn,...)
        if not ok then
            self.disabled=true;self.prepared=nil;self.scopes={}
            pcall(emit,'contact_fault',{reason=tostring(a),contact_detonation_enabled=false})
            return
        end
        return a,b
    end
    function self.prepare(now)
        return safe(function()
            self.prepared=nil
            local s=backend.selected();if not s then return end
            local known={};for _,c in ipairs(s.charges)do known[c.identity]=true end
            self.prepared={snapshot=s,known=known,at=now}
        end)
    end
    function self.commit(now)
        return safe(function()
            local p=self.prepared;self.prepared=nil
            if not p or now-p.at>1000 then return end
            local lease=p.snapshot.lease
            local scope=self.scopes[lease.identity]
            if not scope then
                local n=0;for _ in pairs(self.scopes)do n=n+1 end;assert(n<4,'contact_scope_budget')
                scope={lease=lease,tracks={},known=p.known};self.scopes[lease.identity]=scope
            end
            -- Native C4 throws serialize; a missing projectile is never left
            -- as an invitation to arm a later unrelated spawn.
            scope.pending={known=p.known,mode=p.snapshot.mode,until_ms=now+2000}
            report('contact_throw_mode',{detonation_mode=p.snapshot.mode,weapon_id=lease.weapon_id})
        end)
    end
    function self.step(now)
        return safe(function()
            if next(self.scopes)==nil then return end
            local events,reason=backend.events()
            if not events then
                if reason=='physics_world_unavailable' then self.scopes={} end
                return
            end
            for key,scope in pairs(self.scopes)do
                if scope.lease.root~=events.root then self.scopes[key]=nil
                else
                    local s=backend.tracked(scope.lease,events)
                    if s.expired then self.scopes[key]=nil
                    else
                        local present={};local p=scope.pending
                        if p and now>p.until_ms then scope.pending=nil;p=nil end
                        local newborn={}
                        for _,c in ipairs(s.charges)do
                            present[c.identity]=true
                            if p and not p.known[c.identity] then newborn[#newborn+1]=c end
                        end
                        if p and #newborn>0 then
                            assert(#newborn==1,'contact_ambiguous_new_projectiles')
                            local c=newborn[1];scope.tracks[c.identity]={mode=p.mode,fired=false}
                            scope.pending=nil
                            report('contact_charge_registered',{charge_entity_id=c.id,detonation_mode=p.mode})
                        end
                        for id in pairs(scope.tracks)do if not present[id]then scope.tracks[id]=nil end end
                        for _,c in ipairs(s.charges)do
                            local track=scope.tracks[c.identity]
                            if track and track.mode=='CONTACT' and not track.fired and not c.requested and c.contact then
                                -- Rebuild after each call; native detonation may change
                                -- component arrays/state even before the next update.
                                local fresh=backend.tracked(scope.lease,events)
                                for _,target in ipairs(fresh.charges)do
                                    if target.identity==c.identity and not target.requested and target.contact then
                                        backend.verify();assert(fresh.same(),'contact_capability_changed')
                                        report('contact_detonate_call',{charge_entity_id=c.id,
                                            detonation_mode='CONTACT',action_result='CALL_BEGIN'})
                                        assert(fresh.same(),'contact_identity_changed_before_call')
                                        track.fired=true
                                        backend.explode(target)
                                        report('contact_detonate_returned',{charge_entity_id=c.id,action_result='NATIVE_CALL_RETURNED'})
                                        break
                                    end
                                end
                            end
                        end
                        if not scope.pending and next(scope.tracks)==nil then self.scopes[key]=nil end
                    end
                end
            end
        end)
    end
    function self.stop()self.scopes={};self.prepared=nil end
    return self
end
return M
