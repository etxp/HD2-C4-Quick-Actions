-- EXP06: automatic C4 routing. R/menu/focus pauses never switch the feature off.
local last_pad_epoch=0
local last_guard_blocked=false
local last_pad_down={false,false}
local function suspend_actions()
    router.sample(nil,{down=false,pressed=false},{down=false,pressed=false})
    actions.step(false,M.elapsed_ms,{allowed=false})
end
local function tick(dt)
    M.phase='before_original_update';M.tick=M.tick+1
    if type(dt)=='number' and dt>=0 and dt<math.huge then M.elapsed_ms=M.elapsed_ms+dt*1000 end
    local md,mp=sample(marker)
    if mp and marker.down~=true then emit('manual_marker',{input='F7',enabled=M.capture}) end
    marker.down=md
    local ld,lp,lr=sample(mouse[1]);local rd,rp,rr=sample(mouse[2])
    local pad=gamepad.sample(M.elapsed_ms)
    local guard_keys={}
    for _,key in ipairs(cancel_keys) do guard_keys[#guard_keys+1]=key end
    for _,key in ipairs(pad.menus) do guard_keys[#guard_keys+1]=key end
    local guard_blocked=input_guard.sample(guard_keys)
    last_guard_blocked=guard_blocked
    local released=not ld and not rd and not lp and not rp and pad.released
    last_controls_released=released;last_pad_available=pad.available
    last_controls_allowed=gameplay_guard.sample(focus(),guard_blocked,released) and pad.available
    local owned=gate.sync(last_controls_allowed,released)
    if pad.epoch~=last_pad_epoch then
        suspend_actions();last_pad_epoch=pad.epoch;last_pad_down={false,false}
    end
    local identity=owned and (gate.identity..':pad:'..pad.epoch) or nil
    local request=router.sample(identity,
        {down=ld or pad.right.down,pressed=lp or pad.right.pressed,released=lr or pad.right.released,
            label=pad.right.pressed and pad.right.label or 'LMB'},
        {down=rd or pad.left.down,pressed=rp or pad.left.pressed,released=rr or pad.left.released,
            label=pad.left.pressed and pad.left.label or 'RMB'})
    poll_mouse(mouse[1],ld,lp,lr);poll_mouse(mouse[2],rd,rp,rr)
    for i,b in ipairs({pad.left,pad.right}) do
        if b.label and (b.pressed or b.released or b.down~=last_pad_down[i]) then
            emit('input',{input=b.label,device=b.device,button_id=b.button_id,
                event=b.pressed and 'PRESSED' or b.released and 'RELEASED' or 'BASELINE',
                down=b.down,trigger_value=b.value,source='engine_gamepad_analog_hysteresis'})
        end
        last_pad_down[i]=b.down
    end
    actions.step(owned and last_controls_allowed,M.elapsed_ms,{
        deploy=request.deploy,detonate=request.detonate,allowed=last_controls_allowed,mouse=false,
        deploy_input=pad.left.pressed and pad.left.label or 'RMB',
        detonate_input=pad.right.pressed and pad.right.label or 'LMB'})
    if file and M.tick%60==0 then assert(file:flush(),'log_flush_failed') end
end
local function after_update()
    M.phase='after_original_update'
    -- The original update can open or close a UI during this callback.
    -- Recheck before return and invalidate pending/edges immediately on pause.
    last_controls_allowed=gameplay_guard.sample(focus(),last_guard_blocked,last_controls_released)
        and last_pad_available and not M.disabled
    local owned=gate.sync(last_controls_allowed,last_controls_released)
    if not owned or not last_controls_allowed then suspend_actions() end
end
