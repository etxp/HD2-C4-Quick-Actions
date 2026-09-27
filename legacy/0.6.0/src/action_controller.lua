-- Test-key routing, independent of FFI and native layout.
-- Native active -> inactive is an observed lifecycle end, NOT gameplay success.
local M={}
function M.new(backend,emit,options)
    options=options or {}
    local labels={DEPLOY=options.deploy_input or 'F8',DETONATE=options.detonate_input or 'F9'}
    local self={latest={},last_sample=-math.huge,last_emit=-math.huge,lock=nil,pending=nil,
        fault=nil,serial=0,was_armed=false,last_key=nil}
    local function publish(kind,extra)
        local fields={action_lock=self.lock and self.lock.action or 'IDLE',
            pending_action=self.pending and self.pending.action or 'NONE'}
        for k,v in pairs(extra or {}) do fields[k]=v end
        assert(emit(kind,fields),'action_log_unavailable')
    end
    local function drop_pending(reason)
        if self.pending then
            local old=self.pending;self.pending=nil
            publish('pending_dropped',{requested_action=old.action,reason=reason})
        end
    end
    local function abandon(reason)
        drop_pending(reason)
        if self.lock then
            local old=self.lock;self.lock=nil
            publish('action_observation_ended',{requested_action=old.action,request_id=old.id,
                action_result='COMPLETION_UNKNOWN',reason=reason})
        end
    end
    local function observe(now)
        local ok,row,reason,cap=pcall(backend.snapshot)
        if not ok then reason=row;row=nil end
        if not row then row={context_status='snapshot_unavailable',current_weapon='UNKNOWN',
            current_fire_mode='UNKNOWN',reason=tostring(reason)} end
        self.latest=row;self.last_sample=now
        local key=table.concat({row.context_status,tostring(row.selected_entity_id),
            tostring(row.current_fire_mode),tostring(row.action_gate),tostring(row.active_ability_id),
            tostring(row.native_action_active),tostring(row.ammo_available),tostring(row.deploy_ammo_ready),
            tostring(row.weapon_driver_flags),tostring(row.ammo_path),tostring(row.action_context_error),
            tostring(row.action_read_stage),tostring(row.reason)},'|')
        if key~=self.last_key or now-self.last_emit>=1000 then
            publish('action_context');self.last_key=key;self.last_emit=now
        end
        return cap
    end
    function self.fields(now)
        local row={}
        for k,v in pairs(self.latest) do row[k]=v end
        row.context_sample_age_ms=now-self.last_sample
        row.action_lock=self.lock and self.lock.action or 'IDLE'
        row.pending_action=self.pending and self.pending.action or 'NONE'
        row.action_fault=self.fault or 'NONE'
        return row
    end
    local function reject(action,reason)
        publish('action_rejected',{requested_action=action,reason=reason,action_result='NOT_EXECUTED'})
    end
    local function unavailable_reason()
        return self.latest.action_context_error or self.latest.reason or 'no_fresh_c4_context'
    end
    local function execute(action,now,cap,from_pending,request_input)
        if not cap then reject(action,unavailable_reason());return end
        if cap.blocked then reject(action,self.latest.action_gate);return end
        if cap.active then reject(action,'native_action_busy');return end
        if action=='DEPLOY' and not cap.deploy_ready then
            reject(action,self.latest.deploy_ammo_reason or 'native_deploy_ammo_not_ready');return
        end
        self.serial=self.serial+1
        local lock={action=action,id=self.serial,identity=cap.identity,start=now,
            ability=action=='DEPLOY' and 521 or 520,saw_active=false,mode=self.latest.current_fire_mode}
        self.lock=lock
        -- This record must reach the file before any native side effect.
        publish('action_call',{requested_action=action,request_id=lock.id,
            action_result='CALL_BEGIN',ability_id=lock.ability,
            input=from_pending and 'PENDING' or request_input or labels[action],
            original_input=request_input or labels[action]})
        local ok,result=pcall(backend.execute,action,cap)
        if not ok then
            self.fault=tostring(result);drop_pending('native_call_error')
            publish('action_fault',{requested_action=action,request_id=lock.id,
                action_result='OUTCOME_UNKNOWN',reason=self.fault})
            return
        end
        publish('action_returned',{requested_action=action,executed_action=action,
            request_id=lock.id,ability_id=result,action_result='NATIVE_CALL_RETURNED'})
        local post=observe(now)
        if not post or post.identity~=lock.identity or not post.active or post.ability_id~=lock.ability then
            self.fault='native_start_not_observed';drop_pending(self.fault)
            publish('action_fault',{requested_action=action,request_id=lock.id,
                action_result='START_UNCONFIRMED',reason=self.fault})
            return
        end
        lock.saw_active=true
        publish('action_started',{requested_action=action,executed_action=action,
            request_id=lock.id,action_result='NATIVE_ACTIVE_OBSERVED',fire_mode_before=lock.mode,
            fire_mode_after=self.latest.current_fire_mode,
            fire_mode_unchanged=lock.mode==self.latest.current_fire_mode})
        if lock.mode~=self.latest.current_fire_mode then
            self.fault='fire_mode_changed_during_native_call'
            publish('action_fault',{requested_action=action,request_id=lock.id,
                action_result='MODE_CHANGE_OBSERVED',reason=self.fault})
        end
    end
    function self.step(armed,now,input)
        input=input or {}
        if not armed or not input.allowed then
            abandon(not armed and 'capture_off' or 'focus_or_controls_blocked')
            self.was_armed=false;self.last_sample=-math.huge
            self.latest={context_status='actions_disarmed',current_weapon='UNKNOWN',current_fire_mode='UNKNOWN'}
            return
        end
        local request=input.deploy and input.detonate and 'BOTH' or
            input.deploy and 'DEPLOY' or input.detonate and 'DETONATE' or nil
        local request_input=request=='DEPLOY' and input.deploy_input or
            request=='DETONATE' and input.detonate_input or nil
        -- Require a full released baseline on arming. A key held before F6
        -- cannot become an action, even if a device repeats pressed flags.
        if not self.was_armed then
            self.was_armed=true;observe(now)
            if request then reject(request,'arming_baseline') end
            return
        end
        if self.fault then if request then reject(request,'fault_latched_restart_required') end;return end
        if input.mouse then
            drop_pending('original_mouse_input')
            if request then reject(request,'original_mouse_input') end
            request=nil
        end
        if not request and now-self.last_sample<50 then return end
        local cap=observe(now)
        if not cap then
            abandon('c4_context_unavailable')
            if request then reject(request,unavailable_reason()) end
            return
        end
        if self.lock then
            local lock=self.lock
            if cap.identity~=lock.identity then abandon('weapon_or_avatar_changed')
            elseif cap.active and cap.ability_id~=lock.ability then abandon('native_action_replaced')
            elseif not cap.active and lock.saw_active then
                self.lock=nil
                publish('action_finished',{requested_action=lock.action,request_id=lock.id,
                    action_result='NATIVE_LIFECYCLE_ENDED',gameplay_result='REQUIRES_VISUAL_CONFIRMATION'})
            elseif now-lock.start>=8000 then
                self.fault='native_completion_timeout';drop_pending(self.fault)
                publish('action_fault',{requested_action=lock.action,request_id=lock.id,
                    action_result='COMPLETION_UNKNOWN',reason=self.fault})
                return
            end
        end
        if self.pending and now-self.pending.at>1500 then drop_pending('pending_expired') end
        if cap.interrupt or input.mouse or (cap.blocked and not self.lock) then
            drop_pending('controls_or_native_state_blocked')
            if request then reject(request,'controls_or_native_state_blocked') end
            return
        end
        if request=='BOTH' then
            reject(request,'simultaneous_test_keys_rejected');return
        end
        if self.pending and not self.lock then
            local p=self.pending
            -- Live EXP03.1: native action ends before the next chamber is
            -- ready. Preserve the one queued Deploy across that short native
            -- refill window, retaining its ORIGINAL deadline and identity.
            -- Never wait behind an unrelated active action or bypass ammo.
            if p.identity==cap.identity and not cap.active and p.action=='DEPLOY'
                and not cap.deploy_ready and self.latest.deploy_ammo_reason=='rounds_chamber_blocked' then
                if not p.waiting_ammo then
                    p.waiting_ammo=true
                    publish('pending_waiting',{requested_action=p.action,
                        reason='native_chamber_not_ready',action_result='PENDING_ONE'})
                end
                if request then
                    reject(request,p.action==request and 'pending_coalesced' or 'pending_slot_full')
                end
                return
            end
            self.pending=nil
            if p.identity==cap.identity then
                execute(p.action,now,cap,true,p.input)
                if request then reject(request,'pending_dispatched_this_callback') end
                return
            end
            publish('pending_dropped',{requested_action=p.action,reason='identity_changed'})
        end
        if not request then return end
        publish('action_request',{requested_action=request,action_result='REQUESTED',
            input=request_input or labels[request]})
        if self.lock then
            if not self.pending then
                self.pending={action=request,at=now,identity=cap.identity,input=request_input or labels[request]}
                publish('action_queued',{requested_action=request,action_result='PENDING_ONE'})
            else
                reject(request,self.pending.action==request and 'pending_coalesced' or 'pending_slot_full')
            end
            return
        end
        execute(request,now,cap,false,request_input)
    end
    return self
end
return M
