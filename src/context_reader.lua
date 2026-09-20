-- Build 24826606 only. All addresses are read through a bounded copy API.
-- This module does not call native game functions or write game memory.
local bit = require('bit')
local M = {}
local INVALID = 0xffffffff
local DETONATOR = '51f50d6321f52f3d'
local CHARGE = '9b75217d8312dd67'
local AVATAR = '4d1c334d294dfa97'
local function u32(b,o)
    assert(b and o>=0 and o+4<=#b,'short_u32')
    local a,c,d,e=b:byte(o+1,o+4)
    return a+c*256+d*65536+e*16777216
end
local function resource(b)
    local out={}
    for i=8,1,-1 do out[#out+1]=string.format('%02x',b:byte(i)) end
    return table.concat(out)
end
local function hex(b)
    return (b:gsub('.',function(c) return string.format('%02x',c:byte()) end))
end
local function product_low(a,b)
    -- Exact modulo 2^32 multiplication using 16-bit limbs (Lua uses doubles).
    return ((a%65536)*(b%65536)+
        ((math.floor(a/65536)*(b%65536)+(a%65536)*math.floor(b/65536))%65536)*65536)%4294967296
end
M.u32=u32
M.product_low=product_low

function M.snapshot(api,game,extend)
    local guards,reads,bytes={},0,0
    local extension_result
    local function read(at,n,guard)
        assert(type(at)=='number' and at>=65536 and at+n<0x800000000000,'invalid_address')
        reads=reads+1;bytes=bytes+n
        assert(n>0 and n<=4096 and reads<=768 and bytes<=32768,'snapshot_budget')
        local b=assert(api.read(at,n),'read_unavailable')
        assert(#b==n,'short_read')
        if guard then guards[#guards+1]={at=at,bytes=b} end
        return b
    end
    local function ptr(at,guard)
        local p=assert(api.pointer(read(at,8,guard)),'pointer_unavailable')
        assert(p>=65536 and p<0x800000000000,'invalid_pointer')
        return p
    end
    local function global(rva) return ptr(game+rva,true) end
    local function lookup(at,key,limit)
        local h=read(at,20,true)
        local n,empty,mult=u32(h,8),u32(h,12),u32(h,16)
        assert(n<=limit and (n==0 or bit.band(n,n-1)==0),'unsupported_map')
        if n==0 or key==empty or key==INVALID then return nil end
        local p=assert(api.pointer(h),'map_pointer_unavailable')
        for probe=0,math.min(n,128)-1 do
            local slot=(product_low(key,mult)+probe)%n
            local row=read(p+slot*8,8,true)
            local k=u32(row,0)
            if k==key then
                local index=u32(row,4)
                if index~=INVALID then return index end
                return nil
            end
            if k==empty then return nil end
        end
        error('map_probe_limit')
    end
    local function checked()
        for _,g in ipairs(guards) do
            if read(g.at,#g.bytes)~=g.bytes then return false end
        end
        return true
    end
    local row={current_weapon='UNKNOWN',current_fire_mode='UNKNOWN',
        action_result='OBSERVATION_ONLY',context_status='unresolved',
        c4_guard_candidate=false,layout_evidence='STATIC_DERIVATION_PENDING_LIVE_VALIDATION'}
    local function finish(reason)
        if not checked() then return nil,'context_changed_during_read' end
        if reason~='c4_context_observed' then row.c4_guard_candidate=false end
        row.context_status=reason;row.memory_reads=reads;row.memory_bytes=bytes
        return row,nil,extension_result
    end
    local mode=read(global(0x276c3d0),0x44,true)
    if u32(mode,8)==0 or u32(mode,0x40)<1 or u32(mode,0x40)>7 then
        return finish('waiting_for_mission')
    end
    local pm=global(0x276c190)
    local counts=read(pm+0x84,8,true)
    assert(u32(counts,0)<=4 and u32(counts,4)<=4,'unsupported_player_counts')
    if u32(counts,0)==0 or u32(counts,4)==0 then return finish('waiting_for_local_player') end
    local player=read(ptr(pm+0xe8,true),24,true)
    if bit.band(player:byte(21),1)==0 then return finish('local_player_not_owned') end
    local unit=u32(read(pm+0x3a8,4,true),0)
    if unit==0x7fff then return finish('waiting_for_avatar') end
    local owner=global(0x276f0c0)
    local ei=lookup(owner+0xf21a88,unit,1048576)
    if not ei then return finish('avatar_map_missing') end
    assert(ei<262144,'entity_index_limit')
    local entity=read(owner+0xf31ad8+ei*24,24,true)
    if resource(entity)~=AVATAR or bit.band(entity:byte(21),1)==0 then
        return finish('avatar_identity_rejected')
    end
    local id=u32(entity,8)
    local avatar=global(0x276ca30)
    local ai=lookup(avatar+0xf8,id,64)
    local n=u32(read(avatar+0x6c,4,true),0)
    assert(n<=8,'avatar_count_limit')
    if not ai or ai>=n then return finish('avatar_registry_missing') end
    if read(ptr(avatar+0x110+ai*8,true),24,true)~=entity then
        return finish('avatar_registry_mismatch')
    end
    row.local_entity_id=id;row.local_avatar_index=ai
    local inventory=global(0x276c468)
    local ii=lookup(inventory+0x28,id,65536)
    local count=u32(read(inventory+0x14,4,true),0)
    assert(count<=4096,'inventory_count_limit')
    if not ii or ii>=count then return finish('inventory_missing') end
    if read(ptr(ptr(inventory+0x40,true)+ii*8,true),24,true)~=entity then
        return finish('inventory_owner_mismatch')
    end
    local state=read(ptr(inventory+0x50,true)+ii*48,48,true)
    row.inventory_words={}
    for i=0,11 do row.inventory_words[tostring(i*4)]=u32(state,i*4) end
    local slot=u32(state,0x1c)
    row.selected_slot=slot
    local offsets={[1]=0,[2]=4,[3]=8,[4]=16,[5]=16,[6]=12}
    if not offsets[slot] then return finish('no_selected_weapon') end
    local weapon_id=u32(state,offsets[slot])
    row.selected_entity_id=weapon_id
    if weapon_id==0 or weapon_id==INVALID then return finish('selected_entity_missing') end
    local wi=lookup(owner+0xf19a70,weapon_id,1048576)
    if not wi then return finish('selected_entity_missing') end
    assert(wi<262144,'weapon_entity_index_limit')
    local weapon=read(owner+0xf31ad8+wi*24,24,true)
    if u32(weapon,8)~=weapon_id then return finish('selected_entity_mismatch') end
    local hash=resource(weapon)
    row.current_weapon_resource=hash
    row.current_weapon=hash==DETONATOR and 'C4_DETONATOR' or hash==CHARGE and 'C4_CHARGE' or 'OTHER'
    row.weapon_owned=bit.band(weapon:byte(21),1)~=0
    row.c4_guard_candidate=hash==DETONATOR and row.weapon_owned
    -- An equipped resource must be observed live during the weapon-switch test
    -- before this candidate guard is used to authorize any action.
    if not row.c4_guard_candidate then return finish('selected_weapon_observed') end

    local wd=global(0x276c9f0)
    local di=lookup(wd+0x30,weapon_id,65536)
    local dn=u32(read(wd+0x1c,4,true),0)
    assert(dn<=4096,'weapon_data_count_limit')
    if di and di<dn then
        if read(ptr(ptr(wd+0x48,true)+di*8,true),24,true)~=weapon then
            return finish('weapon_data_owner_mismatch')
        end
        local base=ptr(wd+0x58,true)+di*0x3e0
        local types=read(base+0x340,16,true)
        local packed=read(ptr(wd+0x60,true)+di*12,12,true)
        row.weapon_state_12=hex(packed)
        row.weapon_state_flags=hex(read(ptr(wd+0x50,true)+di*2,2,true))
        row.weapon_function_types={};row.weapon_function_values={}
        local shifts={[1]=4,[7]=0,[8]=2,[9]=6,[10]=8,[11]=10,[12]=14}
        for i=0,3 do
            local k=u32(types,i*4)
            row.weapon_function_types[tostring(i)]=k
            if shifts[k] then
                row.weapon_function_values[tostring(i)]=bit.band(bit.rshift(u32(packed,4),shifts[k]),3)
            end
        end
    else row.weapon_data_status='missing' end

    -- Exact 16-entry resource table used by native getter 0x508be0.
    -- Each 0x58-byte config contains two 40-byte ability descriptors.
    -- Presence here is evidence of configuration, not proof of callable actions.
    local templates=ptr(owner+0xf11888,true)
    local start=tonumber(hash:sub(9,16),16)%16
    row.ability_template_status='absent'
    for probe=0,15 do
        local t=read(templates+((start+probe)%16)*16,16,true)
        local key=resource(t)
        if key=='0000000000000000' then break end
        if key==hash then
            local ti=u32(t,8)
            assert(ti<16,'ability_template_index_limit')
            local config=read(templates+256+ti*0x58,0x58,true)
            row.ability_template_status='present';row.ability_template_hex=hex(config)
            row.ability_descriptors={}
            for i=0,1 do
                local o=i*40
                row.ability_descriptors[tostring(i)]={weapon_ability_id=u32(config,o),
                    owner_ability_id=u32(config,o+4),other_ability_id=u32(config,o+8),
                    flag_32=config:byte(o+33),flag_33=config:byte(o+34)}
            end
            break
        end
    end
    if extend then
        -- Keep validated observations when the action-specific layout is
        -- unsupported. Never return a callable capability from a failed read.
        -- finish() still rechecks every successful read, including extensions.
        local ok,result=pcall(extend,{read=read,ptr=ptr,global=global,lookup=lookup,
            checked=checked,u32=u32,hex=hex,resource=resource,entity=entity,weapon=weapon,
            id=id,weapon_id=weapon_id,owner=owner,avatar=avatar,avatar_index=ai,
            weapon_data=wd,weapon_data_index=di},row)
        if ok then
            extension_result=result;row.action_context_status='validated'
        else
            extension_result=nil;row.action_context_status='rejected'
            row.action_diagnostic=tostring(result)
            row.action_context_error=row.action_diagnostic:match(':%d+: (.*)$') or row.action_diagnostic
            row.action_gate='ACTION_CONTEXT_REJECTED'
        end
    end
    return finish('c4_context_observed')
end
return M
