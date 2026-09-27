-- Original weapon actions, passenger lean and normal (non-forced) reload.
local M={}
function M.new(api,reader,base,layout,bind,emit)
    local game=assert(api.module('game.dll'),'game_module_missing')
    local resolved=NativeResolver.resolve(api,game,layout)
    R,D=resolved.symbols,resolved.fields
    local native=bind(game)
    local self={compatibility=resolved,input=native}
    function self.verify() resolved.verify() end
    self.passenger=PassengerHold.new(api,game,base,self.verify,emit)
    function self.close()return self.passenger.stop('shutdown_or_fault')end
    function self.maintain(enabled,now)
        if not self.passenger.lease then return end
        local _,_,cap=self.snapshot()
        self.passenger.sync(enabled,cap,now)
    end
    function self.snapshot()
        local row,reason,cap=reader.snapshot(api,game,base)
        if not row then return nil,reason end
        return row,nil,cap
    end
    function self.reload(cap)
        local r=assert(cap and cap.reload,'reload_context_unavailable')
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
        assert(cap and not cap.active and not cap.blocked and cap.deploy_ready,'ineligible_lean_capability')
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
        assert(cap and not cap.active and not cap.blocked,'ineligible_action_capability')
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
