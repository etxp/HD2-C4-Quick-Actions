-- EXP06 mock integration: actual reload disarm regression and auto activation.
-- Window/UI states are simulated; real engine values still need live validation.
local fixture,ffi=dofile('tests/gamepad_entry_fixture.lua')
local passed=0
local function test(name,f)
    local ok,err=pcall(f);package.loaded.ffi=ffi
    assert(ok,name..': '..tostring(err));passed=passed+1;print('PASS '..name)
end
local function scenario(options)
    options=options or {};options.entry='src/c4_dual_input_auto.lua'
    if options.window==nil then options.window=true end
    local s=fixture(options)
    function s.arm(dt) s.tick(dt);s.tick(dt);assert(s.module.capture and not s.module.disabled) end
    return s
end
local function contains(s,word) return table.concat(s.lines):find(word,1,true)~=nil end

for _,profile in ipairs({'mouse','xbox','ps'}) do
    for _,mode in ipairs({0,1}) do
        for _,hz in ipairs({30,60,144}) do
            test('automatic '..profile..' both actions, mode '..mode..', '..hz..' Hz',function()
                local s=scenario({pad_profile=profile~='mouse' and profile or nil,
                    pad_slot=profile=='ps' and 'PS4Pad1' or 'Pad1'})
                s.u32(0x4b000000+16,mode);s.arm(1/hz)
                local function input(side,down)
                    if profile=='mouse' then s.button(side=='left' and 1 or 0,down,1/hz)
                    else s.trigger(side,down and 1 or 0,1/hz) end
                end
                input('left',true)
                for i=1,hz do if i==math.floor(hz/2) then s.complete() end;s.tick(1/hz) end
                assert(#s.calls==4 and s.calls[1][2]==521 and #s.vanilla==0)
                input('left',false);input('right',true)
                for i=1,hz do if i==math.floor(hz/2) then s.complete() end;s.tick(1/hz) end
                assert(#s.calls==5 and s.calls[5][2]==520 and #s.vanilla==0)
                input('right',false)
                assert(s.module.capture and not s.module.disabled and s.flags()==0x148)
                assert(contains(s,'"reason":"automatic_activation"'))
                assert(not contains(s,'"reason":"manual_toggle"'))
                assert(_G.shutdown()=='shutdown-original' and s.flags()==0x1148)
            end)
        end
    end
end
test('empty C4, resupply, R chamber refill, both mouse actions without F6',function()
    local s=scenario();s.u32(s.rounds_state+4,0);s.arm()
    s.button(1,true);s.button(1,false);s.finish();assert(#s.calls==4)
    s.button(0,true);s.button(0,false);s.finish();assert(#s.calls==5)
    s.u32(s.rounds_state+4,4) -- resupply gives reserve rounds but no chamber token
    s.key('r',true);assert(s.module.capture and s.flags()==0x1148)
    s.u32(s.rounds_state+0x10,54);s.put(s.rounds_runtime+0x10,'\0') -- native reload completed
    s.key('r',false);s.tick();assert(s.module.capture and s.flags()==0x148)
    s.button(1,true);s.button(1,false);s.finish()
    s.button(0,true);s.button(0,false);s.finish()
    assert(#s.calls==10 and s.calls[6][2]==521 and s.calls[10][2]==520 and #s.vanilla==0)
    assert(not contains(s,'"enabled":false') and not s.module.disabled)
    assert(contains(s,'reload_or_menu_key_held'))
end)
test('F6 has no enable or disable effect',function()
    local s=scenario();s.arm();s.key('f6',true);s.key('f6',false)
    s.button(1,true);assert(#s.calls==4 and s.module.capture and s.flags()==0x148)
end)
test('held mouse during R is discarded until release and a fresh press',function()
    local s=scenario();s.arm();s.key('r',true);s.button(1,true);s.key('r',false)
    for _=1,5 do s.tick() end
    assert(#s.calls==0 and s.module.capture)
    s.button(1,false);s.tick();s.button(1,true);assert(#s.calls==4)
end)
test('reload cancels pending without later replay',function()
    local s=scenario();s.arm();s.button(1,true);s.button(1,false)
    s.button(0,true);s.button(0,false);s.key('r',true);s.finish();s.key('r',false);s.tick()
    assert(#s.calls==4 and s.module.capture)
    s.button(0,true);assert(#s.calls==5)
end)
for _,kind in ipairs({'OS focus','engine focus','visible UI cursor'}) do
    test(kind..' automatically resumes after release, without replaying held input',function()
        local s=scenario();s.arm()
        local function blocked(v)
            if kind=='OS focus' then s.focused=not v
            elseif kind=='engine focus' then s.engine_focus=not v else s.cursor_visible=v end
        end
        blocked(true);s.tick();assert(s.flags()==0x1148)
        s.button(1,true);blocked(false);s.tick();s.tick()
        assert(#s.calls==0 and s.module.capture and not s.module.disabled)
        s.button(1,false);s.tick();s.button(1,true);assert(#s.calls==4)
    end)
end
test('UI opening inside original update immediately invalidates pending actions',function()
    local s=scenario();s.arm();s.button(1,true);s.button(1,false)
    s.button(0,true);s.button(0,false)
    s.original_hook=function() s.cursor_visible=true;s.original_hook=nil end
    s.tick();s.finish();assert(#s.calls==4 and s.flags()==0x1148)
    s.cursor_visible=false;s.tick();s.tick();assert(#s.calls==4)
    s.button(0,true);assert(#s.calls==5)
end)
test('UI close via held controller trigger waits for a new pull',function()
    local s=scenario({pad_profile='xbox'});s.arm();local p=s.pad_devices.Pad1
    p.values[3]=1;p.presses[3]=true;s.cursor_visible=true;s.tick()
    p.values[3]=0;p.presses[3]=false;s.trigger('left',1)
    s.original_hook=function() s.cursor_visible=false;s.original_hook=nil end
    s.tick();s.tick();assert(#s.calls==0 and s.module.capture)
    s.trigger('left',0);s.tick();s.trigger('left',1);assert(#s.calls==4)
end)
test('gamepad operation does not require mouse capture',function()
    local s=scenario({pad_profile='xbox'});s.mouse_focus=false;s.arm()
    s.trigger('left',1);assert(#s.calls==4 and contains(s,'"window_mouse_focus":false'))
end)
test('equipping C4 while holding a mouse button needs a fresh press',function()
    local s=scenario();s.u32(s.state+0x1c,0);s.arm();assert(s.flags()==0x1148)
    s.button(1,true);s.u32(s.state+0x1c,3);s.tick();s.tick();assert(#s.calls==0)
    s.button(1,false);s.tick();s.button(1,true);assert(#s.calls==4)
    s.button(1,false);s.finish();s.u32(s.state+0x1c,0);s.tick();assert(s.flags()==0x1148)
    s.button(0,true);assert(s.vanilla[#s.vanilla]=='OTHER_WEAPON')
end)
test('startup held trigger is not converted into an automatic action',function()
    local s=scenario({pad_profile='xbox'});s.pad_devices.Pad1.values[21]=1;s.arm()
    assert(#s.calls==0 and #s.writes==0)
    s.trigger('right',0);s.tick();s.trigger('right',1);assert(#s.calls==1)
end)
test('automatic hotplug drops pending and reconnected held triggers',function()
    local s=scenario({pad_profile='xbox'});s.arm()
    s.trigger('left',1);s.trigger('left',0);s.trigger('right',1);s.trigger('right',0)
    s.pad_devices.Pad1.active=false;s.tick();s.finish();assert(#s.calls==4)
    local p=s.connect('Pad1','xbox');p.values[21]=1
    for _=1,40 do s.tick() end
    assert(#s.calls==4 and s.module.capture)
    s.trigger('right',0);s.tick();s.trigger('right',1);assert(#s.calls==5)
end)
test('simultaneous mirrored mouse and gamepad edges still choose Detonate once',function()
    local s=scenario({pad_profile='xbox'});s.arm()
    s.pad_devices.Pad1.values[20]=1;s.pad_devices.Pad1.values[21]=1
    s.mouse[0]={down=true,pressed=true};s.mouse[1]={down=true,pressed=true};s.tick()
    assert(#s.calls==1 and s.calls[1][2]==520 and #s.vanilla==0)
end)
test('missing window API prevents automatic takeover',function()
    local s=scenario({window=false});s.arm();s.button(1,true)
    assert(#s.calls==0 and #s.writes==0 and contains(s,'window_state_unavailable'))
end)
test('invalid window state pauses and valid state resumes after release',function()
    local s=scenario();s.arm();s.cursor_visible='invalid';s.tick();s.button(1,true)
    assert(#s.calls==0 and s.flags()==0x1148 and contains(s,'invalid_window_state'))
    s.cursor_visible=false;s.button(1,false);s.tick();s.button(1,true);assert(#s.calls==4)
end)
test('window API exception restores gate and cannot replay input on recovery',function()
    local s=scenario();s.arm();s.window_error=true;s.tick();s.button(1,true)
    assert(#s.calls==0 and s.flags()==0x1148)
    s.window_error=false;s.tick();assert(#s.calls==0)
    s.button(1,false);s.tick();s.button(1,true);assert(#s.calls==4)
end)
test('unsupported controller preserves original Fire instead of automatic takeover',function()
    local s=scenario({pad_profile='unsupported'});s.arm();s.trigger('right',1)
    assert(#s.calls==0 and #s.writes==0 and #s.vanilla==1 and not s.module.disabled)
end)
for _,option in ipairs({'bad_hash','bad_code'}) do
    test(option..' prevents native calls and gate writes',function()
        local s=scenario({[option]=true});s.tick();s.button(1,true)
        assert(s.module.disabled and #s.calls==0 and #s.writes==0 and s.updates==2)
    end)
end
test('original update exception restores gate and latches addon fault',function()
    local s=scenario();s.arm();s.original_error=true
    local ok,err=pcall(s.tick);assert(not ok and tostring(err):find('fixture_original_error',1,true))
    assert(s.module.disabled and not s.module.capture and s.flags()==0x1148)
    s.original_error=false;s.tick();s.button(1,true);assert(#s.calls==0 and s.flags()==0x1148)
end)
test('log failure restores gate and automatic mode cannot restart itself',function()
    local s=scenario();s.arm();s.log_failure=true;s.button(1,true)
    assert(s.module.disabled and #s.calls==0 and s.flags()==0x1148)
    s.log_failure=false;s.button(1,false);s.tick();assert(s.flags()==0x1148)
end)
test('automatic activation log failure stays inside startup failure handler',function()
    local s=scenario({fail_log_record='capture'});s.tick();s.button(1,true)
    assert(s.module.disabled and not s.module.capture and s.closed)
    assert(#s.calls==0 and #s.writes==0 and s.updates==2)
end)
print(string.format('Automatic integration suite: %d cases passed',passed))
