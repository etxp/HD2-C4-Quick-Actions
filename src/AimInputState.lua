-- Read-only native binding/inhibition state. All addresses are snapshot-scoped.
local bit=require('bit')
local M={}
function M.read(api,game,base,codes,native,spec)
    spec=spec or {action=D.input_aim_action,code=D.input_aim_code,index=8}
    local guards={}
    local function read(at,n)
        assert(type(at)=='number' and at>=65536 and at+n<0x800000000000
            and n>0 and n<=512 and #guards<1000,'aim_read_bounds')
        local b=assert(api.read(at,n),'aim_read_unavailable');assert(#b==n,'aim_short_read')
        guards[#guards+1]={at,b};return b
    end
    local function ptr(at)return assert(api.pointer(read(at,8)),'aim_pointer')end
    local function same()
        for _,v in ipairs(guards) do if api.read(v[1],#v[2])~=v[2] then return false end end
        return true
    end
    local owner=ptr(game+R.global_input_owner)
    local count=base.u32(read(owner+D.input_inhibit_count,4),0)
    assert(count<=D.input_inhibit_capacity,'aim_inhibition_count')
    local h=read(owner+D.input_inhibit_map,20)
    local n,empty,mult=base.u32(h,8),base.u32(h,12),base.u32(h,16)
    assert(n<=1024 and (n==0 or bit.band(n,n-1)==0),'aim_inhibition_map')
    local index
    if n>0 then
        local tableptr=assert(api.pointer(h),'aim_inhibition_pointer')
        local ended=false
        for i=0,math.min(n,128)-1 do
            local b=read(tableptr+((base.product_low(spec.code,mult)+i)%n)*8,8)
            local key=base.u32(b,0)
            if key==spec.code then index=base.u32(b,4);ended=true;break end
            if key==empty then ended=true;break end
        end
        assert(ended,'aim_inhibition_probe_limit')
    end
    local mask
    if index and index~=0xffffffff then
        assert(index<count,'aim_inhibition_index')
        local address=owner+D.input_inhibit_rows+index*24
        local b=read(address,24)
        assert(base.u32(b,4)==2 and base.u32(b,8)==spec.index,'aim_inhibition_identity')
        mask={address=address,bytes=b,mode=base.u32(b,0)}
    end
    local result={owner=owner,mask=mask,count=count,same=same}
    if not codes then assert(same(),'aim_state_changed');return result end
    local state=read(owner+808+32*(2*97+spec.index),1)
    assert(state:byte()<=1,'aim_action_state');result.held=state:byte()~=0
    if spec.fire then assert(same(),'fire_input_snapshot_changed');return result end
    local bh=read(owner+D.input_bindings,20)
    local capacity=base.u32(bh,8);assert(capacity==256,'aim_binding_capacity')
    local buckets=assert(api.pointer(bh),'aim_binding_pointer')
    local wanted={[spec.code]='aim',[codes.deploy]='deploy',[codes.detonate]='detonate'}
    assert(wanted[spec.code]=='aim','aim_assignment_collision')
    local lists={}
    for code,key in pairs(wanted) do
      for probe=0,capacity-1 do
        local i=(base.product_low(code,base.u32(bh,16))+probe)%capacity
        local at=buckets+i*328
        if base.u32(read(at,4),0)==code then
            local size=base.u32(read(at+4,4),0);assert(size<=16,'aim_binding_count')
            local mappings={}
            for j=0,size-1 do mappings[#mappings+1]={at=at+8+j*20,bytes=read(at+8+j*20,20)} end
            lists[key]=mappings
            break
        end
      end
    end
    assert(lists.aim and lists.deploy and lists.detonate,'aim_binding_missing')
    assert(same(),'aim_binding_changed')
    -- Original readonly device-selection routine; no device/key polling.
    local chosen=native.input_mapping(owner,spec.action)
    if chosen and chosen~=0 then
        for _,v in ipairs(lists.aim) do
            if v.at==chosen then result.aim=v.bytes;break end
        end
        assert(result.aim,'aim_selected_mapping_outside_bucket')
    end
    result.deploy=lists.deploy;result.detonate=lists.detonate
    assert(same(),'aim_snapshot_changed')
    return result
end
-- Match device, input kind and control index as the original overlap code does.
-- A specific device slot must match unless either mapping uses the wildcard.
local function matches(base,a,b)
    local x,y=base.u32(a,0),base.u32(b,0)
    if bit.band(x,0xfff000ff)~=bit.band(y,0xfff000ff) then return false end
    local sx,sy=bit.band(bit.rshift(x,8),255),bit.band(bit.rshift(y,8),255)
    return sx==sy or sx==255 or sy==255
end
function M.policy(base,p)
    if not p.aim then return false,'no_active_aim_mapping' end
    for _,v in ipairs(p.detonate) do
        if matches(base,p.aim,v.bytes) then return true,'detonate_overlap' end
    end
    local release=false
    for _,v in ipairs(p.deploy) do
        if matches(base,p.aim,v.bytes) then
            local kind=bit.band(bit.rshift(base.u32(v.bytes,0),4),15)
            -- Native Button mappings duplicate trigger in flags and +8.
            if kind~=4 then return true,'throw_non_button_overlap' end
            local trigger=base.u32(v.bytes,8)
            assert(trigger==bit.band(bit.rshift(base.u32(v.bytes,0),16),15) and trigger<=8,
                'aim_trigger_mismatch')
            if trigger==1 or trigger==7 then release=true
            else return true,'throw_overlap' end
        end
    end
    return false,release and 'release_throw_aim_preserved' or 'independent_aim_preserved'
end
return M
