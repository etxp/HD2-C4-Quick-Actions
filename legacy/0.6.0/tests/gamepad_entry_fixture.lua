-- Full assembled input addon with mock Windows and a synthetic vanilla Fire branch.
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
    local s=fixture('rounds');s.u32(s.driver_state,0x1148);s.pad_devices={};s.log_files={}
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
    if options.window then
        s.engine_focus=true;s.cursor_visible=false;s.mouse_focus=true
        _G.stingray.Window={has_focus=function()
            if s.window_error then error('fixture_window_error') end
            return s.engine_focus
        end,show_cursor=function() return s.cursor_visible end,
        mouse_focus=function() return s.mouse_focus end}
    end
    function s.connect(slot,profile)
        local p={active=true,values={},presses={},releases={}}
        local names=profile=='ps' and {[20]='l2',[21]='r2',[3]='options',[4]='share'}
            or {[20]='left_trigger',[21]='right_trigger',[3]='start',[4]='back'}
        local ids={};for n,name in pairs(names) do ids[name]=n end
        if profile=='unsupported' then names[20]='unknown_left';names[21]='unknown_right';ids={} end
        p.api={active=function() return p.active end,
            button_id=function(name) return ids[name] end,button_name=function(n) return names[n] or '' end,
            button=function(n) return p.values[n] or 0 end,
            pressed=function(n) return p.presses[n] or false end,released=function(n) return p.releases[n] or false end,
            num_buttons=function() return 22 end,name=function() return slot..'-fixture' end,
            type=function() return profile=='ps' and 'ps_controller' or 'xbox_controller' end}
        s.pad_devices[slot]=p;_G.stingray[slot]=p.api;return p
    end
    if options.pad_profile then s.connect(options.pad_slot or 'Pad1',options.pad_profile) end
    _G.CowboyBingusModLoader={api=1,version=16,log_directory='/nonexistent-c4-mouse-fixture',
        open_log=function(name) local log={lines={}};s.log_files[name]=log;return {write=function(_,line)
            if s.log_failure then return nil end
            if options.fail_log_record and line:find('"record_type":"'..options.fail_log_record..'"',1,true) then return nil end
            s.lines[#s.lines+1]=line;log.lines[#log.lines+1]=line;return true
        end,flush=function() return not s.flush_failure end,close=function() s.closed=true;log.closed=true;return true end} end}
    _G.update=function(_,extra)
        s.updates=s.updates+1
        if s.original_error then error('fixture_original_error') end
        if s.original_hook then s.original_hook() end
        local c4=base.u32(s.api.read(s.state+0x1c,4),0)==3
        local fire=s.mouse[0] and s.mouse[0].down or false
        local aim=s.mouse[1] and s.mouse[1].down or false
        for _,slot in ipairs({'Pad1','Pad2','Pad3','Pad4','PS4Pad1','PS4Pad2','PS4Pad3','PS4Pad4'}) do
            local p=s.pad_devices[slot]
            if p and p.active then
                fire=fire or (p.values[21] or 0)>0.12
                aim=aim or (p.values[20] or 0)>0.12
                break
            end
        end
        if aim then s.aim_ticks=s.aim_ticks+1 end
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
    s.module=assert(loadfile(options.entry or 'src/c4_dual_input_gamepad.lua'))()
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
    function s.trigger(side,v,dt,slot)
        local p=assert(s.pad_devices[slot or options.pad_slot or 'Pad1'])
        p.values[side=='left' and 20 or 21]=v;s.tick(dt)
    end
    return s
end
return scenario,ffi
