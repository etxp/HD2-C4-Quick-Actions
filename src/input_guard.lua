-- Keep exact raw evidence. A retained down state is not a fresh menu press.
local M={}
local function down(v)
    assert(type(v)=='boolean' or (type(v)=='number' and v==v and v>=0 and v<=1),'invalid_guard_value')
    return v==true or type(v)=='number' and v>=0.5
end
local function edge(v)
    assert(type(v)=='boolean' or (type(v)=='number' and v==v and v>=0 and v<=1),'invalid_guard_edge')
    return v==true or type(v)=='number' and v>0
end
function M.new(emit)
    local self={}
    function self.sample(keys)
        local blocked=false;local cancel
        for _,key in ipairs(keys) do
            local value=key.device.button(key.id)
            local pressed=type(key.device.pressed)=='function' and key.device.pressed(key.id) or false
            local released=type(key.device.released)=='function' and key.device.released(key.id) or false
            local d,p,r=down(value),edge(pressed),edge(released)
            local fresh=p and key.down==false and not key.pressed
            -- If a gamepad lacks pressed(), a released-to-down transition
            -- is still an edge; keyboard devices always expose pressed().
            if type(key.device.pressed)~='function' then fresh=d and key.down==false end
            blocked=blocked or d or p
            if d~=key.down or p~=key.pressed or r~=key.released then
                assert(emit('guard_input',{input=key.label,button_id=key.id,
                    raw_value=value,raw_pressed=pressed,raw_released=released,
                    previous_down=key.down,down=d,pressed=p,released=r,fresh_menu_edge=fresh}),
                    'guard_log_unavailable')
            end
            if fresh and not cancel then cancel={input=key.label,button_id=key.id,
                raw_value=value,raw_pressed=pressed,raw_released=released} end
            key.down=d;key.pressed=p;key.released=r
        end
        return blocked,cancel
    end
    return self
end
return M
