-- Called inside the existing action controller, using its single pending slot.
-- A native lean request is made once. The Deploy waits for the observed native
-- transition to finish; time alone never authorizes a throw.
local M={}
function M.new(backend,publish)
    local self={}
    function self.wait(p,cap)
        assert(p.action=='DEPLOY' and p.prepare=='vehicle_lean','invalid_preparation')
        if not cap.vehicle then return false,'vehicle_left' end
        if cap.active then return false,'native_action_busy' end
        if not cap.deploy_ready then return false,'native_deploy_ammo_not_ready' end
        if cap.vehicle_ready then return true end
        if not p.lean_requested and not cap.vehicle.transition and not cap.vehicle.leaned then
            -- Log before the side effect; backend rechecks code and all read
            -- identities immediately before calling the original seat method.
            publish('vehicle_lean_call',{requested_action='DEPLOY',vehicle_id=cap.vehicle.vehicle_id,
                vehicle_seat=cap.vehicle.seat,action_result='NATIVE_LEAN_REQUEST'})
            local accepted,reason=backend.prepare_deploy(cap)
            if not accepted then return false,reason end
            p.lean_requested=true
            publish('vehicle_lean_returned',{requested_action='DEPLOY',action_result='WAITING_FOR_NATIVE_LEAN'})
        end
        return false
    end
    return self
end
return M

