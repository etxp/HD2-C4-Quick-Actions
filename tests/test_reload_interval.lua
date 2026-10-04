-- Off build: the complete automatic-reload observation is taken every 100 ms
-- while nothing is pending and the ammunition records are unchanged; every
-- event that matters restores per-update observation in the same update.
local scenario=dofile('tests/gamepad_entry_fixture.lua')
local reload_setup=dofile('tests/reload_fixture.lua')
local function check(name,fn)fn();print('PASS '..name)end
local function fresh(variant)
    local values={deploy=false,detonate=false}
    _G.ModBindingsMenu={api=1,version=2,ready=function()return true end,
        register_binding=function()return true end,is_down=function(id)return values[id:match('%.([^%.]+)$')]end}
    local s=scenario{entry='private/build/c4_quick_actions.'..(variant or 'off')..'.lua',window=true,native_ui=true,aim_profile=true}
    s.values=values
    for _=1,8 do s.tick()end
    reload_setup(s)
    -- The weapon ability record is read only by the complete action snapshot.
    local read=s.api.read;s.complete_observations=0
    s.api.read=function(at,n)
        if at<=s.ability_state and at+n>s.ability_state then s.complete_observations=s.complete_observations+1 end
        return read(at,n)
    end
    function s.observed(ticks)
        local before=s.complete_observations
        for _=1,ticks do s.tick()end
        return s.complete_observations-before
    end
    function s.press(action)values[action]=true;s.tick();values[action]=false;s.tick()end
    for _=1,30 do s.tick()end
    assert(not s.module.disabled and s.mask_mode()==1,s.module.status)
    return s
end
check('idle with spare ammunition: complete observation every 100 ms, not every update',function()
    local s=fresh();local n=s.observed(120)
    assert(n>=18 and n<=24,'expected about 20 complete observations in 2 s, got '..n)
    local strict=fresh('off.strict');assert(strict.observed(120)==120)
    local verbose=fresh('verbose');assert(verbose.observed(120)>=120,'diagnostic build must keep per-update observation')
end)
check('a changed ammunition record is observed in the same update',function()
    for _,change in ipairs({
        function(s)s.u32(s.spare_state,5)end,              -- supply counter
        function(s)s.u32(s.rounds_state+16,0)end,          -- chamber token
        function(s)s.put(s.rounds_runtime+0x10,'\1')end})do -- chamber blocked flag
        local s=fresh();s.observed(3)
        local idle=s.observed(1);change(s)
        assert(s.observed(1)>=1,'ammunition change waited for the interval')
    end
end)
check('an empty spare count keeps per-update observation and resupply reloads at once',function()
    local s=fresh();s.u32(s.spare_state,0);s.u32(s.rounds_state+16,0)
    local n=s.observed(30);assert(n>=30 and n<=33,'empty C4 must be observed on every update, got '..n)
    s.u32(s.spare_state,4);s.tick();assert(s.reload_calls==1)
end)
check('a throw restores per-update observation until its reload opportunity ends',function()
    local s=fresh();s.observed(10)
    s.values.deploy=true;s.tick();s.values.deploy=false
    assert(#s.calls==4,'throw did not start')
    assert(s.observed(5)>=5,'pending reload intent was not observed per update')
    s.phase(11);s.tick();assert(s.reload_calls==1)
end)
check('a context that becomes unusable releases input inhibition within the interval',function()
    local function released_after(variant)
        local s=fresh(variant);s.observed(2)
        -- Not an ammunition record: the C4 ability descriptor stops matching.
        s.u32(s.templates+288,999)
        for tick=1,30 do
            s.tick()
            if s.mask_mode()==0 and s.fire_mask_mode()==0 then return tick,s end
        end
        error('input inhibition was never released')
    end
    local strict=released_after('off.strict')
    local lean,s=released_after('off')
    assert(strict==1,'per-update build should release on the next update')
    assert(lean<=7,'release took '..lean..' updates (more than 100 ms)')
    for _=1,10 do s.tick()end;assert(s.mask_mode()==0 and not s.module.disabled)
end)
check('leaving and returning to C4 starts with a complete observation',function()
    local s=fresh();s.observed(3)
    s.u32(s.state+0x1c,1);s.observed(5);s.u32(s.state+0x1c,3)
    local n=s.observed(3);assert(n>=1,'no complete observation after reselecting C4')
end)
check('actions never use a stale interval snapshot',function()
    local s=fresh();s.observed(2)
    -- Ammunition disappears between complete observations; the throw must be refused.
    s.u32(s.rounds_state+16,0);s.values.deploy=true;s.tick();s.values.deploy=false;s.tick()
    assert(#s.calls==0,'throw was authorized without a chambered charge')
    s.u32(s.rounds_state+16,55);s.put(s.rounds_runtime+0x10,'\0');s.press('deploy');assert(#s.calls==4)
end)
