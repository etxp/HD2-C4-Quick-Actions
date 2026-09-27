-- Full assembled addon: mocked Windows, native functions, and engine input.
-- This validates routing and ABI arguments, not execution of Windows game code.
local ffi=require('ffi')
local fixture=dofile('tests/action_fixture.lua')
local signatures,expected_hash={},nil
do
    local f=assert(io.open('evidence/action-layout.json','rb'));local text=f:read('*a');f:close()
    expected_hash=assert(text:match('"module_sha256"%s*:%s*"([0-9a-f]+)"'))
    for rva,h in text:gmatch('"rva"%s*:%s*(%d+),%s*"hex"%s*:%s*"([0-9a-f]+)"') do
        signatures[tonumber(rva)]=h:gsub('..',function(v) return string.char(tonumber(v,16)) end)
    end
end
local function scenario(options)
    options=options or {}
    local s=fixture('rounds');s.lines={};s.keys={};s.mouse={};s.updates=0;s.focused=true
    local k,b,u={},{},{}
    function k.GetModuleHandleA() return ffi.cast('void *',s.game) end
    function k.GetModuleFileNameW() return 1 end
    function k.GetCurrentProcess() return ffi.cast('void *',-1) end
    function k.GetTickCount64() return 1000 end
    function k.CreateFileW() return ffi.cast('void *',1) end
    function k.ReadFile(_,_,_,count) count[0]=0;return 1 end
    function k.CloseHandle() return 1 end
    function k.GetCurrentProcessId() return 42 end
    function u.GetForegroundWindow() return ffi.cast('void *',1) end
    function u.GetWindowThreadProcessId(_,pid) pid[0]=s.focused and 42 or 123;return 1 end
    function k.ReadProcessMemory(_,address,out,n,count)
        if s.fail_reads then return 0 end
        local at=tonumber(ffi.cast('uintptr_t',address))
        local value=signatures[at-s.game]
        if value then
            if options.bad_code then value=string.rep('\0',#value) end
        else value=s.api.read(at,n) end
        if not value or #value~=n then return 0 end
        ffi.copy(out,value,n);count[0]=n;return 1
    end
    function b.BCryptOpenAlgorithmProvider(out) out[0]=ffi.cast('void *',1);return 0 end
    function b.BCryptCreateHash(_,out) out[0]=ffi.cast('void *',2);return 0 end
    function b.BCryptHashData() return 0 end
    function b.BCryptFinishHash(_,out)
        local digest=options.bad_hash and string.rep('0',64) or expected_hash
        ffi.copy(out,digest:gsub('..',function(v) return string.char(tonumber(v,16)) end),32)
        return 0
    end
    function b.BCryptDestroyHash() return 0 end
    function b.BCryptCloseAlgorithmProvider() return 0 end
    local functions={[0x7c21a0]='start',[0x73ca00]='consume',[0x73bf20]='count',[0x74b220]='after'}
    s.bound=0
    package.loaded.ffi=setmetatable({os='Windows',load=function(name)
        return assert(({kernel32=k,bcrypt=b,user32=u})[name])
    end,cast=function(kind,value)
        if type(kind)=='string' and kind:find('(*)',1,true) then
            local name=assert(functions[value-s.game],'unreviewed native call')
            s.bound=s.bound+1
            return function(manager,...)
                assert(not s.log_failure,'native action called after logging failure')
                return s.native[name](tonumber(ffi.cast('uintptr_t',manager)),...)
            end
        end
        return ffi.cast(kind,value)
    end},{__index=ffi})
    local ids={f6=6,f7=7,f8=8,f9=9,esc=10,enter=11,tab=12,r=13,m=14}
    local function device(state,bindings)
        return {button_id=function(name) return assert(bindings[name],name) end,
            button=function(n) return state[n] and state[n].down or false end,
            pressed=function(n) return state[n] and state[n].pressed or false end,
            released=function(n) return state[n] and state[n].released or false end}
    end
    _G.HD2C4BoundaryProbe=nil
    _G.stingray={Mouse=device(s.mouse,{left=0,right=1}),Keyboard=device(s.keys,ids)}
    _G.CowboyBingusModLoader={api=1,version=16,log_directory='/nonexistent-c4-action-fixture',
        open_log=function() return {write=function(_,line)
            if s.log_failure then return nil end
            s.lines[#s.lines+1]=line;return true
        end,flush=function() return not s.flush_failure end,close=function() s.closed=true end} end}
    _G.update=function(_,extra) s.updates=s.updates+1;return 'original',nil,extra end
    _G.shutdown=function() return 'shutdown-original' end
    s.module=assert(loadfile('src/c4_action_prototype.lua'))()
    function s.tick(dt)
        local a,b,c=_G.update(dt or 1/60,42)
        assert(a=='original' and b==nil and c==42,'lost original callback return tuple')
    end
    function s.press(key,dt)
        s.keys[ids[key]]={down=true,pressed=true};s.tick(dt)
    end
    function s.release(key,dt)
        s.keys[ids[key]]={down=false,released=true};s.tick(dt)
    end
    function s.arm(dt)
        s.tick(dt);s.press('f6',dt);s.release('f6',dt);assert(s.module.capture)
    end
    return s
end
local passed=0
local function test(name,f)
    local ok,err=pcall(f);package.loaded.ffi=ffi
    assert(ok,name..': '..tostring(err));passed=passed+1;print('PASS '..name)
end
for _,hz in ipairs({30,60,144}) do
    test('assembled held F8 produces one action at '..hz..' Hz, F9 is independent',function()
        local s=scenario();assert(s.module.status=='ready' and s.bound==4)
        s.arm(1/hz);s.press('f8',1/hz)
        for i=1,hz*2 do if i==math.floor(hz/2) then s.complete() end;s.tick(1/hz) end
        assert(#s.calls==4,'held key repeated')
        local pressed=false
        for _,line in ipairs(s.lines) do
            if line:find('"input":"F8"',1,true) and line:find('"event":"PRESSED"',1,true) then pressed=true end
        end
        assert(pressed,'F8 input evidence missing')
        s.release('f8',1/hz);s.press('f9',1/hz);assert(#s.calls==5 and s.calls[5][2]==520)
        s.release('f9',1/hz);s.complete()
        for _=1,10 do s.tick(1/hz) end
        assert(table.concat(s.lines):find('NATIVE_LIFECYCLE_ENDED',1,true))
        assert(_G.shutdown()=='shutdown-original' and s.closed)
    end)
end
test('F8 held before arming never invokes a native action',function()
    local s=scenario();s.press('f8');s.arm();for _=1,30 do s.tick() end
    assert(#s.calls==0);s.release('f8');s.press('f8');assert(#s.calls==4)
end)
test('opening menu, mode menu or losing focus disarms and drops pending',function()
    for _,key in ipairs({'esc','enter','tab','r','m','focus'}) do
        local s=scenario();s.arm();s.press('f8');s.release('f8');s.press('f9');s.release('f9')
        if key=='focus' then s.focused=false;s.tick() else s.press(key) end
        assert(not s.module.capture);s.complete();for _=1,10 do s.tick() end
        assert(#s.calls==4)
    end
end)
test('original mouse input cannot simultaneously dispatch a test action',function()
    local s=scenario();s.arm();s.mouse[0]={down=true,pressed=true};s.press('f8')
    assert(#s.calls==0)
end)
test('non-C4 equipment and failed snapshots never invoke native actions',function()
    local s=scenario();s.u32(s.state+0x1c,1);s.arm();s.press('f8');assert(#s.calls==0)
    s=scenario();s.arm();s.fail_reads=true;s.press('f8');assert(#s.calls==0)
    assert(not s.module.disabled and table.concat(s.lines):find('snapshot_unavailable',1,true))
end)
test('assembled rejection preserves exact diagnostic fields in the actual JSON log',function()
    local s=scenario();s.u32(s.driver_state,0x88);s.arm();s.press('f8')
    assert(#s.calls==0 and not s.module.disabled)
    local found=false
    for _,line in ipairs(s.lines) do
        if line:find('"record_type":"action_rejected"',1,true) then
            assert(line:find('"weapon_driver_flags":"00000088"',1,true))
            assert(line:find('"current_weapon":"C4_DETONATOR"',1,true))
            assert(line:find('"reason":"unsupported_c4_ammo_path"',1,true))
            assert(line:find('"action_read_stage":"weapon_driver"',1,true))
            found=true
        end
    end
    assert(found,'no diagnostic rejection record')
end)
test('assembled queued F8 waits for native refill without extra presses or repeated execution',function()
    local s=scenario();s.u32(s.rounds_state+4,0);s.arm()
    s.press('f8');s.release('f8');s.press('f8');s.release('f8')
    s.complete();for _=1,12 do s.tick() end
    assert(#s.calls==4 and table.concat(s.lines):find('"record_type":"pending_waiting"',1,true))
    s.u32(s.rounds_state+0x10,55);s.put(s.rounds_runtime+0x10,'\0')
    for _=1,12 do s.tick() end
    assert(#s.calls==8)
    s.complete();for _=1,12 do s.tick() end
    assert(#s.calls==8 and not s.module.disabled)
end)
test('startup hash or code mismatch binds no native pointers',function()
    for _,options in ipairs({{bad_hash=true},{bad_code=true}}) do
        local s=scenario(options);assert(s.module.disabled and s.bound==0)
        s.tick();assert(s.updates==1 and #s.calls==0 and s.closed)
    end
end)
test('action log write, pre-call flush and bounded log limit fail closed',function()
    for _,kind in ipairs({'write','flush','limit'}) do
        local s=scenario();s.arm()
        if kind=='write' then s.log_failure=true
        elseif kind=='flush' then s.flush_failure=true
        else s.module.records=9999 end
        s.press('f8');assert(s.module.disabled and #s.calls==0 and s.closed)
    end
end)
print('TOTAL '..passed..' assembled EXP03 checks; mock Windows/native APIs only')
