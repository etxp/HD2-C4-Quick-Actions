-- Full assembled EXP04 with mock Windows and a synthetic vanilla Fire branch.
-- This cannot prove real game timing, visuals, animation or multiplayer behavior.
local ffi=require('ffi')
local bit=require('bit')
local base=dofile('src/context_reader.lua')
local fixture=dofile('tests/action_fixture.lua')
local signatures,expected_hash={},nil
do
    local f=assert(io.open('evidence/mouse-layout.json','rb'));local text=f:read('*a');f:close()
    expected_hash=assert(text:match('"module_sha256"%s*:%s*"([0-9a-f]+)"'))
    for rva,h in text:gmatch('"rva"%s*:%s*(%d+),%s*"hex"%s*:%s*"([0-9a-f]+)"') do
        signatures[tonumber(rva)]=h:gsub('..',function(v) return string.char(tonumber(v,16)) end)
    end
end
local function scenario(options)
    options=options or {}
    local s=fixture('rounds');s.u32(s.driver_state,0x1148)
    s.lines={};s.keys={};s.mouse={};s.writes={};s.updates=0;s.focused=true;s.vanilla={};s.aim_ticks=0
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
            if options.bad_code or s.bad_code then value=string.rep('\0',#value) end
        else value=s.api.read(at,n) end
        if not value or #value~=n then return 0 end
        ffi.copy(out,value,n);count[0]=n;return 1
    end
    function k.WriteProcessMemory(_,address,value,n,count)
        local at=tonumber(ffi.cast('uintptr_t',address))
        local byte=type(value)=='string' and value:sub(1,n) or ffi.string(value,n)
        assert(at==s.driver_state+1 and n==1,'unscoped memory mutation')
        assert(byte=='\1' or byte=='\17','invalid flags byte')
        s.writes[#s.writes+1]={address=at,byte=byte,n=n}
        if s.fail_writes then return 0 end
        s.put(at,byte);count[0]=1;return 1
    end
    function b.BCryptOpenAlgorithmProvider(out) out[0]=ffi.cast('void *',1);return 0 end
    function b.BCryptCreateHash(_,out) out[0]=ffi.cast('void *',2);return 0 end
    function b.BCryptHashData() return 0 end
    function b.BCryptFinishHash(_,out)
        local digest=options.bad_hash and string.rep('0',64) or expected_hash
        ffi.copy(out,digest:gsub('..',function(v) return string.char(tonumber(v,16)) end),32);return 0
    end
    function b.BCryptDestroyHash() return 0 end
    function b.BCryptCloseAlgorithmProvider() return 0 end
    local functions={[0x7c21a0]='start',[0x73ca00]='consume',[0x73bf20]='count',[0x74b220]='after'}
    s.bound=0
    package.loaded.ffi=setmetatable({os='Windows',load=function(name)
        return assert(({kernel32=k,bcrypt=b,user32=u})[name])
    end,cast=function(kind,value)
        if type(kind)=='string' and kind:find('(*)',1,true) then
            local name=assert(functions[value-s.game],'unreviewed native call');s.bound=s.bound+1
            return function(manager,...)
                assert(not s.log_failure and not s.flush_failure,'action after log failure')
                assert(base.u32(s.api.read(s.driver_state,4),0)==0x148,'action without owned Fire gate')
                return s.native[name](tonumber(ffi.cast('uintptr_t',manager)),...)
            end
        end
        return ffi.cast(kind,value)
    end},{__index=ffi})
    local ids={f6=6,f7=7,esc=10,enter=11,tab=12,r=13,m=14}
    local function device(state,bindings)
        return {button_id=function(name) return assert(bindings[name],name) end,
            button=function(n) return state[n] and state[n].down or false end,
            pressed=function(n) return state[n] and state[n].pressed or false end,
            released=function(n) return state[n] and state[n].released or false end}
    end
    _G.HD2C4BoundaryProbe=nil
    _G.stingray={Mouse=device(s.mouse,{left=0,right=1}),Keyboard=device(s.keys,ids)}
    _G.CowboyBingusModLoader={api=1,version=16,log_directory='/nonexistent-c4-mouse-fixture',
        open_log=function() return {write=function(_,line)
            if s.log_failure then return nil end
            s.lines[#s.lines+1]=line;return true
        end,flush=function() return not s.flush_failure end,close=function() s.closed=true end} end}
    _G.update=function(_,extra)
        s.updates=s.updates+1
        if s.original_error then error('fixture_original_error') end
        if s.original_hook then s.original_hook() end
        local c4=base.u32(s.api.read(s.state+0x1c,4),0)==3
        local fire=s.mouse[0] and s.mouse[0].down or false
        if s.mouse[1] and s.mouse[1].down then s.aim_ticks=s.aim_ticks+1 end
        if c4 then
            local flags=base.u32(s.api.read(s.driver_state,4),0)
            if bit.band(flags,0x1000)~=0 then
                local previous=s.api.read(s.fire_state,1)~='\0'
                if fire and not previous then
                    local mode=base.u32(s.api.read(0x4b000000+16,4),0)
                    s.vanilla[#s.vanilla+1]=mode==0 and 'DEPLOY' or 'DETONATE'
                end
                s.put(s.fire_state,fire and '\1' or '\0')
            end
        elseif fire and not s.other_fire then s.vanilla[#s.vanilla+1]='OTHER_WEAPON' end
        s.other_fire=not c4 and fire
        return 'original',nil,extra
    end
    _G.shutdown=function() return 'shutdown-original' end
    s.module=assert(loadfile('src/c4_dual_input.lua'))()
    function s.tick(dt)
        local a,b,c=_G.update(dt or 1/60,42)
        assert(a=='original' and b==nil and c==42,'lost original callback return tuple')
    end
    function s.key(key,down,dt)
        s.keys[assert(ids[key])]={down=down,pressed=down,released=not down};s.tick(dt)
    end
    function s.button(n,down,dt)
        s.mouse[n]={down=down,pressed=down,released=not down};s.tick(dt)
    end
    function s.arm(dt) s.tick(dt);s.key('f6',true,dt);s.key('f6',false,dt);assert(s.module.capture) end
    function s.finish(dt) s.complete();for _=1,10 do s.tick(dt) end end
    function s.flags() return base.u32(s.api.read(s.driver_state,4),0) end
    return s
end
local passed=0
local function test(name,f)
    local ok,err=pcall(f);package.loaded.ffi=ffi
    assert(ok,name..': '..tostring(err));passed=passed+1;print('PASS '..name)
end
for _,mode in ipairs({0,1}) do
    for _,hz in ipairs({30,60,144}) do
        test('physical mapping and held-edge dedup, mode '..mode..' at '..hz..' Hz',function()
            local s=scenario();s.u32(0x4b000000+16,mode)
            assert(s.module.status=='ready' and s.bound==4 and #s.writes==0)
            s.arm(1/hz);assert(s.flags()==0x148)
            s.button(1,true,1/hz)
            for i=1,hz*2 do if i==math.floor(hz/2) then s.complete() end;s.tick(1/hz) end
            assert(#s.calls==4 and s.calls[1][2]==521 and #s.vanilla==0)
            s.button(1,false,1/hz);s.button(0,true,1/hz)
            for i=1,hz*2 do if i==math.floor(hz/2) then s.complete() end;s.tick(1/hz) end
            assert(#s.calls==5 and s.calls[5][2]==520 and #s.vanilla==0)
            s.button(0,false,1/hz);assert(s.aim_ticks>0,'native Aim unexpectedly swallowed')
            assert(base.u32(s.api.read(0x4b000000+16,4),0)==mode)
            local trace=table.concat(s.lines)
            assert(trace:find('"input":"RMB"',1,true) and trace:find('"input":"LMB"',1,true))
            assert(trace:find('NATIVE_LIFECYCLE_ENDED',1,true) and not trace:find('"record_type":"probe_error"',1,true))
            assert(_G.shutdown()=='shutdown-original' and s.closed and s.flags()==0x1148)
        end)
    end
end
test('simultaneous physical presses invoke Detonate once and never vanilla Deploy',function()
    local s=scenario();s.arm()
    s.mouse[0]={down=true,pressed=true};s.mouse[1]={down=true,pressed=true};s.tick()
    assert(#s.calls==1 and s.calls[1][2]==520 and #s.vanilla==0)
    assert(table.concat(s.lines):find('DETONATE_PRIORITY',1,true))
end)
test('arming while held needs a released baseline and never synthesizes a request',function()
    for _,button in ipairs({0,1}) do
        local s=scenario();s.mouse[button]={down=true,pressed=true};s.arm()
        assert(#s.calls==0 and #s.writes==0)
        s.button(button,false);s.tick();s.button(button,true)
        assert(#s.calls==(button==0 and 1 or 4))
    end
end)
test('F6 disarm during left hold restores only on release without native replay',function()
    local s=scenario();s.arm();s.button(0,true);s.key('f6',true);s.key('f6',false)
    assert(not s.module.capture and s.flags()==0x148 and #s.vanilla==0)
    s.button(0,false);assert(s.flags()==0x1148 and #s.vanilla==0)
    s.button(0,true);assert(#s.vanilla==1 and s.vanilla[1]=='DEPLOY' and #s.calls==1)
end)
test('switching to another weapon restores C4 and passes normal Fire and Aim through',function()
    local s=scenario();s.arm();s.u32(s.state+0x1c,1);s.tick()
    assert(s.flags()==0x1148)
    s.button(0,true);s.button(1,true)
    assert(#s.calls==0 and s.vanilla[1]=='OTHER_WEAPON' and s.aim_ticks>0)
    s.u32(s.state+0x1c,3);s.tick();assert(#s.calls==0 and s.flags()==0x1148)
    s.button(0,false);s.button(1,false);s.tick();s.button(1,true);assert(#s.calls==4)
end)
test('inventory change inside original update restores before the wrapper returns',function()
    local s=scenario();s.arm();s.original_hook=function() s.u32(s.state+0x1c,1) end;s.tick()
    assert(s.flags()==0x1148 and #s.calls==0)
end)
test('menu keys and focus loss disarm, restore and drop queued actions',function()
    for _,key in ipairs({'esc','enter','tab','r','m','focus'}) do
        local s=scenario();s.arm();s.button(1,true);s.button(1,false);s.button(0,true);s.button(0,false)
        if key=='focus' then s.focused=false;s.tick() else s.key(key,true) end
        s.finish();assert(not s.module.capture and s.flags()==0x1148 and #s.calls==4)
    end
end)
test('native refill still gates Deploy while Detonate works with no ready ammo',function()
    local s=scenario();s.arm();s.put(s.rounds_runtime+0x10,'\1');s.u32(s.rounds_state+4,0)
    s.button(1,true);s.button(1,false);assert(#s.calls==0)
    s.button(0,true);s.button(0,false);assert(#s.calls==1 and s.calls[1][2]==520)
    s.finish();s.put(s.rounds_runtime+0x10,'\0');s.u32(s.rounds_state+0x10,55)
    s.button(1,true);assert(#s.calls==5)
end)
test('one pending Deploy retains the original refill behavior without repeat expansion',function()
    local s=scenario();s.u32(s.rounds_state+4,0);s.arm()
    s.button(1,true);s.button(1,false);s.button(1,true);s.button(1,false)
    s.finish();assert(#s.calls==4 and table.concat(s.lines):find('"record_type":"pending_waiting"',1,true))
    s.u32(s.rounds_state+0x10,55);s.put(s.rounds_runtime+0x10,'\0')
    for _=1,12 do s.tick() end
    assert(#s.calls==8);s.finish();assert(#s.calls==8)
end)
test('startup hash or code mismatch performs no memory writes or native binds',function()
    for _,options in ipairs({{bad_hash=true},{bad_code=true}}) do
        local s=scenario(options);assert(s.module.disabled and s.bound==0 and #s.writes==0)
        s.tick();assert(s.updates==1 and #s.calls==0 and s.closed)
    end
end)
test('write failure denies mouse actions; transient restoration failures retry',function()
    local s=scenario();s.fail_writes=true;s.tick();s.key('f6',true)
    assert(s.module.disabled and #s.calls==0 and s.flags()==0x1148)
    s=scenario();s.arm();s.fail_writes=true;s.key('esc',true)
    assert(s.module.disabled and s.flags()==0x148)
    s.fail_writes=false;s.tick();assert(s.flags()==0x1148 and #s.calls==0)
end)
test('read failure blocks actions and restores on recovery',function()
    local s=scenario();s.arm();s.fail_reads=true;s.button(0,true)
    assert(s.module.disabled and #s.calls==0 and s.flags()==0x148)
    s.fail_reads=false;s.button(0,false);assert(s.flags()==0x1148)
end)
test('log write, flush or size-limit failure restores the gate and denies direct actions',function()
    for _,kind in ipairs({'write','flush','limit'}) do
        local s=scenario();s.arm()
        if kind=='write' then s.log_failure=true elseif kind=='flush' then s.flush_failure=true
        else s.module.records=9999 end
        s.button(1,true);assert(s.module.disabled and #s.calls==0 and s.closed and s.flags()==0x1148)
    end
end)
test('an original update exception is propagated with C4 flags restored',function()
    local s=scenario();s.arm();s.original_error=true
    local ok,why=pcall(s.tick);assert(not ok and tostring(why):find('fixture_original_error',1,true))
    assert(s.flags()==0x1148 and not s.module.capture)
end)
test('guarded native code changing after startup prevents the direct action',function()
    local s=scenario();s.arm();s.bad_code=true;s.button(1,true)
    assert(#s.calls==0 and table.concat(s.lines):find('action_code_changed_',1,true))
    s.button(1,false);s.key('f6',true);assert(s.flags()==0x1148)
end)
test('code changes before enabling prevent acquiring the Fire gate',function()
    local s=scenario();s.bad_code=true;s.key('f6',true)
    assert(s.module.disabled and #s.writes==0 and #s.calls==0 and s.flags()==0x1148)
end)
print('TOTAL '..passed..' assembled EXP04 checks; mock Windows/native APIs only')
