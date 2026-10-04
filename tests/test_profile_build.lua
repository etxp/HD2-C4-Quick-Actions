-- The diagnostic build must stay behaviourally silent and name the guarded
-- bytes that retire a snapshot. Requires scripts/build_profile.py output.
_G.C4FixturePages=true;_G.C4ProfileWindow=0.02
local function check(name,fn)fn();print('PASS '..name)end
local scenario=dofile('tests/gamepad_entry_fixture.lua')
_G.ModBindingsMenu={api=1,version=2,ready=function()return true end,
    register_binding=function()return true end,is_down=function()return false end}
local s=scenario{entry='private/build/profile/c4_quick_actions.off.lua',window=true,native_ui=true,aim_profile=true}
dofile('tests/reload_fixture.lua')(s)
local step=dofile('tests/benchmark_scenario.lua')(s,'c4_volatile')
for _=1,1500 do s.tick()end
local log=assert(s.log_files['C4QuickActionsProfile.log'],'profile log was not opened')
local idle=table.concat(log.lines);log.lines={}
for _=1,1500 do step();s.tick()end
local moving=table.concat(log.lines)
assert(not s.module.disabled,s.module.status)
check('idle windows report retained snapshots and no walks',function()
    assert(idle:find('== C4 profile',1,true) and idle:find('total.before_update',1,true) and idle:find('total.after_update',1,true))
    local kept,changed,walks=idle:match('cache action: calls %d+, shared in phase %d+, guards reread %d+ %(kept (%d+), changed (%d+), unreadable %d+%), walks (%d+)')
    assert(tonumber(kept)>0)
    local last
    for a,b,c in idle:gmatch('cache action: calls %d+, shared in phase %d+, guards reread %d+ %(kept (%d+), changed (%d+), unreadable %d+%), walks (%d+)')do last={a,b,c}end
    assert(tonumber(last[1])>0 and tonumber(last[2])==0 and tonumber(last[3])==0,'idle window still walked')
    local reads;for value in idle:gmatch('reads: ([%d.]+) per update')do reads=tonumber(value)end
    assert(reads>88 and reads<96,'instrumentation changed the idle read count: '..tostring(reads))
end)
check('changing guards are named by source line and byte offset',function()
    assert(moving:find('ActionReader: local ability=read(ptr(cap.ability_manager+0x38,true)+bi*0xe0,32,true) +8 len 32',1,true),
        'ability clock change was not attributed')
    assert(moving:find('+23 len 24',1,true),'avatar flag change was not attributed')
    local reads;for value in moving:gmatch('reads: ([%d.]+) per update')do reads=tonumber(value)end
    assert(reads>120 and reads<140,'instrumentation changed the worst-case read count: '..tostring(reads))
end)
check('section table covers the per-update consumers',function()
    for _,name in ipairs({'mbm.sample','window_focus','native_ui','guard.sample','fire_flag_gate.sync','aim_gate.sync',
        'fire_input.sync','auto_reload.step','backend.routing_snapshot','backend.snapshot','input_state.read',
        'code_verify.fn_input_mapping'})do
        assert(moving:find(name,1,true),name..' missing from the report')
    end
end)
assert(_G.shutdown()=='shutdown-original')
check('configuration capture is skipped on a game build it was not derived from',function()
    assert(idle:find('capture: skipped, this game build differs from the analysed one',1,true))
    assert(not idle:find('capture: error',1,true) and not moving:find('capture: error',1,true))
end)
check('configuration capture reads membership and the WeaponData aim byte when the build matches',function()
    _G.C4ProfileAssumeBuild=true
    local R=dofile('private/tests/mock_symbols.lua')
    local c=scenario{entry='private/build/profile/c4_quick_actions.off.lua',window=true,native_ui=true,aim_profile=true}
    dofile('tests/reload_fixture.lua')(c)
    -- Synthetic managers at the analysed globals: present in the fire-route
    -- component map, absent from the others, with an override row and a template.
    local route=c.allocate();c.ptr(c.game+0x3326c20,route);c.map(route+0x20,c.allocate(),{{c.wid,4}})
    local throw=c.allocate();c.ptr(c.game+0x33264c0,throw);c.map(throw+0x30,c.allocate(),{})
    local fire=c.allocate();c.ptr(c.game+0x3326a38,fire);c.map(fire+0x278,c.allocate(),{{c.otherid,1}})
    assert(c.api.pointer(c.api.read(c.game+R.global_weapon_data,8))==c.wd)
    if R.global_weapon_data~=0x3326ce0 then c.ptr(c.game+0x3326ce0,c.wd) end
    c.map(c.wd+0x70,c.allocate(),{{c.wid,2}})
    local rows=c.allocate();c.ptr(c.wd+0xb0,rows);c.zero(rows+2*0x4d0+0x170,0x30);c.put(rows+2*0x4d0+0x182,'\1')
    local templates=0x7a000000;c.ptr(c.owner+0xf12bd8,templates);c.zero(templates,730*16)
    c.put(templates+700*16,c.weapon:sub(1,8));c.u32(templates+700*16+8,5)
    c.zero(templates+0x2da0+5*0x4d0+0x170,0x30)
    for _=1,400 do c.tick()end
    assert(not c.module.disabled,c.module.status)
    local text=table.concat(c.log_files['C4QuickActionsProfile.log'].lines)
    for _,expected in ipairs({'fire-route component manager (global 3326c20, map +20): present, index 4',
        'throwable manager (global 33264c0, map +30): absent',
        'fire-threshold manager (global 3326a38, map +278): absent',
        'fire-threshold manager second map (global 3326a38, map +2b8): absent (empty map)',
        'weapon data override (global 3326ce0, map +70): present, index 2',
        'override aim byte +0x182 = 1','shared template (index 5) aim byte +0x182 = 0'})do
        assert(text:find(expected,1,true),'capture line missing: '..expected)
    end
    assert(not text:find('capture: error',1,true))
    local captures=select(2,text:gsub('capture %d+: weapon id',''))
    assert(captures==6,'capture must stop after six reports, got '..captures)
    assert(_G.shutdown()=='shutdown-original');_G.C4ProfileAssumeBuild=nil
end)
