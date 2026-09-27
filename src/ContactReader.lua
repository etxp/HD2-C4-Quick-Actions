-- Owned projectile capabilities survive switching weapons, but never a world,
-- entity generation or network-authority change. No writes or native calls.
local bit=require('bit')
local M={}
local CHARGE='9b75217d8312dd67'
local function hex(b)return (b:gsub('.',function(c)return string.format('%02x',c:byte())end))end
local function memory(api,game,base)
    local guards,reads,bytes={},0,0
    local e={u32=base.u32,hex=hex,resource=function(b)return hex(b:sub(1,8):reverse())end}
    function e.read(at,n,guard)
        reads=reads+1;bytes=bytes+n
        assert(type(at)=='number' and at>=65536 and at+n<0x800000000000,'contact_address')
        assert(n>0 and n<=4096 and reads<=16384 and bytes<=1048576,'contact_read_budget')
        local b=assert(api.read(at,n),'contact_read_unavailable');assert(#b==n,'contact_short_read')
        if guard then guards[#guards+1]={at=at,bytes=b} end
        return b
    end
    function e.ptr(at,guard)return assert(api.pointer(e.read(at,8,guard)),'contact_pointer')end
    function e.global(rva)return e.ptr(game+assert(rva),true)end
    function e.lookup(at,key,limit)
        local h=e.read(at,20,true);local n,empty,mult=base.u32(h,8),base.u32(h,12),base.u32(h,16)
        assert(n<=limit and (n==0 or bit.band(n,n-1)==0),'contact_map_layout')
        if n==0 or key==empty or key==0xffffffff then return end
        local data=assert(api.pointer(h),'contact_map_pointer')
        for probe=0,math.min(n,128)-1 do
            local slot=(base.product_low(key,mult)+probe)%n
            local b=e.read(data+slot*8,8,true);local k=base.u32(b,0)
            if k==key then local v=base.u32(b,4);if v~=0xffffffff then return v end;return end
            if k==empty then return end
        end
        error('contact_map_probe_limit')
    end
    function e.checked()
        for _,g in ipairs(guards)do if e.read(g.at,#g.bytes)~=g.bytes then return false end end
        return true
    end
    return e
end
local function scan(e,symbols,lease,events)
    local read,ptr,lookup,u32=e.read,e.ptr,e.lookup,e.u32
    local owner=e.global(symbols.global_contact_owner)
    assert(owner==lease.owner and e.global(symbols.global_contact_world)==lease.root,'contact_world_changed')
    local wi=lookup(owner+D.entity_id_map,lease.weapon_id,1048576)
    if not wi then return {lease=lease,charges={},same=e.checked,expired=true} end
    assert(wi<262144,'contact_weapon_index')
    if read(owner+D.entity_array+wi*24,24,true)~=lease.weapon then
        return {lease=lease,charges={},same=e.checked,expired=true}
    end
    local remote=e.global(symbols.global_contact_remote)
    local count=u32(read(remote+0x10,4,true),0);assert(count<=128,'contact_registry_budget')
    local result={lease=lease,charges={},same=e.checked,remote=remote}
    if count==0 then return result end
    local registry,links=ptr(remote+0x38,true),ptr(remote+0x48,true)
    local by_unit={}
    for i=0,count-1 do
        local at=ptr(registry+i*8,true);local entity=read(at,24,true)
        if e.resource(entity)==CHARGE and bit.band(entity:byte(21),1)~=0 then
            local reference=u32(read(links+i*8,8,true),0)
            local oi=reference~=0x7fff and lookup(owner+D.entity_unit_map,reference,1048576)
            if oi then
                assert(oi<262144,'contact_owner_index')
                if read(owner+D.entity_array+oi*24,24,true)==lease.weapon then
                    local id,unit=u32(entity,8),u32(entity,12)
                    assert(lookup(remote+0x20,id,65536)==i,'contact_remote_index')
                    local ei=assert(lookup(owner+D.entity_id_map,id,1048576),'contact_entity_missing')
                    assert(ei<262144 and read(owner+D.entity_array+ei*24,24,true)==entity,'contact_entity_reused')
                    assert(unit~=0 and lookup(owner+D.unit_entity_id_map,unit,1048576)==id,'contact_unit_identity')
                    local explosive=e.global(symbols.global_contact_explosive)
                    local xi=lookup(explosive+0x38,id,65536)
                    if xi then
                        assert(xi<4096,'contact_explosive_index')
                        assert(read(ptr(ptr(explosive+0x50,true)+xi*8,true),24,true)==entity,'contact_explosive_identity')
                        local network=read(ptr(explosive+0x68,true)+xi*56,2,true)
                        assert(network:byte(2)<=1,'contact_explosive_flag')
                        local item={id=id,unit=unit,identity=hex(entity),entity=entity,
                            manager=explosive,requested=network:byte(2)==1,
                            invalid_source=u32(read(e.game+symbols.global_contact_invalid_source,4,true),0)}
                        assert(#result.charges<128,'contact_owned_budget')
                        result.charges[#result.charges+1]=item;by_unit[unit]=item
                    end
                end
            end
        end
    end
    for _,event in ipairs(events and events.contacts or {})do
        if event.kind~=2 and event.unit_a~=event.unit_b then
            for _,unit in ipairs({event.unit_a,event.unit_b})do
                local item=by_unit[unit]
                if item and not item.contact then item.contact=event end
            end
        end
    end
    return result
end
function M.selected(api,game,base,symbols)
    local row,err,selected=base.snapshot(api,game,function(e,row)
        assert(row.weapon_function_types and row.weapon_function_types['0']==10,'contact_selector_type')
        local selector=row.weapon_function_values['0'];assert(selector==0 or selector==1,'contact_selector')
        local lease={owner=e.owner,root=e.global(symbols.global_contact_world),weapon=e.weapon,weapon_id=e.weapon_id}
        lease.identity=table.concat({tostring(lease.owner),tostring(lease.root),e.hex(lease.weapon)},':')
        return {lease=lease,mode=selector==1 and 'CONTACT' or 'MANUAL',same=e.checked}
    end)
    if not selected then return row,err end
    local result=M.tracked(api,game,base,symbols,selected.lease)
    assert(selected.same(),'contact_selected_context_changed')
    result.mode=selected.mode
    return row,err,result
end
function M.tracked(api,game,base,symbols,lease,events)
    local e=memory(api,game,base);e.game=game
    local result=scan(e,symbols,lease,events)
    assert(e.checked(),'contact_snapshot_changed')
    return result
end
return M
