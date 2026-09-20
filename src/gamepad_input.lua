-- Read engine-owned pads. Do not change global dead zones or inject input.
local M={}
local function flag(v)
    assert(type(v)=='boolean' or (type(v)=='number' and v==v),'invalid_pad_flag')
    return v==true or type(v)=='number' and v>0
end
local function value(v)
    if type(v)=='boolean' then return v and 1 or 0 end
    assert(type(v)=='number' and v==v and v>=0 and v<=1,'invalid_trigger_value')
    return v
end
local function id(device,name)
    local ok,n=pcall(device.button_id,name)
    if not ok or type(n)~='number' or n<0 or n>255 or n~=math.floor(n) then return nil end
    local yes,actual=pcall(device.button_name,n)
    if not yes or actual~=name then return nil end
    return n
end
local function describe(device,method)
    if type(device[method])~='function' then return 'UNKNOWN' end
    local ok,result=pcall(device[method]);return ok and type(result)=='string' and result or 'UNKNOWN'
end
local function buttons(device)
    local result={}
    if type(device.num_buttons)~='function' or type(device.button_name)~='function' then return result end
    local ok,n=pcall(device.num_buttons)
    if not ok or type(n)~='number' or n<0 or n>64 or n~=math.floor(n) then return result end
    for i=0,n-1 do
        local yes,name=pcall(device.button_name,i)
        if yes and type(name)=='string' and name~='' then result[tostring(i)]=name end
    end
    return result
end
function M.new(engine,emit)
    local self={selected=nil,epoch=0,status=nil,last_scan=-math.huge}
    local function publish(status,row)
        self.status=status;row=row or {};row.gamepad_status=status
        assert(emit('gamepad',row),'gamepad_log_unavailable')
    end
    local function select(now)
        if self.selected then
            local s=self.selected
            if rawget(engine,s.slot)==s.device and flag(s.device.active()) then return s,false end
            self.selected=nil;self.epoch=self.epoch+1
            publish('disconnected',{device=s.slot,device_epoch=self.epoch})
        end
        if now-self.last_scan<500 then return nil,false end
        self.last_scan=now
        local seen={}
        -- Prefer the game's Xbox/Steam Input pad. A mirrored native PS pad
        -- must not produce a second trigger action from the same controller.
        for _,family in ipairs({'Pad','PS4Pad'}) do
            for index=1,4 do
                local slot=family..index;local d=rawget(engine,slot)
                if type(d)=='table' and not seen[d] and type(d.active)=='function' then
                    seen[d]=true
                    if flag(d.active()) then
                        local s={slot=slot,device=d,down={false,false},valid=false,menus={}}
                        if type(d.button_id)=='function' and type(d.button_name)=='function'
                            and type(d.button)=='function' then
                            for _,names in ipairs({{'left_trigger','right_trigger','LT','RT'},{'l2','r2','L2','R2'}}) do
                                local l,r=id(d,names[1]),id(d,names[2])
                                if l and r and l~=r then
                                    s.left=l;s.right=r;s.labels={names[3],names[4]};s.valid=true;break
                                end
                            end
                            for _,name in ipairs({'start','back','options','share'}) do
                                local n=id(d,name)
                                if n then s.menus[#s.menus+1]={id=n,label=slot..'.'..name,device=d,down=nil} end
                            end
                        end
                        self.epoch=self.epoch+1;self.selected=s
                        publish(s.valid and 'connected' or 'unsupported_buttons',{
                            device=slot,device_epoch=self.epoch,device_name=describe(d,'name'),
                            device_type=describe(d,'type'),left_id=s.left,right_id=s.right,
                            deploy_input=s.labels and s.labels[1],detonate_input=s.labels and s.labels[2],
                            press_threshold=0.55,release_threshold=0.25,baseline_threshold=0.1,
                            available_buttons=buttons(d)})
                        return s,true
                    end
                end
            end
        end
        if self.status~='not_connected' then publish('not_connected') end
        return nil,false
    end
    function self.sample(now)
        local prior=self.epoch
        local s=select(now)
        local result={epoch=self.epoch,changed=prior~=self.epoch,released=true,available=true,
            left={down=false,pressed=false,released=false},right={down=false,pressed=false,released=false},menus={}}
        if not s then return result end
        result.device=s.slot;result.available=s.valid;result.released=false;result.menus=s.menus
        if not s.valid then return result end
        local function sample(index,n,label)
            local v=value(s.device.button(n));local old=s.down[index]
            local down=old and v>0.25 or v>=0.55
            s.down[index]=down
            return {down=down,pressed=down and not old,released=old and not down,value=v,
                label=label,device=s.slot,button_id=n}
        end
        result.left=sample(1,s.left,s.labels[1]);result.right=sample(2,s.right,s.labels[2])
        result.released=result.left.value<=0.1 and result.right.value<=0.1
        return result
    end
    return self
end
return M
