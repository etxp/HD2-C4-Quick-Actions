-- A dismount is a new reload opportunity, not a retry loop in the vehicle.
local M={}
function M.new(emit)
    local self={pending=nil}
    function self.arm(cap)
        if cap.vehicle and cap.reload and cap.reload.ammo>0 then
            self.pending={identity=cap.reload_identity,saw_empty=cap.reload.chamber_empty}
        else self.pending=nil end
    end
    function self.observe(row,cap,allowed,now,priority)
        local p=self.pending;if not p then return false end
        if not cap or not cap.reload then
            -- Positive evidence of another selected weapon ends the ticket.
            if row and (row.current_weapon=='OTHER' or row.current_weapon=='C4_CHARGE'
                or row.context_status=='waiting_for_mission') then self.pending=nil end
            p.stable=nil;return false
        end
        local r=cap.reload
        if cap.reload_identity~=p.identity or r.ammo<=0 then
            self.pending=nil;return false
        end
        if not r.chamber_empty then
            -- Some native throws consume the chamber after the start callback.
            if not p.saw_empty and cap.active and cap.ability_id==521 then return false end
            self.pending=nil;return false
        end
        p.saw_empty=true
        if cap.vehicle then
            -- A second seat/vehicle is not a dismount; no request while seated.
            p.foot_at=nil;p.stable=nil;return false
        end
        if cap.seated then
            if row.avatar_action_scope=='UNSUPPORTED_VEHICLE' then self.pending=nil end
            p.foot_at=nil;p.stable=nil;return false
        end
        p.foot_at=p.foot_at or now
        if now-p.foot_at>=8000 or priority then self.pending=nil;return false end
        if not allowed or cap.interrupt or cap.active or r.avatar_active then
            p.stable=nil;return false
        end
        -- Wait for a settled on-foot context rather than the one-frame exit gap.
        p.stable=p.stable or {at=now,samples=0}
        p.stable.samples=p.stable.samples+1
        if now-p.stable.at<250 or p.stable.samples<3 then return false end
        self.pending=nil
        assert(emit('reload_dismount',{reason='passenger_charge_still_empty',
            reload_spare_ammo=r.ammo}),'reload_dismount_log_unavailable')
        return true
    end
    return self
end
return M
