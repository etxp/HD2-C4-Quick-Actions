-- Embedded by assemble_mouse.py in the same scope as the shared log shell.
local function tick(dt)
    M.tick=M.tick+1
    if type(dt)=='number' and dt>=0 and dt<math.huge then M.elapsed_ms=M.elapsed_ms+dt*1000 end
    local td,tp=sample(toggle)
    if tp and toggle.down~=true then
        M.capture=not M.capture
        for _,b in ipairs(mouse) do b.down=nil;b.held_ticks=0 end
        emit('capture',{enabled=M.capture,input='F6',scope='RMB Deploy / LMB Detonate; local C4 only'})
        assert(file:flush(),'log_flush_failed')
    end
    toggle.down=td
    local md,mp=sample(marker)
    if mp and marker.down~=true then emit('manual_marker',{input='F7'}) end
    marker.down=md
    local ld,lp,lr=sample(mouse[1]);local rd,rp,rr=sample(mouse[2])
    local focused=focus()
    local cancel=not focused
    for _,key in ipairs(cancel_keys) do
        local down,pressed=sample(key)
        if down or pressed then cancel=true end
        key.down=down
    end
    if M.capture and cancel then
        M.capture=false
        emit('capture',{enabled=false,reason=not focused and 'focus_lost' or 'menu_or_mode_key'})
    end
    local released=not ld and not rd and not lp and not rp
    last_mouse_released=released
    local owned=gate.sync(M.capture and focused,released)
    local request=router.sample(owned and gate.identity or nil,
        {down=ld,pressed=lp,released=lr},{down=rd,pressed=rp,released=rr})
    if M.capture then
        poll_mouse(mouse[1],ld,lp,lr);poll_mouse(mouse[2],rd,rp,rr)
    else
        mouse[1].down=ld;mouse[2].down=rd
        mouse[1].held_ticks=0;mouse[2].held_ticks=0
    end
    actions.step(M.capture and owned,M.elapsed_ms,{deploy=request.deploy,
        detonate=request.detonate,allowed=focused,mouse=false})
    if file and M.tick%60==0 then assert(file:flush(),'log_flush_failed') end
end

local function after_update()
    if gate then gate.sync(M.capture and not M.disabled and focus(),last_mouse_released) end
end

