-- Physical mouse edges are independent of C4 mode and native Fire/Aim binds.
-- Full release is required after arming, focus or weapon identity changes.
local M={}
function M.new(emit)
    local self={identity=nil,ready=false,left=false,right=false}
    function self.sample(identity,left,right)
        local output={deploy=false,detonate=false}
        if not identity or identity~=self.identity then
            self.identity=identity;self.ready=false
        end
        if not identity then self.left=left.down;self.right=right.down;return output end
        if not self.ready then
            self.left=left.down;self.right=right.down
            if not left.down and not right.down and not left.pressed and not right.pressed then self.ready=true end
            return output
        end
        output.deploy=right.pressed and not self.right
        output.detonate=left.pressed and not self.left
        self.left=left.down;self.right=right.down
        if output.deploy and output.detonate then
            output.deploy=false
            assert(emit('simultaneous_input',{input=(left.label or 'LMB')..'+'..(right.label or 'RMB'),resolution='DETONATE_PRIORITY',
                dropped_action='DEPLOY'}),'mouse_router_log_unavailable')
        end
        return output
    end
    return self
end
return M
