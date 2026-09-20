-- LuaJIT fixtures exercise the real probe with fake engine devices and logger.
-- These are input-observer tests, not gameplay or action-routing tests.
local source=assert(io.open('src/c4_probe.lua','rb')):read('*a')
local total=0
local function check(ok, label) assert(ok,label); total=total+1; print('PASS '..label) end
local function pack(...) return {n=select('#',...),...} end
local function fixture(options)
    options=options or {}
    local env={}; for k,v in pairs(_G) do env[k]=v end
    env._G=env
    local lines, frame, old, calls={}, {}, {}, 0
    local sink={closed=false}
    function sink:write(line)
        if options.write_error then return nil,'mock_io_error' end
        lines[#lines+1]=line; return self
    end
    function sink:flush() if options.flush_error then return nil end; return true end
    function sink:close() self.closed=true; return true end
    local function device(ids)
        return {
            button_id=function(name) return ids[name] end,
            button_name=function(id) for name,n in pairs(ids) do if id==n then return name end end; return '' end,
            button=function(id) return (frame[id] or {}).down and 1 or 0 end,
            pressed=function(id) return (frame[id] or {}).pressed or false end,
            released=function(id) return (frame[id] or {}).released or false end,
        }
    end
    env.stingray={Keyboard=device({f6=106,f7=107}),Mouse=device({left=0,right=1}),
                  Weapon={deploy=function() error('must not execute gameplay') end}}
    if options.no_mouse then env.stingray.Mouse=nil end
    env.CowboyBingusModLoader={version=16,api=1,log_directory='/mock',
        open_log=function() if options.no_log then return nil end; return sink end}
    if options.old_loader then env.CowboyBingusModLoader.version=15 end
    env.io={open=function() return nil end}
    env.print=function() end
    env.update=function(dt,...) calls=calls+1; return 7,nil,'tail',nil end
    env.shutdown=function(...) return 9,nil,'shutdown_tail',nil end
    local original=env.update
    local function load()
        local fn=assert(loadstring(source,'@src/c4_probe.lua')); setfenv(fn,env); return fn()
    end
    local state=load()
    local function step(values, raw)
        frame={}
        values=values or {}
        for _,id in ipairs({0,1,106,107}) do
            local down=values[id] or false
            frame[id]={down=down,pressed=down and not old[id],released=not down and old[id] or false}
            old[id]=down
        end
        for id,v in pairs(raw or {}) do frame[id]=v end
        return env.update(1/(options.hz or 60),'original_argument')
    end
    local function count(fragment)
        local n=0; for _,line in ipairs(lines) do if line:find(fragment,1,true) then n=n+1 end end; return n
    end
    local function enable() step({[106]=true}); step({}) end
    return {env=env,state=state,step=step,count=count,enable=enable,lines=lines,
            sink=sink,load=load,options=options,original=original,calls=function() return calls end}
end

local f=fixture()
check(f.state.status=='ready','initialization')
local same=f.env.update
check(f.load()==f.state and f.env.update==same,'idempotent callback installation')
local v=pack(f.step())
check(v.n==4 and v[1]==7 and v[2]==nil and v[3]=='tail' and v[4]==nil,'original update return tuple including nils')
check(f.calls()==1,'original update exactly once')
f.enable()
f.step({[0]=true})
for i=1,180 do f.step({[0]=true}) end
f.step({})
check(f.count('"event":"PRESSED"')==1,'hold LMB produces one pressed observation')
check(f.count('"event":"HELD"')==1,'held state does not log every tick')
check(f.count('"event":"RELEASED"')==1,'release observed independently')
check(f.count('"executed_action":"NONE"')==#f.lines,'no action fabricated')
local held=fixture(); held.enable(); held.step({[1]=true})
for i=1,180 do held.step({[1]=true}) end
held.step({})
check(held.count('"event":"PRESSED"')==1 and held.count('"event":"RELEASED"')==1,
      'hold RMB produces one press and one release')

local sequences={
    rmb_repeat={1,1,1,1},lmb_repeat={0,0,0},rmb_lmb={1,0},
    lmb_rmb={0,1},alternating={1,0,1,0,1,0},
}
for name,sequence in pairs(sequences) do
    local x=fixture();x.enable()
    for _,key in ipairs(sequence) do x.step({[key]=true});x.step({}) end
    check(x.count('"event":"PRESSED"')==#sequence,'sequence '..name)
end
local x=fixture();x.enable();x.step({[0]=true,[1]=true});x.step({})
check(x.count('"record_type":"simultaneous_input"')==1 and x.count('"event":"PRESSED"')==2,
      'same-frame buttons retained without choosing priority')
x=fixture();x.enable()
x.step({}, {[0]={down=false,pressed=true,released=true}})
check(x.count('"event":"PRESSED_RELEASED"')==1,'subframe press and release flags retained')
x=fixture();x.step({[1]=true});x.step({[1]=true,[106]=true})
check(x.count('"event":"HELD_AT_CAPTURE_START"')==1 and x.count('"event":"PRESSED"')==0,
      'already held at capture start is not a new press')
x=fixture();x.enable();for i=1,3000 do x.step({}) end
check(x.count('"event":"PRESSED"')==0,'numeric zero is not Lua true input')
local start=x.state.records
x.step({[106]=true});x.step({[0]=true});x.step({})
check(not x.state.capture and x.state.records==start+1,'capture stop stops mouse records')
for _,name in ipairs({'no_mouse','no_log','old_loader','write_error','flush_error'}) do
    x=fixture({[name]=true})
    check(x.state.disabled and x.env.update==x.original,'fail closed '..name)
end
x=fixture();x.enable();x.options.write_error=true;x.step({[0]=true})
check(x.state.disabled and x.calls()==3,'I/O failure preserves original update')
x=fixture();x.enable();x.state.records=10000;x.step({[0]=true})
check(x.state.disabled and x.sink.closed and x.calls()==3,'log limit closes probe and preserves game callback')
x=fixture();x.enable();x.step({[107]=true});x.step({[107]=true})
check(x.count('"record_type":"manual_marker"')==1,'marker is edge triggered')
local result=pack(x.env.shutdown())
check(x.sink.closed and result.n==4 and result[1]==9 and result[3]=='shutdown_tail',
      'shutdown closes log and preserves return tuple')

-- Sustained alternating presses at 30/60/144 Hz simulated callback schedules.
-- No real framerate, game state or action outcome is claimed.
local rates={30,60,144}
for _,hz in ipairs(rates) do
    x=fixture({hz=hz});x.enable()
    for i=1,hz*10 do
        local button=(i%2==0) and 0 or 1
        x.step({[button]=true});x.step({})
    end
    check(x.count('"event":"PRESSED"')==hz*10 and not x.state.disabled
          and math.abs(x.state.elapsed_ms-(hz*20+2)*1000/hz)<0.01,
          'stress '..hz..' Hz simulated callback schedule')
end
local output=assert(io.open('evidence/mock-input-trace.jsonl','w'))
for _,line in ipairs(x.lines) do
    output:write((line:gsub('"evidence_kind":"RUNTIME_OBSERVATION"','"evidence_kind":"MOCK"')))
end
output:close()
print('RESULT '..total..' passed; MOCK input observer only; gameplay tests NOT RUN')
