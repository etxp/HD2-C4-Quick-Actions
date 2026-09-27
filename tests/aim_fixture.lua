-- Synthetic original input manager; native ABI is checked at each mock call.
local ffi=require('ffi')
return function(s,R,D,base)
    local owner,buckets,maskmap=0x70000000,0x71000000,0x72000000
    s.input_owner=owner;s.aim_row=owner+D.input_inhibit_rows
    s.ptr(s.game+R.global_input_owner,owner)
    s.u32(owner+D.input_inhibit_count,0)
    s.map(owner+D.input_inhibit_map,maskmap,{})
    s.ptr(owner+D.input_bindings,buckets)
    s.u32(owner+D.input_bindings+8,256)
    s.u32(owner+D.input_bindings+12,0xffffffff)
    s.u32(owner+D.input_bindings+16,1)
    for i=0,255 do s.u32(buckets+i*328,0xffffffff) end
    s.aim_state=owner+808+32*(2*97+8);s.put(s.aim_state,'\0')
    s.fire_input_state=s.aim_state+32;s.put(s.fire_input_state,'\0')
    s.fire_row=s.aim_row+24
    s.fire_inhibit_calls=0;s.fire_unblock_calls=0
    local addresses={}
    for key,code in pairs({aim=D.input_aim_code,deploy=10*65536,detonate=10*65536+2}) do
        local i=code%256
        while base.u32(s.api.read(buckets+i*328,4),0)~=0xffffffff do i=(i+1)%256 end
        local at=buckets+i*328;s.u32(at,code);s.u32(at+4,1);addresses[key]=at+8
    end
    function s.mapping(key,trigger,control,device,slot)
        local at=addresses[key];s.zero(at,20)
        s.u32(at,(device or 1)+4*16+(slot or 255)*256+(trigger or 0)*65536+(control or 1)*1048576)
        s.u32(at+8,trigger or 0)
    end
    s.mapping('aim');s.mapping('deploy');s.mapping('detonate',0,0)
    s.inhibit_calls=0;s.unblock_calls=0
    function s.mask_mode()
        if base.u32(s.api.read(owner+D.input_inhibit_count,4),0)==0 then return 0 end
        return base.u32(s.api.read(s.aim_row,4),0)
    end
    function s.fire_mask_mode()
        if base.u32(s.api.read(owner+D.input_inhibit_count,4),0)==0 then return 0 end
        return base.u32(s.api.read(s.fire_row,4),0)
    end
    local function ensure_records()
        if base.u32(s.api.read(owner+D.input_inhibit_count,4),0)>0 then return end
        s.u32(owner+D.input_inhibit_count,2)
        s.map(owner+D.input_inhibit_map,maskmap,{{D.input_aim_code,0},{D.input_fire_code,1}})
        for i=0,1 do
            local at=s.aim_row+i*24;s.zero(at,24);s.u32(at+4,2);s.u32(at+8,8+i)
        end
    end
    function s.set_mask(mode,expiry)
        ensure_records();s.u32(s.aim_row,mode);s.u32(s.aim_row+16,expiry or 0)
    end
    s.native.input_mapping=function(manager,action,fallback)
        assert(manager==owner and tonumber(action)==D.input_aim_action and fallback==true)
        return ffi.cast('void *',addresses.aim)
    end
    s.native.input_inhibit=function(manager,action,mode,duration)
        assert(manager==owner and mode==1 and duration==-1)
        if tonumber(action)==D.input_fire_action then
            s.fire_inhibit_calls=s.fire_inhibit_calls+1;ensure_records();s.u32(s.fire_row,mode)
        else
            assert(tonumber(action)==D.input_aim_action)
            s.inhibit_calls=s.inhibit_calls+1;s.set_mask(mode)
        end
    end
    s.native.input_unblock=function(manager,action)
        assert(manager==owner)
        if tonumber(action)==D.input_fire_action then
            s.fire_unblock_calls=s.fire_unblock_calls+1;s.u32(s.fire_row,0)
        else
            assert(tonumber(action)==D.input_aim_action)
            s.unblock_calls=s.unblock_calls+1;s.u32(s.aim_row,0)
        end
    end
end
