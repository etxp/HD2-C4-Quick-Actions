-- Immutable code checks remain complete at readonly and mutation boundaries.
-- These synthetic fixtures neither attach to the game nor modify its process.
GuardSpans=dofile('src/GuardSpans.lua')
local resolver=dofile('src/NativeResolver.lua')
local cat=dofile('private/build/native_catalog.lua')
local symbols=dofile('private/tests/mock_symbols.lua')
local fields=dofile('private/tests/mock_fields.lua')
local function check(name,fn)fn();print('PASS '..name)end
local f=assert(io.open('private/tests/mock-native.bin','rb'));local image=f:read('*a');f:close()
local game=0x700000000000
local function u32(at)
    local a,b,c,d=image:byte(at+1,at+4);return a+b*256+c*65536+d*16777216
end
local function fixture()
    local state={reads={},changed=nil}
    local api={read=function(at,n)
        at=at-game;state.reads[#state.reads+1]={at=at,n=n}
        local value=image:sub(at+1,at+n)
        if state.changed and at<=state.changed and at+n>state.changed then
            local p=state.changed-at+1
            value=value:sub(1,p-1)..string.char((value:byte(p)+1)%256)..value:sub(p+1)
        end
        return value
    end}
    state.resolved=resolver.resolve(api,game,cat)
    state.mapping=state.resolved.verifier_for('fn_input_mapping')
    state.reads={}
    return state
end
local cases={{name='mapping routine',at=symbols.fn_input_mapping},
    {name='called input-index routine',at=symbols.fn_input_index}}
for _,node in ipairs(cat.nodes) do
    if node.name=='fn_input_mapping' or node.name=='fn_input_index' then
        for index,t in ipairs(node.tables or {}) do
            cases[#cases+1]={name=node.name..' switch table '..index,at=u32(symbols[node.name]+t.operand)}
        end
    end
end
check('readonly mapping verifies its complete catalog closure with fewer reads',function()
    local s=fixture();s.mapping();local count=#s.reads
    for _,case in ipairs(cases) do
        local covered=false
        for _,r in ipairs(s.reads) do
            if r.at<=case.at and r.at+r.n>case.at then covered=true end
        end
        assert(covered,case.name..' missing from mapping verification')
    end
    local scoped=0;for _,r in ipairs(s.reads) do scoped=scoped+r.n end
    s.reads={};s.resolved.verify()
    local complete=0;for _,r in ipairs(s.reads) do complete=complete+r.n end
    -- Page-coalesced reads make call counts incomparable; the scope must still
    -- touch far fewer pages and bytes than the complete catalog.
    assert(count<#s.reads/4 and scoped<complete/10,'readonly scope did not remove unrelated verification')
    print(string.format('MEASURE mapping verification reads=%d bytes=%d; complete reads=%d bytes=%d',
        count,scoped,#s.reads,complete))
    assert(s.mapping==s.resolved.verifier_for('fn_input_mapping'),'scope was rebuilt')
end)
for _,case in ipairs(cases) do
    check('readonly mapping rejects modified '..case.name,function()
        local s=fixture();s.changed=case.at
        local ok,why=pcall(s.mapping)
        assert(not ok and tostring(why):find('compat_live_code_changed:',1,true),tostring(why))
    end)
end
check('readonly scope excludes unrelated action code while full mutation verification retains it',function()
    local s=fixture();s.changed=symbols.fn_start;s.mapping()
    local ok,why=pcall(s.resolved.verify)
    assert(not ok and tostring(why):find('compat_live_code_changed:fn_start',1,true),tostring(why))
end)
check('unclosed catalog call graph falls back to complete verification',function()
    local s=fixture()
    -- input_inhibit has an unnamed external hash-map insertion call.
    local verify=s.resolved.verifier_for('fn_input_inhibit')
    assert(verify==s.resolved.verify)
    s.changed=symbols.fn_start;assert(not pcall(verify))
    assert(not pcall(s.resolved.verifier_for,'missing_native_symbol'))
end)

-- Exercise real assembled AimInputState and the native mock call boundary.
local ffi=require('ffi')
local scenario=dofile('tests/gamepad_entry_fixture.lua')
local function runtime()
    _G.ModBindingsMenu={api=1,version=2,ready=function()return true end,
        register_binding=function()return true end,is_down=function()return false end}
    local s=scenario{entry='private/build/c4_quick_actions.off.lua',window=true,native_ui=true,
        aim_profile=true,before_load=function(state,k)
            local rpm=k.ReadProcessMemory
            k.ReadProcessMemory=function(process,address,out,n,count)
                local ok=rpm(process,address,out,n,count)
                local at=tonumber(ffi.cast('uintptr_t',address))-state.game
                if ok~=0 and state.changed_code and at<=state.changed_code and at+n>state.changed_code then
                    local p=state.changed_code-at
                    out[p]=(tonumber(out[p])+1)%256
                end
                return ok
            end
        end}
    for _=1,8 do s.tick()end
    assert(not s.module.disabled,s.module.status)
    assert(s.mask_mode()==1 and s.fire_mask_mode()==1)
    s.mapping_calls=0
    local mapping=s.native.input_mapping
    s.native.input_mapping=function(...)
        s.mapping_calls=s.mapping_calls+1;return mapping(...)
    end
    return s
end
for _,case in ipairs(cases) do
    check('assembled Aim refuses native mapping call after modified '..case.name,function()
        local s=runtime();s.changed_code=case.at;s.tick()
        assert(s.mapping_calls==0,'unverified native mapping was called')
        assert(s.unblock_calls==0 and s.fire_unblock_calls==0,'mutation after failed immutable verification')
        s.changed_code=nil;assert(_G.shutdown()=='shutdown-original')
        assert(s.mask_mode()==0 and s.fire_mask_mode()==0)
    end)
end
check('assembled idle mapping does not scan unrelated code; restoration still verifies it',function()
    local s=runtime();s.changed_code=symbols.fn_start;s.tick()
    assert(s.mapping_calls==2,'readonly mapping was blocked by unrelated action code')
    assert(s.inhibit_calls==1 and s.fire_inhibit_calls==1,'idle reacquired input masks')
    s.ui(11);s.tick()
    assert(s.unblock_calls==0 and s.fire_unblock_calls==0,'restoration bypassed full verification')
    s.changed_code=nil;assert(_G.shutdown()=='shutdown-original')
    assert(s.mask_mode()==0 and s.fire_mask_mode()==0)
end)

-- Isolate the constructor's old-backend fallback and the event/call race.
local gf=assert(io.open('src/AimInputGate.lua','rb'));local source=gf:read('*a');gf:close()
local function gate_fixture(fire,legacy)
    local s={mode=0,full=0,scoped=0,mapping=0,inhibit=0,unblock=0,blocked=false}
    local cap={identity='selected-c4',same=function()return true end}
    local function full()s.full=s.full+1;assert(not s.blocked,'fixture_code_changed')end
    local native={}
    local backend={input=native,verify=full,snapshot=function()return {},nil,cap end}
    if not legacy then
        backend.compatibility={verifier_for=function(name)
            assert(name=='fn_input_mapping')
            return function()s.scoped=s.scoped+1 end
        end}
    end
    function native.input_inhibit()s.inhibit=s.inhibit+1;s.mode=1 end
    function native.input_unblock()s.unblock=s.unblock+1;s.mode=0 end
    local state={read=function(_,_,_,codes,_,spec,verify)
        if codes and not spec.fire then verify();s.mapping=s.mapping+1 end
        return {owner=123456,count=1,mask={mode=s.mode,bytes=s.mode==1 and 'owned' or 'released'},
            held=false,same=function()return true end}
    end,policy=function()return true,'throw_overlap'end}
    -- Readback contract used after the inhibit call.
    local original=state.read
    state.read=function(...)
        local row=original(...)
        row.mask.bytes=(row.mask.mode==1 and 'owned' or 'released')..string.rep(' ',11)..string.rep('\0',8)
        return row
    end
    local module=assert(loadstring('local D,AimInputState=...\n'..source))(fields,state)
    s.gate=module.new({},game,{},backend,function()return {}end,function(_,row)
        if s.mutate_on_acquire and (row.aim_gate_status=='acquire' or row.fire_input_status=='acquire') then
            s.blocked=true
        end
        return true
    end,fire and {action=fields.input_fire_action,code=fields.input_fire_code,index=9,tag='fire_input',fire=true} or nil)
    return s
end
for _,fire in ipairs({false,true}) do
    check((fire and 'Fire' or 'Aim')..' owns input mask without full catalog reads on idle',function()
        local s=gate_fixture(fire);s.gate.sync(true,0)
        assert(s.inhibit==1 and s.full==1)
        s.gate.sync(true,1)
        assert(s.inhibit==1 and s.full==1)
        assert(s.scoped==(fire and 0 or 2))
        assert(s.gate.stop());assert(s.unblock==1 and s.full==2)
    end)
    check((fire and 'Fire' or 'Aim')..' rechecks full immutable code after acquire event',function()
        local s=gate_fixture(fire);s.mutate_on_acquire=true;s.gate.sync(true,0)
        assert(s.inhibit==0 and s.full==1,'input inhibition bypassed mutation verification')
    end)
end
check('Aim backend without scoped API retains the full readonly verification fallback',function()
    local s=gate_fixture(false,true);s.gate.sync(true,0)
    assert(s.inhibit==1 and s.full==2)
    s.gate.sync(true,1);assert(s.full==3 and s.inhibit==1)
end)
