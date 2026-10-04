-- Attribution only: wrappers intentionally add overhead. Counts, not timings.
local entry=assert(arg[1]);local catalog=assert(arg[2])
local frames=tonumber(arg[3]) or 120
_G.C4FixturePages=arg[4]=='pages'
local scenario=dofile('tests/gamepad_entry_fixture.lua')
_G.ModBindingsMenu={api=1,version=2,ready=function()return true end,
    register_binding=function()return true end,is_down=function()return false end}
local s=scenario{entry=entry,window=true,native_ui=true,aim_profile=true,before_load=function()
    package.preload['mods/etxp/c4_quick_actions_catalog']=function()return dofile(catalog)end
end}
dofile('tests/reload_fixture.lua')(s)
for _=1,30 do s.tick()end
local p=assert(_G.C4ReadProfile)
for _,case in ipairs({'c4_idle','other_weapon','menu'})do
    if case=='other_weapon' then s.u32(s.state+0x1c,1)
    elseif case=='menu' then s.u32(s.state+0x1c,3);s.ui(11)end
    for _=1,10 do s.tick()end
    p.counts={};p.enabled=true
    for _=1,frames do s.tick()end
    p.enabled=false
    assert(not s.module.disabled,s.module.status)
    print('SCENARIO '..case)
    local keys={};for k in pairs(p.counts)do keys[#keys+1]=k end;table.sort(keys)
    for _,key in ipairs(keys)do
        local v=p.counts[key]
        print(string.format('READS %.3f BYTES %.3f %s',v[1]/frames,v[2]/frames,key))
    end
end
assert(_G.shutdown()=='shutdown-original')
