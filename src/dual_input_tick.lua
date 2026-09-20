-- EXP05: the mouse and selected gamepad share one native action lock/pending.
local last_pad_epoch=0
local last_guard_blocked=false
local last_pad_down={false,false}
local function tick(dt)
    M.tick=M.tick+1
    if type(dt)=='number' and dt>=0 and dt<math.huge then M.elapsed_ms=M.elapsed_ms+dt*1000 end
    local td,tp=sample(toggle)
    if tp and toggle.down~=true then
        M.capture=not M.capture
        for _,b in ipairs(mouse) do b.down=nil;b.held_ticks=0 end
        emit('capture',{enabled=M.capture,input='F6',reason='manual_toggle',
            scope='RMB / LT / L2 Deploy; LMB / RT / R2 Detonate; local C4 only'})
        assert(file:flush(),'log_flush_failed')
    end
    toggle.down=td
    local md,mp=sample(marker)
    if mp and marker.down~=true then emit('manual_marker',{input='F7',enabled=M.capture}) end
    marker.down=md
    local ld,lp,lr=sample(mouse[1]);local rd,rp,rr=sample(mouse[2])
    local pad=gamepad.sample(M.elapsed_ms)
    local guard_keys={}
    for _,key in ipairs(cancel_keys) do guard_keys[#guard_keys+1]=key end
    for _,key in ipairs(pad.menus) do guard_keys[#guard_keys+1]=key end
    local guard_blocked,cancel=input_guard.sample(guard_keys)
    if guard_blocked~=last_guard_blocked then
        emit('input_suspended',{suspended=guard_blocked,enabled=M.capture,reason='guard_key_state'})
        last_guard_blocked=guard_blocked
    end
    local focused=focus()
    if M.capture and (not focused or cancel) then
        M.capture=false
        local row=cancel or {};row.enabled=false;row.reason=not focused and 'focus_lost' or 'menu_key_edge'
        emit('capture',row);assert(file:flush(),'log_flush_failed')
    end
    local released=not ld and not rd and not lp and not rp and pad.released
    last_controls_released=released
    last_controls_allowed=pad.available and not guard_blocked
    local owned=gate.sync(M.capture and focused and last_controls_allowed,released)
    if pad.epoch~=last_pad_epoch then
        actions.step(false,M.elapsed_ms,{allowed=false});last_pad_epoch=pad.epoch
        last_pad_down={false,false}
    end
    local identity=owned and (gate.identity..':pad:'..pad.epoch) or nil
    local request=router.sample(identity,
        {down=ld or pad.right.down,pressed=lp or pad.right.pressed,released=lr or pad.right.released,
            label=pad.right.pressed and pad.right.label or 'LMB'},
        {down=rd or pad.left.down,pressed=rp or pad.left.pressed,released=rr or pad.left.released,
            label=pad.left.pressed and pad.left.label or 'RMB'})
    if M.capture then
        poll_mouse(mouse[1],ld,lp,lr);poll_mouse(mouse[2],rd,rp,rr)
        for i,b in ipairs({pad.left,pad.right}) do
            if b.label and (b.pressed or b.released or b.down~=last_pad_down[i]) then
                emit('input',{input=b.label,device=b.device,button_id=b.button_id,
                    event=b.pressed and 'PRESSED' or b.released and 'RELEASED' or 'BASELINE',
                    down=b.down,trigger_value=b.value,source='engine_gamepad_analog_hysteresis'})
            end
            last_pad_down[i]=b.down
        end
    else
        mouse[1].down=ld;mouse[2].down=rd
        mouse[1].held_ticks=0;mouse[2].held_ticks=0
        last_pad_down={pad.left.down,pad.right.down}
    end
    actions.step(M.capture and owned and last_controls_allowed,M.elapsed_ms,{
        deploy=request.deploy,detonate=request.detonate,allowed=focused,mouse=false,
        deploy_input=pad.left.pressed and pad.left.label or 'RMB',
        detonate_input=pad.right.pressed and pad.right.label or 'LMB'})
    if file and M.tick%60==0 then assert(file:flush(),'log_flush_failed') end
end
local function after_update()
    if gate then gate.sync(M.capture and not M.disabled and focus() and last_controls_allowed,last_controls_released) end
end
