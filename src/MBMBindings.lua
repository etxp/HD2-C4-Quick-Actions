-- MBM owns device mappings and activation types. No physical-key fallback.
local M={}
function M.new(get_api,emit)
    local defs={
        {action='deploy',id='etxp.c4_quick_actions.deploy',label='Throw C4'},
        {action='detonate',id='etxp.c4_quick_actions.detonate',label='Detonate C4'},
    }
    local self={provider=nil,registered={},status='starting',epoch=0,next_attempt=0,
        identity=nil,armed=false,previous={deploy=false,detonate=false}}
    local function status(value,reason)
        if self.status==value and self.reason==reason then return end
        self.status=value;self.reason=reason
        assert(emit('mod_bindings',{mbm_status=value,mbm_reason=reason,
            mbm_original_controls='REMOVED',mbm_input_support='MBM_V2_NATIVE_INPUTS'}))
    end
    function self.cancel()
        self.identity=nil;self.armed=false
        self.previous={deploy=false,detonate=false}
    end
    function self.fields()
        return {mbm_status=self.status,mbm_reason=self.reason,mbm_epoch=self.epoch,
            mbm_input_armed=self.armed,mbm_original_controls='REMOVED'}
    end
    local function unavailable(reason)
        self.cancel();status('unavailable',reason)
        return {available=false,released=false,deploy=false,detonate=false}
    end
    function self.sample(now)
        local api=get_api()
        if api~=self.provider then
            self.provider=api;self.registered={};self.epoch=self.epoch+1
            self.next_attempt=0;self.cancel()
        end
        if type(api)~='table' or api.api~=1 or type(api.version)~='number' or api.version<2
            or type(api.register_binding)~='function' or type(api.is_down)~='function'
            or type(api.ready)~='function' then return unavailable('MBM v2 required') end
        for _,def in ipairs(defs) do
            if not self.registered[def.id] then
                if now<self.next_attempt then return unavailable('registration_retry_wait') end
                local called,ok,why=pcall(api.register_binding,def.id,def.label,0,
                    {category='HD2 C4 Quick Actions'})
                if not called or ok~=true then
                    self.next_attempt=now+1000
                    return unavailable(tostring(not called and ok or why or 'registration_rejected'))
                end
                self.registered[def.id]=true
            end
        end
        local called,ready=pcall(api.ready)
        if not called or ready~=true then return unavailable('native_input_not_ready') end
        local result={available=true}
        for _,def in ipairs(defs) do
            local ok,value=pcall(api.is_down,def.id)
            if not ok or type(value)~='boolean' then return unavailable('binding_unavailable:'..def.action) end
            result[def.action]=value
        end
        result.released=not result.deploy and not result.detonate
        status('ready')
        return result
    end
    function self.route(identity,allowed,input)
        local result={deploy=false,detonate=false,allowed=allowed,mouse=false,
            deploy_input=defs[1].id,detonate_input=defs[2].id}
        if not allowed or not identity or not input.available then self.cancel();return result end
        if self.identity~=identity then self.cancel();self.identity=identity end
        if not self.armed then
            self.armed=input.released
            self.previous={deploy=input.deploy,detonate=input.detonate}
            return result
        end
        result.detonate=input.detonate and not self.previous.detonate
        result.deploy=input.deploy and not self.previous.deploy and not result.detonate
        self.previous={deploy=input.deploy,detonate=input.detonate}
        if result.deploy or result.detonate then
            assert(emit('input',{source='MBM_ONLY',input=result.detonate and defs[2].id or defs[1].id,
                event='ACTIVATED',simultaneous_resolution=result.detonate and input.deploy and 'DETONATE_PRIORITY' or nil}))
        end
        return result
    end
    return self
end
return M
