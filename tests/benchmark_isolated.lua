-- Whole callback benchmark with a synthetic C FFI read provider.
-- This is NOT ReadProcessMemory/Wine, native game execution, or an FPS test.
local entry=assert(arg[1]);local catalog=assert(arg[2])
local frames=tonumber(arg[3]) or 1000
local memory=arg[4]=='c' and dofile('tests/bench_memory.lua')
    or arg[4]=='wine' and dofile('tests/wine_memory.lua') or nil
if arg[5]=='off' then jit.off();jit.flush() end
local scenario=dofile('tests/gamepad_entry_fixture.lua')
local function setup(s,k,image)
    package.preload['mods/etxp/c4_quick_actions_catalog']=function()return dofile(catalog)end
    if memory then memory(s,k,image)end
end
_G.ModBindingsMenu={api=1,version=2,ready=function()return true end,
    register_binding=function()return true end,is_down=function()return false end}
local s=scenario{entry=entry,window=true,native_ui=true,aim_profile=true,before_load=setup}
if arg[6]=='reload' then dofile('tests/reload_fixture.lua')(s) end
local step=dofile('tests/benchmark_scenario.lua')(s,arg[7])
if step then local tick=s.tick;s.tick=function()step();tick()end end
for _=1,200 do s.tick()end
assert(not s.module.disabled,s.module.status)
assert(s.module.status=='ready',s.module.status)
local count,bytes=0,0
-- Instrument assembled WindowsRead, not the mock helper: the same surface as
-- the live profiler. A generated benchmark entry exposes this local API only.
local api=assert(_G.C4BenchmarkApi);local read=api.read
api.read=function(at,n)count=count+1;bytes=bytes+n;return read(at,n)end
for _=1,100 do s.tick()end
count,bytes=0,0
-- Count work in a separate untimed pass, then remove the meter. Timing fewer
-- reads must not gain an artificial advantage from less counter overhead.
for _=1,frames do s.tick()end
local measured_count,measured_bytes=count,bytes
api.read=read
for _=1,300 do s.tick()end
s.lines={};s.calls={};collectgarbage('collect')
local start=os.clock()
for _=1,frames do s.tick()end
local elapsed=os.clock()-start
assert(not s.module.disabled,s.module.status)
assert(s.module.status=='ready',s.module.status)
print(string.format('RESULT {"frames":%d,"counter_frames":%d,"timing":"unmetered","memory":"%s","jit":%s,"ms_per_update":%.6f,"reads_per_update":%.3f,"bytes_per_update":%.3f}',
    frames,frames,arg[4],tostring(jit.status()),elapsed*1000/frames,measured_count/frames,measured_bytes/frames))
assert(_G.shutdown()=='shutdown-original')
