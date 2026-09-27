-- Read-only flight evidence. New units are candidates, never assumed owned by
-- the local player. Position differences are sampled velocity, not launch speed.
local M={}
local CHARGE='content/fac_helldivers/equipment/backpacks/c4_charge_backpack/c4_charge'
local AVATAR='content/fac_helldivers/cha_avatar/avatar_helldiver'
function M.new(sr,emit)
    local self={capture=nil,serial=0}
    local function report(kind,row)
        row.observation_only=true
        -- Diagnostic failures must never disable action routing.
        pcall(emit,kind,row)
    end
    local function position(unit,node)
        local vector=sr.Unit.world_position(unit,node or 1)
        local x,y,z=sr.Vector3.x(vector),sr.Vector3.y(vector),sr.Vector3.z(vector)
        for _,v in ipairs({x,y,z}) do assert(type(v)=='number' and v==v and math.abs(v)<1e8,'invalid_position') end
        assert(x and y and z,'incomplete_position')
        return {x,y,z}
    end
    local function scene(world)
        assert(sr.Application.main_world()==world,'world_changed')
        local result={};local count=0
        local units=assert(sr.World.units_by_resource(world,CHARGE),'charge_scan_unavailable')
        for _,unit in pairs(units) do
            count=count+1;assert(count<=128,'diagnostic_scan_limit')
            if sr.Unit.alive(unit) then result[unit]=position(unit) end
        end
        return result
    end
    local function pose(world)
        -- Single-rig scenes are unambiguous. Multiplayer rigs are not guessed.
        local avatar,count=nil,0
        for _,unit in pairs(sr.World.units_by_resource(world,AVATAR) or {}) do
            if sr.Unit.alive(unit) then avatar=unit;count=count+1 end
        end
        if count~=1 then return {flight_rig_status='not_unique',flight_rig_count=count} end
        local row={flight_rig_status='single_avatar',flight_avatar_position=position(avatar)}
        if sr.Unit.has_node(avatar,'attach_hand_r') then
            row.flight_hand_position=position(avatar,sr.Unit.node(avatar,'attach_hand_r'))
        end
        if sr.Unit.has_animation_state_machine and sr.Unit.has_animation_state_machine(avatar) then
            local values={sr.Unit.animation_get_state(avatar)};local states={}
            for i=1,math.min(#values,64) do if type(values[i])=='number' then states[tostring(i)]=values[i] end end
            row.flight_animation_states=states
        end
        return row
    end
    local function end_capture(reason)
        local c=self.capture;if not c then return end
        self.capture=nil
        report('flight_end',{flight_capture_id=c.id,flight_reason=reason,flight_candidate_count=c.count})
    end
    function self.begin(now,request)
        end_capture('next_throw')
        self.serial=self.serial+1
        local ok,why=pcall(function()
            -- Check accessors even when the scene has no charges yet.
            assert(sr.Vector3 and type(sr.Vector3.x)=='function' and
                type(sr.Vector3.y)=='function' and type(sr.Vector3.z)=='function',
                'vector_accessors_unavailable')
            local world=assert(sr.Application.main_world(),'no_world')
            local baseline=scene(world)
            self.capture={id=self.serial,world=world,start=now,last=now,baseline=baseline,units={},count=0}
            report('flight_begin',{flight_capture_id=self.serial,flight_request_id=request,
                flight_window_ms=1600,flight_candidate_ownership='UNCONFIRMED'})
        end)
        if not ok then self.capture=nil;report('flight_unavailable',{reason=tostring(why)}) end
    end
    function self.sample(now)
        local c=self.capture;if not c then return end
        if now-c.start>1600 then end_capture('window_complete');return end
        if now<=c.last then return end
        local ok,why=pcall(function()
            local current=scene(c.world)
            local row={flight_capture_id=c.id,flight_age_ms=now-c.start,flight_units={}}
            local pose_ok,detail=pcall(pose,c.world)
            if pose_ok then for k,v in pairs(detail) do row[k]=v end
            else row.flight_rig_status=tostring(detail) end
            for unit,p in pairs(current) do
                local track=c.units[unit]
                if not c.baseline[unit] and not track then
                    c.count=c.count+1
                    track={id=c.count,first=now};c.units[unit]=track
                end
                if track then
                    local point={candidate=track.id,position=p,age_ms=now-track.first}
                    if track.position and track.time<now then
                        local dt=(now-track.time)/1000;local v={}
                        for i=1,3 do v[i]=(p[i]-track.position[i])/dt end
                        point.sampled_velocity=v;point.sample_interval_ms=now-track.time
                    end
                    row.flight_units[#row.flight_units+1]=point
                    track.position=p;track.time=now
                end
            end
            c.last=now
            report('flight_sample',row)
        end)
        if not ok then end_capture(tostring(why)) end
    end
    function self.stop()end_capture('shutdown')end
    return self
end
return M
