-- A full, collision-heavy native binding hash table shared by A/B benchmarks.
-- This changes fixture-owned memory only. Existing mapping edits remain usable.
local ffi=require('ffi')
return function(s)
    local R=dofile('private/tests/mock_symbols.lua')
    local D=dofile('private/tests/mock_fields.lua')
    local base=dofile('private/tests/modules/context_reader.lua')(R,D)
    local owner=assert(s.input_owner,'aim fixture required')
    local header=owner+D.input_bindings
    local buckets=assert(s.api.pointer(s.api.read(header,8)))
    local codes={aim=D.input_aim_code,deploy=10*65536,detonate=10*65536+2}
    local entries,old_addresses={},{}
    for key,code in pairs(codes) do
        for index=0,255 do
            local at=buckets+index*328
            if base.u32(s.api.read(at,4),0)==code then
                local count=base.u32(s.api.read(at+4,4),0)
                local parts={s.api.read(at,8)}
                for i=0,count-1 do parts[#parts+1]=s.api.read(at+8+i*20,20) end
                entries[key]=table.concat(parts);old_addresses[key]=at+8;break
            end
        end
        assert(entries[key],'fixture mapping missing: '..key)
    end
    for index=0,255 do
        local at=buckets+index*328
        s.u32(at,0x60000000+index);s.u32(at+4,0)
    end
    local addresses={}
    for key,index in pairs({aim=190,deploy=200,detonate=210}) do
        local at=buckets+index*328;s.put(at,entries[key]);addresses[key]=at+8
    end
    local mapping=s.mapping
    function s.mapping(key,...)
        mapping(key,...)
        s.put(addresses[key],assert(s.api.read(old_addresses[key],20)))
    end
    s.native.input_mapping=function(manager,action,fallback)
        assert(manager==owner and tonumber(action)==D.input_aim_action and fallback==true)
        return ffi.cast('void *',addresses.aim)
    end
    s.binding_probe={owner=owner,header=header,buckets=buckets,addresses=addresses,codes=codes}
    return s.binding_probe
end
