-- Quiet diagnostics may omit presentation data, never action data or guards.
-- All pages and native transitions below are synthetic; no game attachment.
local R=dofile('private/tests/mock_symbols.lua')
local D=dofile('private/tests/mock_fields.lua')
local base=dofile('private/tests/modules/context_reader.lua')(R,D)
local reader=dofile('private/tests/modules/action_reader.lua')(R,D)
local fixture=dofile('tests/action_fixture.lua')
local reload_setup=dofile('tests/reload_fixture.lua')
local omitted={weapon_state_12=true,weapon_state_flags=true,ability_template_hex=true,
    ability_descriptors=true,avatar_flags=true,rounds_state_hex=true,
    rounds_runtime_hex=true,rounds_config_hex=true,reload_config_hex=true}
local function check(name,fn)fn();print('PASS '..name)end
local function equal(a,b,path)
    path=path or 'value'
    assert(type(a)==type(b),path..' type changed')
    if type(a)=='function' then return end
    if type(a)~='table' then assert(a==b,path..' changed');return end
    for k,v in pairs(a)do equal(v,b[k],path..'.'..tostring(k))end
    for k in pairs(b)do assert(a[k]~=nil,path..'.'..tostring(k)..' added')end
end
local function snap(s,diagnostics)
    base.diagnostics=diagnostics
    return reader.snapshot(s.api,s.game,base)
end
local function pair(s)
    local before=s.read_calls
    local full,why,cap=snap(s,true);assert(full and not why and cap)
    local full_reads=s.read_calls-before;before=s.read_calls
    local quiet,qwhy,qcap=snap(s,false);assert(quiet and not qwhy and qcap)
    assert(s.read_calls-before==full_reads,'quiet mode must retain every read')
    for k,v in pairs(full)do
        if omitted[k] then assert(quiet[k]==nil,'quiet diagnostics retained '..k)
        elseif k=='inventory_words' then equal(v['12'],quiet[k]['12'],k)
        else equal(v,quiet[k],k)end
    end
    for k in pairs(quiet)do assert(full[k]~=nil,'quiet mode added '..k)end
    local count=0;for k in pairs(quiet.inventory_words)do
        count=count+1;assert(k=='12','only the reload backpack word remains')
    end
    assert(count==1)
    equal(cap,qcap,'capability')
    assert(cap.same() and qcap.same())
    return full,quiet,cap,qcap
end
local function reloading(path)
    local s=fixture('rounds');s.tick=function()end
    return reload_setup(s,path)
end

check('quiet rounds and resource snapshots preserve action data and read budgets',function()
    for _,path in ipairs({'rounds','resource'})do
        local full,quiet=pair(fixture(path))
        assert(full.ability_template_hex and full.ability_descriptors and full.avatar_flags)
        assert(full.weapon_state_12 and full.weapon_state_flags)
        if path=='rounds' then assert(full.rounds_config_hex and full.rounds_state_hex)end
        assert(quiet.current_weapon=='C4_DETONATOR' and quiet.action_gate=='READY')
    end
end)

check('quiet snapshots retain backpack and alternate supply resupply observations',function()
    for _,path in ipairs({'backpack','supply'})do
        local s=reloading(path)
        for _,n in ipairs({0,6,0,9})do
            s.u32(s.spare_state,n)
            local full,quiet,cap,qcap=pair(s)
            assert(full.reload_context=='verified' and full.reload_config_hex)
            assert(quiet.reload_supply_count==n and quiet.reload_spare_ammo==n)
            assert(cap.reload.ammo==n and qcap.reload.ammo==n)
            if path=='backpack' then assert(quiet.reload_backpack_entity_id==s.otherid)end
        end
    end
end)

check('raw descriptor checks reject every changed gameplay byte in both modes',function()
    local s=fixture('rounds');local at=s.templates+D.ability_capacity*16
    local original=s.api.read(at,88)
    for offset=0,79 do
        if not (offset>=16 and offset<20 or offset>=56 and offset<60)then
            s.put(at+offset,string.char((original:byte(offset+1)+1)%256))
            for _,diagnostics in ipairs({true,false})do
                local row,why,cap=snap(s,diagnostics)
                assert(row and not why and not cap)
                assert(row.action_context_error=='unsupported_c4_descriptors',tostring(offset))
            end
            s.put(at,original)
        end
    end
end)

check('cosmetic descriptor captions stay accepted and freshly guarded in both modes',function()
    local s=fixture('rounds');local at=s.templates+D.ability_capacity*16
    for _,offset in ipairs({16,17,18,19,56,57,58,59})do
        local original=s.api.read(at+offset,1)
        s.put(at+offset,string.char((original:byte()+1)%256))
        local _,_,cap,qcap=pair(s)
        s.put(at+offset,original)
        assert(not cap.same() and not qcap.same(),'caption guard removed')
    end
end)

check('omitted diagnostic sources remain guarded through action and reload use',function()
    local s=reloading('backpack')
    local sources={s.state+12,0x4b000000+12,0x4c000000+2,s.avatar_flags,
        s.rounds_state,s.rounds_runtime,s.rounds_config,s.reload_config,
        s.templates+D.ability_capacity*16,s.eaddr,s.waddr}
    for _,at in ipairs(sources)do
        local original=s.api.read(at,1)
        local _,_,cap,qcap=pair(s)
        s.put(at,string.char((original:byte()+1)%256))
        assert(not cap.same() and not qcap.same(),string.format('lost guard %x',at))
        s.put(at,original)
        assert(cap.same() and qcap.same())
    end
end)

check('quiet action admission rejects unreadable and short diagnostic source reads',function()
    for _,short in ipairs({false,true})do
        for _,target in ipairs({'descriptor','avatar','rounds'})do
            local s=fixture('rounds')
            local at=target=='descriptor' and s.templates+D.ability_capacity*16 or
                target=='avatar' and s.avatar_flags or s.rounds_state
            s.intercept=function(address,n)
                if address==at then return short and string.rep('\0',n-1) or nil,true end
            end
            for _,diagnostics in ipairs({true,false})do
                local ok,row,_,cap=pcall(snap,s,diagnostics)
                assert(not ok or row==nil or cap==nil,'partial action capability escaped')
            end
        end
    end
end)

check('quiet reload configuration failures preserve actions without permitting reload',function()
    for _,short in ipairs({false,true})do
        local s=reloading('backpack')
        s.intercept=function(at,n)
            if at==s.reload_config then return short and string.rep('\0',n-1) or nil,true end
        end
        for _,diagnostics in ipairs({true,false})do
            local row,why,cap=snap(s,diagnostics)
            assert(row and not why and cap and not cap.reload)
            assert(row.action_gate=='READY' and row.reload_context~='verified')
        end
    end
end)
