local f=assert(io.open('src/ActionController.lua'));local source=f:read('*a');f:close()
local module=assert(loadstring('return function(VehiclePrepare) '..source..' end'))()(dofile('src/VehiclePrepare.lua'))
local function setup()
 local s={manual=0,starts=0,logs={},cap={identity='c4',active=false,deploy_ready=true,same=function()return true end}}
 local backend={snapshot=function()return {context_status='ready',current_fire_mode='DEPLOY'},nil,s.cap end,
 execute=function(action) s.starts=s.starts+1;s.cap.active=true;s.cap.ability_id=action=='DEPLOY' and 521 or 520;return s.cap.ability_id end,
 airborne_manual=function(cap)assert(cap==s.cap);if s.error then error('native failure')end;if s.nocharge then return false end;s.manual=s.manual+1;return true end}
 s.controller=module.new(backend,function(k,v)s.logs[#s.logs+1]={k,v};return true end)
 function s.step(now,action,allowed)s.controller.step(true,now,{allowed=allowed~=false,deploy=action=='DEPLOY',detonate=action=='DETONATE'})end
 s.step(0);s.step(10,'DEPLOY');assert(s.controller.lock and not s.controller.fault);return s
end
local function test(name,fn)fn();print('PASS '..name)end
test('manual air detonation leaves throw and passenger hold lifecycle intact',function()
 local s=setup();s.cap.vehicle=true;s.cap.deploy_released=true;local lock=s.controller.lock
 s.step(20,'DETONATE');assert(s.manual==1 and s.starts==1 and s.controller.lock==lock)
 s.step(100);assert(s.manual==1);s.cap.active=false;s.step(200);assert(not s.controller.lock)
end)
test('manual input before release is dispatched only after projectile release',function()
 local s=setup();s.step(20,'DETONATE');assert(s.manual==0 and s.controller.pending)
 s.cap.deploy_released=true;s.step(100);assert(s.manual==1 and not s.controller.pending and s.starts==1)
 s.step(200);assert(s.manual==1)
end)
test('UI and ragdoll interruption revoke queued manual detonation',function()
 for _,kind in ipairs({'allowed','interrupt'})do local s=setup();s.step(20,'DETONATE');s.cap.deploy_released=true
 if kind=='interrupt'then s.cap.interrupt=true end;s.step(100,nil,kind~='allowed');assert(s.manual==0 and not s.controller.pending)end
end)
test('weapon identity changes cannot detonate the old throw',function()
 local s=setup();s.step(20,'DETONATE');s.cap.identity='other';s.cap.deploy_released=true;s.step(100)
 assert(s.manual==0 and not s.controller.pending and not s.controller.lock)
end)
test('no owned airborne charge retains original detonation fallback',function()
 local s=setup();s.nocharge=true;s.cap.deploy_released=true;s.step(20,'DETONATE');assert(s.manual==0 and s.controller.pending)
 s.cap.active=false;s.step(100);assert(s.starts==2 and s.controller.lock.action=='DETONATE')
end)
test('native airborne failure latches without replay',function()
 local s=setup();s.error=true;s.cap.deploy_released=true;s.step(20,'DETONATE');assert(s.controller.fault)
 s.error=false;s.step(100,'DETONATE');assert(s.manual==0)
end)
