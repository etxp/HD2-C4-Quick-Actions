-- One optional reload request per throw or observed empty -> resupply.
-- Defer a new resupply opportunity through the action already in progress;
-- never interrupt it or replay a request after a subsequent player operation.
local M={}
function M.new(backend,emit)
    local self={identity=nil,ammo=nil,intent=nil,status='idle',observation=nil,latest={}}
    local recovery=PassengerReloadRecovery.new(emit)
    local function observe(cap,now)
        local r=cap.reload
        self.latest={reload_sample_at_ms=now,reload_spare_ammo=r.ammo,
            reload_chamber_empty=r.chamber_empty,avatar_ability_active=r.avatar_active,
            avatar_ability_id=r.avatar_ability,avatar_ability_time=r.avatar_time,
            native_action_active=cap.active,active_ability_id=cap.ability_id,
            reload_passenger=cap.vehicle~=nil,
            reload_seat_leaned=cap.vehicle and cap.vehicle.leaned or false,
            reload_seat_idle=cap.vehicle and cap.vehicle.idle or false,
            reload_seat_transition=cap.vehicle and cap.vehicle.transition or false}
    end
    local function publish(status,reason)
        if self.status==status and not reason then return end
        self.status=status
        local fields={auto_reload_status=status,reason=reason}
        for k,v in pairs(self.latest) do fields[k]=v end
        assert(emit('auto_reload',fields),'auto_reload_log_unavailable')
    end
    function self.cancel(reason,reset)
        if self.intent then self.intent=nil;publish('cancelled',reason) end
        if reset then self.identity=nil;self.ammo=nil;self.observation=nil end
    end
    function self.arm(now)
        local _,_,cap=backend.snapshot()
        if not cap or not cap.reload then return end
        observe(cap,now)
        self.identity=cap.identity;self.ammo=cap.reload.ammo
        recovery.arm(cap)
        self.intent={identity=cap.identity,at=now,source='throw',waiting_since=nil,
            passenger=cap.vehicle~=nil,avatar_active_at_arm=cap.reload.avatar_active}
        publish('waiting_for_throw')
    end
    function self.suspend(now)
        local ok,row,_,cap=pcall(backend.snapshot)
        if ok then recovery.observe(row,cap,false,now,false) end
        self.cancel('controls_suspended',true)
    end
    function self.step(allowed,now,player_priority)
        if not allowed then self.suspend(now);return end
        local row,_,cap=backend.snapshot()
        local dismounted=recovery.observe(row,cap,true,now,player_priority)
        if not cap or not cap.reload then self.cancel('context_unavailable',true);return end
        local r=cap.reload
        observe(cap,now)
        local observation=table.concat({cap.identity,tostring(r.ammo),
            tostring(row.reload_supply_source),tostring(row.reload_supply_entity_id)},':')
        if observation~=self.observation then
            self.observation=observation
            assert(emit('reload_ammo_observed',{reload_spare_ammo=r.ammo,
                reload_supply_source=row.reload_supply_source,
                reload_supply_entity_id=row.reload_supply_entity_id,
                reload_chamber_empty=r.chamber_empty,avatar_ability_active=r.avatar_active,
                avatar_ability_id=r.avatar_ability}),'reload_observation_log_unavailable')
        end
        if cap.identity~=self.identity then
            self.cancel('identity_changed');self.identity=cap.identity;self.ammo=r.ammo
        end
        local resupplied=self.ammo==0 and r.ammo>0 and r.chamber_empty
        self.ammo=r.ammo
        if player_priority or cap.interrupt then self.cancel('player_operation');return end
        if cap.active and cap.ability_id~=521 then self.cancel('weapon_action');return end
        if resupplied and not self.intent then
            recovery.arm(cap)
            self.intent={identity=cap.identity,at=now,source='resupply'}
            if r.avatar_active and r.avatar_ability~=r.ability and r.avatar_time then
                -- Remember the action already running when ammo arrives, not
                -- a hardcoded pickup ability. Any replacement/reset cancels.
                self.intent.wait_avatar={ability=r.avatar_ability,time=r.avatar_time}
            end
            publish('waiting_for_reload','empty_then_resupplied')
        end
        if dismounted and not self.intent then
            self.intent={identity=cap.identity,at=now,source='dismount'}
            publish('waiting_for_reload','passenger_dismounted_empty')
        end
        local p=self.intent;if not p then return end
        if p.identity~=cap.identity or r.ammo<=0 or now-p.at>=8000 then
            self.cancel(r.ammo<=0 and 'no_spare_ammunition' or 'opportunity_expired');return
        end
        if not r.chamber_empty then self.cancel('chamber_already_loaded');return end
        -- Never accumulate seat stability through a native action or lease.
        if r.avatar_active or cap.active or backend.passenger.lease then p.seat_stable=nil end
        if r.avatar_active then
            if r.avatar_ability==r.ability then
                -- The engine may attempt phase-30 reload while the passenger
                -- throw still owns the seat. Preserve one post-throw chance
                -- only for that early attempt, never for a reload we requested.
                if p.source=='throw' and p.passenger and not p.avatar_active_at_arm and not p.early_native_finished and
                    r.avatar_time and (not p.early_native_time or r.avatar_time>=p.early_native_time) and
                    ((cap.active and cap.ability_id==521) or p.early_native_reload) then
                    p.early_native_reload=true;p.early_native_time=r.avatar_time
                    publish('waiting_for_native_vehicle_reload');return
                end
                self.cancel('native_reload_already_running');return
            end
            local w=p.wait_avatar
            if w and r.avatar_ability==w.ability and r.avatar_time and r.avatar_time>=w.time then
                w.time=r.avatar_time;publish('waiting_for_current_action');return
            end
            self.cancel('avatar_action');return
        end
        if p.early_native_reload then p.early_native_finished=true end
        p.wait_avatar=nil
        if cap.active then
            -- Vehicle throws retain dev.7's complete native lifecycle.
            if cap.vehicle or p.source~='throw' or not cap.deploy_released then return end
        end
        if backend.passenger.lease then return end
        if cap.vehicle then
            local v=cap.vehicle
            if not v.idle then
                p.seat_stable=nil;publish('waiting_for_seat_transition');return
            end
            -- Releasing the throw reservation leaves a briefly idle relation
            -- BEFORE native retract starts (observed in dev.11). One idle frame
            -- cannot authorize reload. Require an unchanged lean state across
            -- at least three observations and 250 ms, with no pending animation.
            -- Stable lean-out is also allowed, so holding Aim cannot deadlock it.
            local s=p.seat_stable
            if not s or s.leaned~=v.leaned then
                s={leaned=v.leaned,at=now,samples=0};p.seat_stable=s
            end
            s.samples=s.samples+1
            self.latest.reload_seat_stable_ms=now-s.at
            self.latest.reload_seat_stable_samples=s.samples
            if now-s.at<250 or s.samples<3 then publish('waiting_for_seat_settle');return end
        end
        p.waiting_since=p.waiting_since or now
        if now-p.waiting_since>1500 then self.cancel('native_reload_not_eligible');return end
        local accepted=backend.reload(cap)
        if accepted then
            self.intent=nil;publish('requested',p.source)
        else publish('waiting_for_native_eligibility') end
    end
    function self.fields()
        return {auto_reload_status=self.status,auto_reload_pending=self.intent~=nil,
            reload_dismount_pending=recovery.pending~=nil}
    end
    return self
end
return M
