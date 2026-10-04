-- Original weapon actions, passenger lean and normal (non-forced) reload.
local M={}
function M.new(api,reader,base,layout,bind,emit,scan)
    local game=assert(api.module('game.dll'),'game_module_missing')
    local resolved=NativeResolver.resolve(api,game,layout,scan)
    R,D=resolved.symbols,resolved.fields
    local native=bind(game)
    local self={compatibility=resolved,input=native}
    local snapshots=SnapshotCache.new(function()
        local row,reason,cap,same=reader.snapshot(api,game,base)
        if not row then return nil,reason end
        return row,nil,cap,same
    end)
    local routing=SnapshotCache.new(function()
        return RoutingReader.snapshot(api,game,base)
    end)
    -- The complete action snapshot guards every byte the routing observation
    -- guards. When the previous after-update phase consumed it, revalidate it
    -- first so the routing observation shares those spans instead of reading
    -- the same pages a second time.
    local after,primed,full_used,full_expected=false,false,false,false
    -- full_due=false: automatic reload will not take its complete observation
    -- in this phase, so the action snapshot is not revalidated ahead of time.
    function self.begin_phase(kind,full_due)
        if api.memo_begin then api.memo_begin() end
        snapshots.begin_phase();routing.begin_phase()
        after=kind=='after';primed=false
        if after then
            if full_due==false then full_expected=false
            else full_expected=full_used;full_used=false end
        end
    end
    function self.end_phase()
        snapshots.end_phase();routing.end_phase();after=false
        if api.memo_end then api.memo_end() end
    end
    function self.invalidate()
        if api.memo_reset then api.memo_reset() end
        snapshots.invalidate();routing.invalidate()
    end
    -- Mutations invalidate both data paths even when they fail. Read-only
    -- mapping/count queries preserve the uninterrupted observation phase;
    -- mutating consumers still enforce cap.same() immediately before use.
    for _,name in ipairs({'start','consume','after','lean','reload','input_inhibit','input_unblock'}) do
        local call=assert(native[name],'observation_mutator_missing:'..name)
        native[name]=function(...)self.invalidate();return call(...)end
    end
    for _,name in ipairs({'fire_gate_exchange','passenger_exchange'}) do
        local call=assert(api[name],'observation_mutator_missing:'..name)
        api[name]=function(...)self.invalidate();return call(...)end
    end
    function self.verify() resolved.verify() end
    -- Fresh reread of a few recorded records; true only if every byte is unchanged.
    function self.unchanged(records)
        if not records then return false end
        for i=1,#records do
            local g=records[i]
            if api.read(g.at,#g.bytes)~=g.bytes then return false end
        end
        return true
    end
    self.passenger=PassengerHold.new(api,game,base,self.verify,emit)
    function self.close()self.end_phase();return self.passenger.stop('shutdown_or_fault')end
    function self.maintain(enabled,now)
        if not self.passenger.lease then return end
        local _,_,cap=self.snapshot()
        self.passenger.sync(enabled,cap,now)
    end
    function self.snapshot()
        if after then full_used=true end
        return snapshots.snapshot()
    end
    function self.routing_snapshot()
        if after and full_expected and not primed then primed=true;snapshots.prime() end
        return routing.snapshot()
    end
    self.input_snapshot=self.routing_snapshot
    function self.reload(cap)
        local r=assert(cap and not cap.input_only and not cap.routing_only and cap.reload,'reload_context_unavailable')
        assert(not cap.interrupt and not r.avatar_active and r.ammo>0,'reload_context_ineligible')
        assert(not cap.active or (cap.deploy_released and not cap.vehicle),'reload_before_throw_release')
        assert(not self.passenger.lease,'reload_during_passenger_throw')
        assert(not cap.vehicle or not cap.vehicle.transition,'reload_during_seat_transition')
        assert(not cap.vehicle or cap.vehicle.idle,'reload_with_pending_seat_animation')
        self.verify();assert(cap.same(),'reload_context_changed')
        -- Preserve all native ammunition, state and animation eligibility.
        if not native.reload_eligible(r.manager,cap.weapon_id) then return false,'native_reload_veto' end
        assert(cap.same(),'reload_context_changed_after_query')
        assert(emit('reload_call',{requested_action='RELOAD',action_result='CALL_BEGIN'}),'reload_log_unavailable')
        assert(cap.same(),'reload_context_changed_before_call')
        native.reload(r.manager,cap.weapon_id)
        return true
    end
    function self.prepare_deploy(cap)
        assert(cap and not cap.input_only and not cap.active and not cap.blocked and cap.deploy_ready,'ineligible_lean_capability')
        local v=assert(cap.vehicle,'no_verified_passenger_seat')
        assert(not v.transition and not v.leaned,'lean_already_active')
        local supported,reason=resolved.vehicle_lean_available(v.config,v.seat)
        if not supported then return false,reason end
        self.verify()
        assert(cap.same(),'vehicle_context_changed')
        native.lean(v.manager,v.avatar_id)
        return true
    end
    function self.execute(action,cap,now)
        assert(action=='DEPLOY' or action=='DETONATE','unsupported_action')
        assert(cap and not cap.input_only and not cap.active and not cap.blocked,'ineligible_action_capability')
        assert(action~='DEPLOY' or cap.deploy_ready==true,'native_deploy_ammo_not_ready')
        assert(action~='DEPLOY' or not cap.vehicle or cap.vehicle_ready,'native_lean_not_ready')
        if action=='DEPLOY' and cap.vehicle then self.passenger.ready(cap) end
        -- Verify all guarded code again on each request; no native mutation
        -- occurs if another mod patched these functions after initialization.
        self.verify()
        assert(cap.same(),'action_context_changed')
        local id=action=='DEPLOY' and 521 or 520
        -- It is not 0.0. R9D=1 retains the original local/network path.
        native.start(cap.ability_manager,cap.weapon_id,id,1,1.0)
        if action=='DEPLOY' then
            native.consume(cap.weapon_manager,cap.weapon_id)
            local count=native.count(cap.weapon_manager,cap.weapon_id)
            native.after(cap.weapon_data,cap.weapon_id,count,true)
            if cap.vehicle then
                local _,_,fresh=self.snapshot()
                assert(fresh and fresh.identity==cap.identity,'passenger_hold_post_start_context')
                self.passenger.acquire(fresh,now)
            end
        end
        return id
    end
    return self
end
return M
