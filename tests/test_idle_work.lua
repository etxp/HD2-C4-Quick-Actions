local function check(name,fn)fn();print('PASS '..name)end
local function controller_fixture(diagnostics)
    local file=assert(io.open('src/ActionController.lua'));local text=file:read('*a');file:close()
    local Controller=assert(loadstring('local VehiclePrepare=dofile("src/VehiclePrepare.lua")\n'..text))()
    local s={reads=0,calls={},row={context_status='c4_context_observed',current_fire_mode='DEPLOY'},cap={identity='c4',
        active=false,blocked=false,interrupt=false,deploy_ready=true}}
    s.backend={snapshot=function()s.reads=s.reads+1;return s.row,nil,s.cap end,
        execute=function(action,cap)
            assert(cap==s.cap);s.calls[#s.calls+1]={action=action,identity=cap.identity}
            cap.active=true;cap.ability_id=action=='DEPLOY' and 521 or 520
            return cap.ability_id
        end}
    s.controller=Controller.new(s.backend,function()return true end,{diagnostics=diagnostics})
    return s
end
check('Off action idle skips redundant observation after the released baseline',function()
    local s=controller_fixture(false)
    s.controller.step(true,0,{allowed=true});assert(s.reads==1)
    for n=1,1000 do s.controller.step(true,n*16,{allowed=true})end
    assert(s.reads==1 and #s.calls==0)
    s.controller.step(false,17000,{allowed=false})
    s.controller.step(true,17016,{allowed=true});assert(s.reads==2)
end)
check('Off action request obtains a fresh weapon context even after long idle',function()
    local s=controller_fixture(false)
    s.controller.step(true,0,{allowed=true})
    s.cap.identity='replacement-c4'
    s.controller.step(true,16000,{allowed=true,deploy=true})
    assert(s.reads==3 and #s.calls==1 and s.calls[1].identity=='replacement-c4')
end)
check('Off action request still rejects newly unavailable or blocked context',function()
    for _,case in ipairs({'missing','blocked'})do
        local s=controller_fixture(false)
        s.controller.step(true,0,{allowed=true})
        if case=='missing'then s.cap=nil else s.cap.blocked=true end
        s.controller.step(true,500,{allowed=true,deploy=true})
        assert(s.reads==2 and #s.calls==0)
    end
end)
check('Off active lifecycle and queued action remain observed without new input',function()
    local s=controller_fixture(false)
    s.controller.step(true,0,{allowed=true})
    s.controller.step(true,100,{allowed=true,deploy=true})
    assert(#s.calls==1 and s.controller.lock and s.controller.lock.saw_active)
    s.controller.step(true,150,{allowed=true,detonate=true})
    assert(s.controller.pending and #s.calls==1)
    s.cap.active=false
    s.controller.step(true,220,{allowed=true})
    assert(#s.calls==2 and s.calls[2].action=='DETONATE' and s.controller.pending==nil)
end)
check('diagnostic action idle retains the original periodic observation',function()
    local s=controller_fixture(true)
    s.controller.step(true,0,{allowed=true});s.controller.step(true,60,{allowed=true})
    assert(s.reads==2)
end)
local function load_reload()
    local f=assert(io.open('src/AutoReload.lua'));local text=f:read('*a');f:close()
    return assert(loadstring('local PassengerReloadRecovery=dofile("src/PassengerReloadRecovery.lua")\n'..text))()
end
check('an active UI stack skips avatar work and map still blocks immediately after close',function()
    local R=dofile('private/tests/mock_symbols.lua')
    local D=dofile('private/tests/mock_fields.lua')
    local bit=require('bit')
    local pressed=false
    _G.ModBindingsMenu={api=1,version=2,ready=function()return true end,
        register_binding=function()return true end,is_down=function(id)
            return pressed and id=='etxp.c4_quick_actions.deploy'
        end}
    local s=dofile('tests/gamepad_entry_fixture.lua'){
        entry='private/build/c4_quick_actions.off.lua',window=true,native_ui=true,aim_profile=true}
    for _=1,8 do s.tick()end
    s.ui(11);s.tick()
    local reads=0;local old=s.api.read
    s.api.read=function(at,n)if at==s.game+R.global_avatar then reads=reads+1 end;return old(at,n)end
    for _=1,8 do s.tick()end
    assert(reads==0,'active UI should not traverse avatar')
    local address=s.avatar_flags+math.floor(D.tactical_map/32)*4
    local flag=2^(D.tactical_map%32)
    local base=dofile('private/tests/modules/context_reader.lua')(R,D)
    s.u32(address,bit.bor(base.u32(s.api.read(address,4),0),flag))
    s.ui();local calls=#s.calls;pressed=true;s.tick();pressed=false;s.tick()
    assert(reads>0 and #s.calls==calls,'map behind closed UI must retain veto')
    s.u32(address,bit.band(base.u32(s.api.read(address,4),0),bit.bnot(flag)))
    for _=1,8 do s.tick()end
    pressed=true;s.tick();pressed=false;s.tick()
    assert(#s.calls>calls and not s.module.disabled)
    assert(_G.shutdown()=='shutdown-original')
end)
local Reload=load_reload()
check('suspending without a passenger recovery ticket does not read native C4 state',function()
    local calls=0
    local r=Reload.new({snapshot=function()calls=calls+1;error('unexpected snapshot')end},function()return true end)
    for n=1,100 do r.suspend(n)end
    assert(calls==0 and r.intent==nil)
end)
check('suspension still observes and retires a passenger recovery on weapon switch',function()
    local calls=0
    local row={current_weapon='C4_DETONATOR'}
    local cap={identity='c4',reload_identity='c4',vehicle={},reload={ammo=2,chamber_empty=true}}
    local r=Reload.new({snapshot=function()calls=calls+1;return row,nil,cap end},function()return true end)
    r.arm(0);assert(calls==1)
    r.suspend(10);assert(calls==2 and r.fields().reload_dismount_pending)
    row={current_weapon='OTHER'};cap=nil;r.suspend(20)
    assert(calls==3 and not r.fields().reload_dismount_pending)
    r.suspend(30);assert(calls==3)
end)
for _,diagnostics in ipairs({true,false})do
 check('resupply automatic reload preserves behavior with diagnostics '..tostring(diagnostics),function()
    local calls=0
    local cap={identity='c4',reload_identity='c4',interrupt=false,active=false,
        reload={ammo=0,chamber_empty=true,avatar_active=false,ability=123}}
    local backend={passenger={},snapshot=function()return {},nil,cap end,
        reload=function(current)assert(current==cap);calls=calls+1;return true end}
    local r=Reload.new(backend,function()return true end,{diagnostics=diagnostics})
    r.step(true,0,false);assert(calls==0)
    cap.reload.ammo=2;r.step(true,16,false);assert(calls==1 and r.intent==nil)
    r.step(true,32,false);assert(calls==1)
    cap.reload.ammo=0;r.step(true,48,false)
    cap.reload.ammo=2;r.step(true,64,true);assert(calls==1)
    r.step(true,80,false);assert(calls==1)
 end)
end
