-- Engine pad profiles and trigger behavior in the full assembled addon.
local scenario,ffi=dofile('tests/gamepad_entry_fixture.lua')
local passed=0
local function test(name,f)
    local ok,err=pcall(f);package.loaded.ffi=ffi
    assert(ok,name..': '..tostring(err));passed=passed+1;print('PASS '..name)
end
for _,profile in ipairs({'xbox','ps'}) do
    for _,mode in ipairs({0,1}) do
        for _,hz in ipairs({30,60,144}) do
            test(profile..' triggers preserve mode '..mode..' and do not repeat at '..hz..' Hz',function()
                local slot=profile=='ps' and 'PS4Pad1' or 'Pad1'
                local s=scenario({pad_profile=profile,pad_slot=slot});s.u32(0x4b000000+16,mode)
                s.arm(1/hz);s.trigger('left',1,1/hz)
                for i=1,hz*2 do if i==math.floor(hz/2) then s.complete() end;s.tick(1/hz) end
                assert(#s.calls==4 and s.calls[1][2]==521 and #s.vanilla==0)
                s.trigger('left',0,1/hz);s.trigger('right',1,1/hz)
                for i=1,hz*2 do if i==math.floor(hz/2) then s.complete() end;s.tick(1/hz) end
                assert(#s.calls==5 and s.calls[5][2]==520 and #s.vanilla==0)
                s.trigger('right',0,1/hz)
                local trace=table.concat(s.lines)
                assert(trace:find('"original_input":"'..(profile=='ps' and 'L2' or 'LT')..'"',1,true))
                assert(trace:find('"original_input":"'..(profile=='ps' and 'R2' or 'RT')..'"',1,true))
                assert(not s.module.disabled and s.module.capture)
                assert(_G.shutdown()=='shutdown-original' and s.flags()==0x1148)
            end)
        end
    end
end
test('PS trigger naming also works when the game exposes it through Pad1',function()
    local s=scenario({pad_profile='ps'});s.arm();s.trigger('left',1);assert(#s.calls==4)
    assert(table.concat(s.lines):find('"original_input":"L2"',1,true))
end)
test('analog hysteresis rejects partial pulls and threshold jitter',function()
    local s=scenario({pad_profile='xbox'});s.arm()
    for _,v in ipairs({0.1,0.3,0.54,0.4,0.53}) do s.trigger('right',v) end
    assert(#s.calls==0)
    s.trigger('right',0.55);s.finish();assert(#s.calls==1)
    for _,v in ipairs({0.54,0.3,0.26,0.54,0.7,1}) do s.trigger('right',v) end
    assert(#s.calls==1)
    s.trigger('right',0.25);s.trigger('right',0.8);assert(#s.calls==2)
end)
test('a held trigger at F6 enable waits for release and a new pull',function()
    local s=scenario({pad_profile='xbox'});s.pad_devices.Pad1.values[21]=1;s.arm()
    assert(#s.calls==0 and #s.writes==0)
    s.trigger('right',0);s.tick();s.trigger('right',1);assert(#s.calls==1)
end)
test('simultaneous LT and RT choose one Detonate, including mirrored mouse input',function()
    local s=scenario({pad_profile='xbox'});s.arm()
    s.pad_devices.Pad1.values[20]=1;s.pad_devices.Pad1.values[21]=1
    s.mouse[0]={down=true,pressed=true};s.mouse[1]={down=true,pressed=true};s.tick()
    assert(#s.calls==1 and s.calls[1][2]==520 and #s.vanilla==0)
    assert(table.concat(s.lines):find('"input":"RT+LT"',1,true))
end)
test('mouse and controller share one edge when a mapping mirrors the same held pull',function()
    local s=scenario({pad_profile='xbox'});s.arm();s.trigger('right',1);s.finish()
    s.button(0,true);assert(#s.calls==1)
    s.trigger('right',0);assert(#s.calls==1)
    s.button(0,false);s.trigger('right',1);assert(#s.calls==2)
end)
test('a mirrored Xbox and PS device never causes a second independent route',function()
    local s=scenario({pad_profile='xbox'});s.connect('PS4Pad1','ps');s.arm()
    s.pad_devices.PS4Pad1.values[20]=1;s.trigger('left',1)
    assert(#s.calls==4 and #s.vanilla==0)
end)
test('disconnection cancels pending and reconnect held triggers require release',function()
    local s=scenario({pad_profile='xbox'});s.arm()
    s.trigger('left',1);s.trigger('left',0);s.trigger('right',1);s.trigger('right',0)
    s.pad_devices.Pad1.active=false;s.tick();s.finish();assert(#s.calls==4)
    local p=s.connect('Pad1','xbox');p.values[21]=1
    for _=1,40 do s.tick() end
    assert(#s.calls==4 and s.module.capture)
    s.trigger('right',0);s.tick();s.trigger('right',1);assert(#s.calls==5)
end)
test('unsupported active pad leaves original Fire available and reports button names',function()
    local s=scenario({pad_profile='unsupported'});s.arm();s.trigger('right',1)
    assert(#s.calls==0 and #s.writes==0 and #s.vanilla==1 and not s.module.disabled)
    assert(table.concat(s.lines):find('unsupported_buttons',1,true))
end)
test('F6 disarm while holding RT waits for actual trigger release before restoration',function()
    local s=scenario({pad_profile='xbox'});s.arm();s.trigger('right',1);s.key('f6',true);s.key('f6',false)
    assert(s.flags()==0x148 and #s.vanilla==0)
    s.trigger('right',0.2);assert(s.flags()==0x148)
    s.trigger('right',0);assert(s.flags()==0x1148 and #s.vanilla==0)
end)
test('gamepad menu press disarms and records the exact input and raw state',function()
    local s=scenario({pad_profile='xbox'});s.arm();local p=s.pad_devices.Pad1
    p.values[3]=1;p.presses[3]=true;s.tick()
    assert(not s.module.capture and s.flags()==0x1148)
    local found=false
    for _,line in ipairs(s.lines) do
        if line:find('"record_type":"capture"',1,true) and line:find('"reason":"menu_key_edge"',1,true) then
            assert(line:find('"input":"Pad1.start"',1,true) and line:find('"raw_value":1',1,true));found=true
        end
    end
    assert(found)
end)
test('empty chamber never disables the addon and RT can still detonate',function()
    local s=scenario({pad_profile='xbox'});s.u32(s.rounds_state+4,0);s.arm()
    s.trigger('left',1);s.trigger('left',0);s.finish()
    for _=1,300 do s.tick() end
    assert(s.module.capture and not s.module.disabled and #s.calls==4 and s.flags()==0x148)
    s.trigger('right',1);s.trigger('right',0);s.finish()
    assert(#s.calls==5 and s.calls[5][2]==520 and s.module.capture)
end)
test('down-only guard state suspends temporarily without permanently toggling F6 off',function()
    local s=scenario();s.arm()
    s.keys[13]={down=true,pressed=false};s.tick()
    assert(s.module.capture and #s.calls==0)
    s.keys[13]={down=false,released=true};s.tick();s.tick();s.button(1,true)
    assert(s.module.capture and #s.calls==4)
    assert(table.concat(s.lines):find('"fresh_menu_edge":false',1,true))
end)
test('real keyboard menu edge still disarms and identifies the exact key',function()
    local s=scenario();s.arm();s.key('r',true)
    assert(not s.module.capture and s.flags()==0x1148)
    local found=false
    for _,line in ipairs(s.lines) do
        if line:find('"record_type":"capture"',1,true) and line:find('"reason":"menu_key_edge"',1,true) then
            assert(line:find('"input":"r"',1,true) and line:find('"raw_pressed":true',1,true));found=true
        end
    end
    assert(found)
end)
test('old record/byte counters do not disable EXP05',function()
    local s=scenario();s.arm();s.module.records=10000;s.module.bytes=4*1024*1024
    s.button(1,true);assert(#s.calls==4 and s.module.capture and not s.module.disabled)
end)
print('TOTAL '..passed..' gamepad and disarm regression checks; mocks only')
