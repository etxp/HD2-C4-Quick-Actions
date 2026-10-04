-- One immutable mode per accepted throw; existing/manual charges are never
-- armed retroactively. Automatic impacts are independent of player input/UI.
local M={}
function M.new(backend,emit)
    local self={scopes={},prepared=nil,disabled=false}
    -- No collision is delayed: events are still sampled every phase. Only
    -- retirement of a quiet/despawned track is amortized over this interval.
    local RETIRE_MS=250
    local function remove(scope,id)
        local track=scope.tracks[id]
        if track and scope.units[track.unit]==id then scope.units[track.unit]=nil end
        scope.tracks[id]=nil
    end
    local function scope_count()
        local n=0;for _ in pairs(self.scopes)do n=n+1 end;return n
    end
    local function event_units()
        local units,merged
        for _,scope in pairs(self.scopes)do
            -- A pending throw's projectile does not have a known unit yet.
            -- Include every event so a spawn and impact in one phase survives.
            if scope.pending then return nil end
            if not units then units=scope.units
            else
                if not merged then
                    merged={};for unit in pairs(units)do merged[unit]=true end
                    units=merged
                end
                for unit in pairs(scope.units)do units[unit]=true end
            end
        end
        -- The common single-weapon case returns its existing index directly;
        -- this filter never authorizes calls or bypasses identity validation.
        return units
    end
    local function reclaim(now)
        -- Quiet retirement must not make rapid weapon turnover consume the
        -- old four-scope safety bound. Pay for immediate checked retirement
        -- only when a new weapon would otherwise exhaust that bound.
        for key,scope in pairs(self.scopes)do
            if scope.pending and now>scope.pending.until_ms then scope.pending=nil end
            if not scope.pending and next(scope.tracks)==nil then self.scopes[key]=nil end
        end
        if scope_count()<4 then return end
        local events,reason=backend.events()
        if not events then
            if reason=='physics_world_unavailable' then self.scopes={} end
            return
        end
        for key,scope in pairs(self.scopes)do
            if scope.lease.root~=events.root then self.scopes[key]=nil
            else
                local s=backend.tracked(scope.lease,events,scope.tracks)
                if s.expired then self.scopes[key]=nil
                else
                    local present={}
                    for _,c in ipairs(s.charges)do present[c.identity]=true end
                    for id in pairs(scope.tracks)do if not present[id]then remove(scope,id)end end
                    scope.last_retire=now
                    if not scope.pending and next(scope.tracks)==nil then self.scopes[key]=nil end
                end
            end
        end
    end
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
            local s=backend.selected(true);if not s then return end
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
            if p.snapshot.mode=='MANUAL' then
                -- Manual charges need no collision monitoring. A new throw
                -- supersedes any unmatched spawn window, while already armed
                -- Contact charges retain their immutable mode and tracking.
                if scope then
                    scope.pending=nil
                    if next(scope.tracks)==nil then self.scopes[lease.identity]=nil end
                end
                report('contact_throw_mode',{detonation_mode='MANUAL',weapon_id=lease.weapon_id})
                return
            end
            if not scope then
                if scope_count()>=4 then reclaim(now) end
                assert(scope_count()<4,'contact_scope_budget')
                scope={lease=lease,tracks={},units={},last_retire=now};self.scopes[lease.identity]=scope
            end
            -- Native C4 throws serialize; a missing projectile is never left
            -- as an invitation to arm a later unrelated spawn.
            scope.pending={known=p.known,mode=p.snapshot.mode,until_ms=now+2000}
            report('contact_throw_mode',{detonation_mode=p.snapshot.mode,weapon_id=lease.weapon_id})
        end)
    end
    function self.step(now)
        if self.disabled or next(self.scopes)==nil then return end
        return safe(function()
            -- Expire unmatched throws even if no stable physics snapshot is
            -- available. They must never arm an unrelated later projectile.
            for key,scope in pairs(self.scopes)do
                if scope.pending and now>scope.pending.until_ms then scope.pending=nil end
                if not scope.pending and next(scope.tracks)==nil then self.scopes[key]=nil end
            end
            if next(self.scopes)==nil then return end
            local events,reason=backend.events(event_units())
            if not events then
                if reason=='physics_world_unavailable' then self.scopes={} end
                return
            end
            for key,scope in pairs(self.scopes)do
                if scope.lease.root~=events.root then self.scopes[key]=nil
                else
                    local p=scope.pending
                    local retire=now-scope.last_retire>=RETIRE_MS
                    local wanted
                    if not p then
                        if retire then wanted=scope.tracks
                        else
                            -- A stale unit number is only a candidate, never
                            -- authority to call native code. Reader rechecks
                            -- ownership, generation and all component links.
                            for _,event in ipairs(events.contacts)do
                                if event.kind~=2 and event.unit_a~=event.unit_b then
                                    local a,b=scope.units[event.unit_a],scope.units[event.unit_b]
                                    if a then wanted=wanted or {};wanted[a]=scope.tracks[a] end
                                    if b then wanted=wanted or {};wanted[b]=scope.tracks[b] end
                                end
                            end
                        end
                    end
                    if p or wanted then
                        local s=backend.tracked(scope.lease,events,wanted)
                        if s.expired then self.scopes[key]=nil
                        else
                            local present={}
                            local newborn={}
                            for _,c in ipairs(s.charges)do
                                present[c.identity]=true
                                if p and not p.known[c.identity] then newborn[#newborn+1]=c end
                            end
                            if p and #newborn>0 then
                                assert(#newborn==1,'contact_ambiguous_new_projectiles')
                                local c=newborn[1]
                                scope.tracks[c.identity]={mode=p.mode,id=c.id,unit=c.unit}
                                scope.units[c.unit]=c.identity
                                scope.pending=nil
                                report('contact_charge_registered',{charge_entity_id=c.id,detonation_mode=p.mode})
                            end
                            for id in pairs(wanted or scope.tracks)do if not present[id]then remove(scope,id) end end
                            if p or retire then scope.last_retire=now end
                            for _,c in ipairs(s.charges)do
                                local track=scope.tracks[c.identity]
                                -- A native request can suppress our call, but it
                                -- is not evidence of completed destruction. Keep
                                -- the immutable mode if that flag later clears.
                                if track and track.mode=='CONTACT' and not c.requested and c.contact then
                                    -- Rebuild after each call; native detonation may change
                                    -- component arrays/state even before the next update.
                                    local fresh=backend.tracked(scope.lease,events,{[c.identity]=track})
                                    for _,target in ipairs(fresh.charges)do
                                        if target.identity==c.identity and not target.requested and target.contact then
                                            backend.verify();assert(fresh.same(),'contact_capability_changed')
                                            report('contact_detonate_call',{charge_entity_id=c.id,
                                                detonation_mode='CONTACT',action_result='CALL_BEGIN'})
                                            assert(fresh.same(),'contact_identity_changed_before_call')
                                            backend.explode(target)
                                            -- This is a one-shot request, just as
                                            -- the former fired flag was. Retaining
                                            -- the completed charge only wastes scans.
                                            remove(scope,c.identity)
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
            end
        end)
    end
    function self.stop()self.scopes={};self.prepared=nil end
    return self
end
return M
