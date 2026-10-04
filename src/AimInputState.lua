-- Read-only native binding/inhibition state. All addresses are snapshot-scoped.
local bit=require('bit')
local M={}
-- The observation below is a pure function of its guarded bytes, the MBM
-- codes and (for Aim) the engine's selected mapping. While every guard still
-- compares equal it is reused; the engine's selection is queried every time.
local function selected(result,lists,chosen)
    if chosen and chosen~=0 then
        for _,v in ipairs(lists.aim) do
            if v.at==chosen then result.aim=v.bytes;break end
        end
        assert(result.aim,'aim_selected_mapping_outside_bucket')
    end
end
-- The Aim and Fire gates guard neighbouring records of one input owner. Once
-- per phase their guards are reread together, one read per page; each gate
-- then compares its own guards against those just-read spans.
function M.group()
    local self={members={},epoch=nil,plan=nil}
    function self.set(key,guards)self.members[key]=guards;self.plan=nil end
    -- Returns whether phase spans may be shared, and whether this very call
    -- reread them (false when an earlier call in the phase already had).
    function self.sweep(api)
        local epoch=api.memo_epoch and api.memo_epoch()
        if not epoch then return false,false end
        if self.epoch==epoch and self.plan then return true,false end
        if not self.plan then
            local all={}
            for _,guards in pairs(self.members)do
                for i=1,#guards do all[#all+1]=guards[i] end
            end
            self.plan=GuardSpans.plan(all)
        end
        self.epoch=epoch
        -- A difference is found by the member comparison that follows.
        pcall(GuardSpans.same,api,self.plan,true,false)
        return true,true
    end
    return self
end
local function reuse(api,c,codes,native,spec,verify_mapping,group)
    if spec.fire then
        if c.codes~=true then return nil end
        local ok,same=pcall(c.same,group and (group.sweep(api)))
        return ok and same and c.result or nil
    end
    if type(c.codes)~='table' or c.codes.deploy~=codes.deploy or c.codes.detonate~=codes.detonate then return nil end
    -- Same order as a full read: code first, then the bytes the query uses.
    -- The native query must follow a reread made in this call: spans from an
    -- earlier call in the phase are not accepted here.
    if verify_mapping then verify_mapping() end
    local shared,reread=false,false
    if group then shared,reread=group.sweep(api) end
    local ok,same=pcall(c.same,shared and reread)
    if not ok or not same then return nil end
    local base=c.result
    local result={owner=base.owner,mask=base.mask,count=base.count,same=base.same,held=base.held,
        deploy=base.deploy,detonate=base.detonate}
    selected(result,c.lists,native.input_mapping(base.owner,spec.action))
    assert(c.same(),'aim_snapshot_changed')
    return result
end
function M.read(api,game,base,codes,native,spec,verify_mapping,hints)
    spec=spec or {action=D.input_aim_action,code=D.input_aim_code,index=8}
    local group=hints and hints.group
    if codes and hints and hints.cache then
        local result=reuse(api,hints.cache,codes,native,spec,verify_mapping,group)
        if result then return result end
        hints.cache=nil
        if group then group.set(hints,nil) end
    end
    local guards={}
    local function read(at,n)
        assert(type(at)=='number' and at>=65536 and at+n<0x800000000000
            and n>0 and n<=512 and #guards<1000,'aim_read_bounds')
        local b=assert(api.read(at,n),'aim_read_unavailable');assert(#b==n,'aim_short_read')
        guards[#guards+1]={at=at,bytes=b};return b
    end
    local function ptr(at)return assert(api.pointer(read(at,8)),'aim_pointer')end
    -- Every guarded byte is reread; guards on one page share one read.
    local same=GuardSpans.checker(api,guards,false)
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
    if spec.fire then
        assert(same(),'fire_input_snapshot_changed')
        if hints then
            hints.cache={codes=true,same=same,result=result}
            if group then group.set(hints,guards) end
        end
        return result
    end
    local bh=read(owner+D.input_bindings,20)
    local capacity=base.u32(bh,8);assert(capacity==256,'aim_binding_capacity')
    local buckets=assert(api.pointer(bh),'aim_binding_pointer')
    local wanted={[spec.code]='aim',[codes.deploy]='deploy',[codes.detonate]='detonate'}
    assert(wanted[spec.code]=='aim','aim_assignment_collision')
    -- Positive bucket locations are only hints. The owner/header/key and every
    -- mapping byte are read again for each use. A moved/removed bucket falls
    -- back to the original probe within this call; a miss is never cached.
    -- Three fixed role keys bound storage even across unlimited user remaps.
    if hints and (hints.owner~=owner or hints.header~=bh or hints.aim~=spec.code
        or hints.deploy~=codes.deploy or hints.detonate~=codes.detonate) then
        hints.owner=owner;hints.header=bh;hints.aim=spec.code
        hints.deploy=codes.deploy;hints.detonate=codes.detonate;hints.slots={}
    end
    local lists,probed={},false
    for code,key in pairs(wanted) do
        local at=hints and hints.slots[key]
        if at and base.u32(read(at,4),0)~=code then hints.slots[key]=nil;at=nil end
        if not at then
            probed=true
            local start=base.product_low(code,base.u32(bh,16))%capacity
            for probe=0,capacity-1 do
                local candidate=buckets+((start+probe)%capacity)*328
                if base.u32(read(candidate,4),0)==code then at=candidate;break end
            end
        end
        if at then
            local size=base.u32(read(at+4,4),0);assert(size<=16,'aim_binding_count')
            local mappings={}
            for j=0,size-1 do mappings[#mappings+1]={at=at+8+j*20,bytes=read(at+8+j*20,20)} end
            lists[key]=mappings
            if hints then hints.slots[key]=at end
        end
    end
    assert(lists.aim and lists.deploy and lists.detonate,'aim_binding_missing')
    -- Original readonly device-selection routine; no device/key polling.
    -- Verify directly at the call boundary, including its catalog dependencies.
    if verify_mapping then verify_mapping() end
    assert(same(),'aim_binding_changed')
    local chosen=native.input_mapping(owner,spec.action)
    result.deploy=lists.deploy;result.detonate=lists.detonate
    local observed={owner=owner,mask=mask,count=count,same=same,held=result.held,
        deploy=lists.deploy,detonate=lists.detonate}
    selected(result,lists,chosen)
    assert(same(),'aim_snapshot_changed')
    -- Keep only an observation located through the three remembered buckets:
    -- its guards are those few records, not a whole probe sequence.
    if hints and not probed then
        hints.cache={codes={deploy=codes.deploy,detonate=codes.detonate},same=same,result=observed,lists=lists}
        if group then group.set(hints,guards) end
    end
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
