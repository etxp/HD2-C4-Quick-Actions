-- Executes the assembled addon with synthetic Windows APIs and engine devices.
local real_ffi=require('ffi')
local expected_hash
local signatures={}
do
    local f=assert(io.open('evidence/context-layout.json','rb'));local text=f:read('*a');f:close()
    expected_hash=assert(text:match('"module_sha256"%s*:%s*"([0-9a-f]+)"'))
    for rva,h in text:gmatch('"rva"%s*:%s*(%d+),%s*"hex"%s*:%s*"([0-9a-f]+)"') do
        signatures[tonumber(rva)]=h:gsub('..',function(v) return string.char(tonumber(v,16)) end)
    end
end
assert(next(signatures),'missing fixtures')
local function scenario(hash_ok,code_ok)
    local s={lines={},updates=0,keys={},mouse={},reads=0,closed=0,hash_closed=0}
    local game,mode=0x10000000,0x32000000
    local k={}
    function k.GetModuleHandleA() return real_ffi.cast('void *',game) end
    function k.GetModuleFileNameW() return 1 end
    function k.GetCurrentProcess() return real_ffi.cast('void *',-1) end
    function k.GetTickCount64() return 1000 end
    function k.CreateFileW() return real_ffi.cast('void *',1) end
    function k.ReadFile(_,_,_,count) count[0]=0;return 1 end
    function k.CloseHandle() s.closed=s.closed+1;return 1 end
    function k.ReadProcessMemory(_,address,out,n,count)
        s.reads=s.reads+1
        if s.fail_reads then return 0 end
        local at=tonumber(real_ffi.cast('uintptr_t',address));local value
        if signatures[at-game] then
            value=code_ok and signatures[at-game] or string.rep('\0',n)
        elseif at==game+0x276c3d0 then
            value=real_ffi.string(real_ffi.new('uint64_t[1]',mode),8)
        elseif at==mode then value=string.rep('\0',0x44) end
        if not value or #value~=n then return 0 end
        real_ffi.copy(out,value,n);count[0]=n;return 1
    end
    local b={}
    function b.BCryptOpenAlgorithmProvider(out) out[0]=real_ffi.cast('void *',1);return 0 end
    function b.BCryptCreateHash(_,out) out[0]=real_ffi.cast('void *',2);return 0 end
    function b.BCryptHashData() return 0 end
    function b.BCryptFinishHash(_,out)
        local digest=hash_ok and expected_hash or string.rep('0',64)
        digest=digest:gsub('..',function(v) return string.char(tonumber(v,16)) end)
        real_ffi.copy(out,digest,32);return 0
    end
    function b.BCryptDestroyHash() s.hash_closed=s.hash_closed+1;return 0 end
    function b.BCryptCloseAlgorithmProvider() s.hash_closed=s.hash_closed+1;return 0 end
    package.loaded.ffi=setmetatable({os='Windows',load=function(name)
        assert(name=='kernel32' or name=='bcrypt');return name=='kernel32' and k or b
    end},{__index=real_ffi})
    local function device(state,ids)
        return {button_id=function(n) return assert(ids[n]) end,
            button=function(n) return state[n] and state[n].down or false end,
            pressed=function(n) return state[n] and state[n].pressed or false end,
            released=function(n) return state[n] and state[n].released or false end}
    end
    _G.HD2C4BoundaryProbe=nil
    _G.stingray={Mouse=device(s.mouse,{left=0,right=1}),Keyboard=device(s.keys,{f6=6,f7=7})}
    _G.CowboyBingusModLoader={api=1,version=16,log_directory='/nonexistent-c4-mock',
        open_log=function() return {write=function(_,line) s.lines[#s.lines+1]=line;return true end,
            flush=function() return true end,close=function() s.log_closed=true end} end}
    _G.update=function(_,extra) s.updates=s.updates+1;return 'original',nil,extra end
    _G.shutdown=function() return 'shutdown-result' end
    s.module=assert(loadfile('src/c4_context_probe.lua'))()
    function s.tick(dt)
        local a,b,c=_G.update(dt,42)
        assert(a=='original' and b==nil and c==42,'original update tuple changed')
    end
    return s
end
local function test(name,f) assert(pcall(f),name);print('PASS '..name) end
test('assembled addon initializes through mock Windows read and hash APIs',function()
    local s=scenario(true,true)
    assert(s.module.status=='ready');assert(s.closed==1 and s.hash_closed==2)
    assert(table.concat(s.lines):find('"record_type":"layout_verified"',1,true))
    s.keys[6]={down=true,pressed=true};s.tick(0.1)
    assert(s.module.capture and s.updates==1)
    assert(table.concat(s.lines):find('"context_status":"waiting_for_mission"',1,true))
    s.keys[6]={down=false};s.keys[7]={down=true,pressed=true};s.mouse[0]={down=true,pressed=true}
    s.tick(0.1)
    local log=table.concat(s.lines)
    assert(log:find('"record_type":"manual_marker"',1,true))
    assert(log:find('"event":"PRESSED"',1,true))
    assert(not log:find('"executed_action":"DEPLOY"',1,true))
    assert(_G.shutdown()=='shutdown-result' and s.log_closed)
end)
test('assembled runtime read failure still preserves original update and mouse observations',function()
    local s=scenario(true,true);s.fail_reads=true;s.keys[6]={down=true,pressed=true};s.tick(0.1)
    assert(s.updates==1 and not s.module.disabled)
    assert(table.concat(s.lines):find('"context_status":"snapshot_unavailable"',1,true))
end)
test('assembled module hash failure stops context setup and preserves game update',function()
    local s=scenario(false,true);assert(s.module.disabled and s.reads==0)
    s.tick(0.1);assert(s.updates==1 and s.log_closed and s.closed==1 and s.hash_closed==2)
end)
test('assembled live code mismatch stops before context reads',function()
    local s=scenario(true,false);assert(s.module.disabled and s.reads==1)
    s.tick(0.1);assert(s.updates==1 and s.log_closed)
end)
package.loaded.ffi=real_ffi
