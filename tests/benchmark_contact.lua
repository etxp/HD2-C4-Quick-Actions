-- Synthetic registry/physics activity. No real engine or collision scheduling;
-- the physics stream copy/decode is NOT timed by this fixture. Compare the
-- same script/fixture against the unchanged public 1.11 reader/controller.
local fixture=dofile('tests/contact_fixture.lua')
local baseline=arg[1]=='baseline'
local baseline_path=arg[2] or '../../releases/1.11'
local function loadmodule(path,D)
 local f=assert(io.open(path));local text=f:read('*a');f:close()
 return assert(loadstring('return function(D) '..text..' end'))()(D)
end
for _,case in ipairs({
 {name='manual_20',mode='MANUAL',active=20,existing=0},
 {name='contact_1',mode='CONTACT',active=1,existing=0},
 {name='contact_1_manual_64',mode='CONTACT',active=1,existing=64},
 {name='contact_20',mode='CONTACT',active=20,existing=0},
 {name='contact_128',mode='CONTACT',active=128,existing=0},
 {name='contact_1_unrelated_events_128',mode='CONTACT',active=1,existing=0,events=128}
})do
 local s=fixture()
 if baseline then
    local reader=loadmodule(baseline_path..'/src/ContactReader.lua',s.D)
    s.backend.selected=function(prepare_only)local _,_,cap=reader.selected(s.api,s.game,s.base,s.symbols,prepare_only);return cap end
    s.backend.tracked=function(lease,events,wanted)return reader.tracked(s.api,s.game,s.base,s.symbols,lease,events,wanted)end
    s.controller=dofile(baseline_path..'/src/ContactController.lua').new(s.backend,s.emit)
 end
 for i=1,case.existing do s.add(i)end
 for i=1,case.active do s.throw(i*100,case.mode);s.add(case.existing+i);s.controller.step(i*100+50)end
 for i=1,case.events or 0 do s.events.contacts[#s.events.contacts+1]=s.collide(0x600000+i)end
 local old=s.api.read;local reads,bytes,events=0,0,0
 s.api.read=function(at,n)reads=reads+1;bytes=bytes+n;return old(at,n)end
 s.backend.events=function()events=events+1;return s.events end
 collectgarbage('collect');local start=os.clock();local kb=collectgarbage('count');collectgarbage('stop')
 for i=1,120 do
    local now=case.active*100+50+i*16
    s.controller.step(now);s.controller.step(now) -- before and after the engine
 end
 local elapsed=os.clock()-start;local allocation=collectgarbage('count')-kb;collectgarbage('restart')
 assert(not s.controller.disabled)
 print(string.format('{"baseline":%s,"case":"%s","frames":120,"phases":240,"physics_snapshots":%d,"read_calls_per_frame":%.3f,"read_bytes_per_frame":%.3f,"mock_ms_per_frame":%.6f,"allocation_KiB_per_frame":%.3f}',tostring(baseline),case.name,events,reads/120,bytes/120,elapsed*1000/120,allocation/120))
end
