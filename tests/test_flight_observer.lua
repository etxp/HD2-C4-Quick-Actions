local M=dofile('src/FlightObserver.lua')
local function check(name,fn)fn();print('PASS '..name)end
local function fixture()
    local s={world=1,charges={11},positions={[11]={0,0,0},[7]={0,0,1}},logs={}}
    local sr={Application={main_world=function()return s.world end},
        World={units_by_resource=function(_,resource)
            return resource:find('c4_charge',1,true) and s.charges or {7}
        end},Vector3={x=function(v)return v.coordinates[1]end,
            y=function(v)return v.coordinates[2]end,z=function(v)return v.coordinates[3]end},
        Unit={alive=function(u)return s.positions[u]~=nil end,
            world_position=function(u)return {coordinates=assert(s.positions[u])}end,
            has_node=function()return true end,node=function()return 3 end,
            has_animation_state_machine=function()return true end,
            animation_get_state=function()return 0,1,2 end}}
    s.engine=sr
    s.observer=M.new(sr,function(kind,row)s.logs[#s.logs+1]={kind=kind,row=row};return true end)
    function s.sample(t)s.observer.sample(t);return s.logs[#s.logs].row end
    return s
end
check('flight measurement excludes pre-existing charges and measures new motion',function()
    local s=fixture();s.observer.begin(0,1);s.positions[12]={1,0,0};s.charges={11,12}
    local a=s.sample(100);assert(#a.flight_units==1 and not a.flight_units[1].sampled_velocity)
    s.positions[12]={2,0,0};local b=s.sample(200)
    assert(b.flight_units[1].sampled_velocity[1]==10 and b.flight_hand_position[3]==1)
    assert(b.flight_units[1].sample_interval_ms==100)
end)
check('flight evidence never attributes a candidate to the local player',function()
    local s=fixture();s.observer.begin(0,2)
    assert(s.logs[1].row.flight_candidate_ownership=='UNCONFIRMED')
    s.charges={12,13};s.positions[12]={0,0,0};s.positions[13]={1,1,1}
    assert(#s.sample(10).flight_units==2)
end)
check('world changes discard flight capture before touching old unit handles',function()
    local s=fixture();s.observer.begin(0,1);s.world=2;s.sample(10)
    assert(s.observer.capture==nil and s.logs[#s.logs].kind=='flight_end')
end)
check('flight observer is bounded and ignores zero-time samples',function()
    local s=fixture();s.observer.begin(0,1);s.sample(0);assert(#s.logs==1)
    s.sample(1601);assert(s.observer.capture==nil)
end)
check('missing engine diagnostics do not raise into gameplay',function()
    local observer=M.new({},function()return true end)
    observer.begin(0,1);observer.sample(10);assert(observer.capture==nil)
end)
check('diagnostic logging errors do not raise into gameplay',function()
    local observer=M.new({},function()error('log unavailable')end)
    observer.begin(0,1);observer.sample(10);observer.stop()
end)
check('next throw and shutdown end the prior flight capture',function()
    local s=fixture();s.observer.begin(0,1);s.observer.begin(1,2)
    assert(s.logs[2].row.flight_reason=='next_throw' and s.observer.capture.id==2)
    s.observer.stop();assert(s.observer.capture==nil)
end)
check('invalid positions end diagnostics without affecting action routing',function()
    local s=fixture();s.observer.begin(0,1);s.positions[11]={0/0,0,0};s.sample(10)
    assert(s.observer.capture==nil)
end)

check('actual x/y/z-only API handles baseline and newly spawned C4',function()
    local s=fixture();assert(s.engine.Vector3.elements==nil)
    s.observer.begin(0,1);assert(s.observer.capture)
    s.charges={11,12};s.positions[12]={1,2,3}
    local row=s.sample(16)
    assert(row.flight_units[1].position[2]==2 and row.flight_rig_status=='single_avatar')
end)
check('missing vector API is detected before an empty-scene capture starts',function()
    local s=fixture();s.charges={};s.engine.Vector3.z=nil;s.observer.begin(0,1)
    assert(not s.observer.capture and s.logs[1].kind=='flight_unavailable')
    assert(s.logs[1].row.reason:find('vector_accessors_unavailable',1,true))
end)
