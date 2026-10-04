-- This module does not call native game functions or write game memory.
local bit = require('bit')
local M = {}
-- Maintainers keep full descriptive rows by default. The Off runtime selects
-- quiet rows while retaining every raw read, guard and gameplay field.
M.diagnostics=true
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
    -- Two exact uint32 words preserve the uint64 resource ID without rounding
    -- it through a double or formatting each of its eight bytes separately.
    return bit.tohex(u32(b,4),8)..bit.tohex(u32(b,0),8)
end
local HEX={}
for n=0,255 do HEX[n]=bit.tohex(n,2) end
local function hex(b)
    local out={};local count=0;local length=#b;local at=1
    -- Diagnostic/descriptor bytes keep their original order. All arithmetic
    -- is exact below 2^32; tohex also handles the signed bit-library boundary.
    while at+3<=length do
        local a,c,d,e=b:byte(at,at+3)
        count=count+1;out[count]=bit.tohex(a*16777216+c*65536+d*256+e,8)
        at=at+4
    end
    while at<=length do
        count=count+1;out[count]=HEX[b:byte(at)];at=at+1
    end
    return table.concat(out)
end
local function product_low(a,b)
    -- Exact modulo 2^32 multiplication using 16-bit limbs (Lua uses doubles).
    return ((a%65536)*(b%65536)+
        ((math.floor(a/65536)*(b%65536)+(a%65536)*math.floor(b/65536))%65536)*65536)%4294967296
end
M.u32=u32
function M.f32(b,o)
    local n=u32(b,o);local sign=n>=0x80000000 and -1 or 1
    local exponent=math.floor(n/0x800000)%256;local fraction=n%0x800000
    assert(exponent~=255,'nonfinite_native_float')
    return sign*(exponent==0 and fraction*2^-149 or (1+fraction/0x800000)*2^(exponent-127))
end
M.product_low=product_low

local function walk(api,game,extend,scope,source)
    local guards,reads,bytes={},0,0
    local guarded_bytes=0
    local extension_result
    local ability_template
    local avatar_flags
    -- An unreadable address is an input that no guard records. A walk that
    -- met one (or made an unguarded read) is never offered for reuse.
    local reusable=true
    local function read(at,n,guard)
        assert(type(at)=='number' and at>=65536 and at+n<0x800000000000,'invalid_address')
        reads=reads+1;bytes=bytes+n
        assert(n>0 and n<=4096 and reads<=768 and bytes<=32768,'snapshot_budget')
        local b=source(at,n)
        if not b or #b~=n then reusable=false end
        assert(b,'read_unavailable')
        assert(#b==n,'short_read')
        if guard then guards[#guards+1]={at=at,bytes=b};guarded_bytes=guarded_bytes+n else reusable=false end
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
    -- Revalidate every guarded byte. Guards on one page share one read; the
    -- construction budget above already bounds their number and size.
    -- checked() rereads memory; checked(true) may share spans read earlier
    -- in this same phase and is used only by the read-only snapshot cache.
    local checked=GuardSpans.checker(api,guards,true)
    local row={current_weapon='UNKNOWN',current_fire_mode='UNKNOWN',
        action_result='OBSERVATION_ONLY',context_status='unresolved',
        c4_guard_candidate=false,layout_evidence='STATIC_DERIVATION_PENDING_LIVE_VALIDATION'}
    local function finish(reason)
        if not checked() then return nil,'context_changed_during_read' end
        if reason~='c4_context_observed' then row.c4_guard_candidate=false end
        -- Diagnostic totals keep their meaning: every read plus every guard compared.
        row.context_status=reason;row.memory_reads=reads+#guards;row.memory_bytes=bytes+guarded_bytes
        -- The fourth value lets a cache prove this observation is still current.
        return row,nil,extension_result,reusable and checked or nil
    end
    local function extension(e)
        if not extend then return end
        -- An extension can add guarded fields, but never expose a partial
        -- capability after a failed read. finish() validates all its reads.
        local ok,result=pcall(extend,e,row)
        if ok then
            extension_result=result;row.action_context_status='validated'
        else
            extension_result=nil;row.action_context_status='rejected'
            row.action_diagnostic=tostring(result)
            row.action_context_error=row.action_diagnostic:match(':%d+: (.*)$') or row.action_diagnostic
            row.action_gate='ACTION_CONTEXT_REJECTED'
        end
    end
    local mode=read(global(R.global_mode),0x44,true)
    if u32(mode,8)==0 or u32(mode,0x40)<1 or u32(mode,0x40)>7 then
        return finish('waiting_for_mission')
    end
    local pm=global(R.global_player)
    local counts=read(pm+0x84,8,true)
    assert(u32(counts,0)<=4 and u32(counts,4)<=4,'unsupported_player_counts')
    if u32(counts,0)==0 or u32(counts,4)==0 then return finish('waiting_for_local_player') end
    local player=read(ptr(pm+0xe8,true),24,true)
    if bit.band(player:byte(21),1)==0 then return finish('local_player_not_owned') end
    local unit=u32(read(pm+0x3a8,4,true),0)
    if unit==0x7fff then return finish('waiting_for_avatar') end
    local owner=global(R.global_owner)
    local ei=lookup(owner+D.entity_unit_map,unit,1048576)
    if not ei then return finish('avatar_map_missing') end
    assert(ei<262144,'entity_index_limit')
    local entity=read(owner+D.entity_array+ei*24,24,true)
    if resource(entity)~=AVATAR or bit.band(entity:byte(21),1)==0 then
        return finish('avatar_identity_rejected')
    end
    local id=u32(entity,8)
    local avatar=global(R.global_avatar)
    local ai=lookup(avatar+0xf8,id,64)
    local n=u32(read(avatar+0x6c,4,true),0)
    assert(n<=8,'avatar_count_limit')
    if not ai or ai>=n then return finish('avatar_registry_missing') end
    if read(ptr(avatar+0x110+ai*8,true),24,true)~=entity then
        return finish('avatar_registry_mismatch')
    end
    row.local_entity_id=id;row.local_avatar_index=ai
    if scope=='routing' then
        -- UI flags also belong to ordinary-weapon and no-selected-weapon rows.
        -- The routing extension can reuse these guarded bytes for input vetoes.
        avatar_flags=read(avatar+0x53e880+ai*0x1238,24,true)
        row.tactical_map_active=AvatarFlags.has(avatar_flags,D.tactical_map)
        row.weapon_menu_active=AvatarFlags.has(avatar_flags,D.weapon_menu)
    end
    if scope=='avatar' then
        extension{read=read,ptr=ptr,global=global,lookup=lookup,
            checked=checked,u32=u32,hex=hex,resource=resource,entity=entity,
            id=id,owner=owner,avatar=avatar,avatar_index=ai}
        return finish('avatar_context_observed')
    end
    local inventory=global(R.global_inventory)
    local ii=lookup(inventory+0x28,id,65536)
    local count=u32(read(inventory+0x14,4,true),0)
    assert(count<=4096,'inventory_count_limit')
    if not ii or ii>=count then return finish('inventory_missing') end
    if read(ptr(ptr(inventory+0x40,true)+ii*8,true),24,true)~=entity then
        return finish('inventory_owner_mismatch')
    end
    local state=read(ptr(inventory+0x50,true)+ii*48,48,true)
    row.inventory_words={['12']=u32(state,12)} -- equipped backpack for reload
    if M.diagnostics then
        for i=0,11 do row.inventory_words[tostring(i*4)]=u32(state,i*4) end
    end
    local slot=u32(state,0x1c)
    row.selected_slot=slot
    local offsets={[1]=0,[2]=4,[3]=8,[4]=16,[5]=16,[6]=12}
    if not offsets[slot] then return finish('no_selected_weapon') end
    local weapon_id=u32(state,offsets[slot])
    row.selected_entity_id=weapon_id
    if weapon_id==0 or weapon_id==INVALID then return finish('selected_entity_missing') end
    local wi=lookup(owner+D.entity_id_map,weapon_id,1048576)
    if not wi then return finish('selected_entity_missing') end
    assert(wi<262144,'weapon_entity_index_limit')
    local weapon=read(owner+D.entity_array+wi*24,24,true)
    if u32(weapon,8)~=weapon_id then return finish('selected_entity_mismatch') end
    local hash=resource(weapon)
    row.current_weapon_resource=hash
    row.current_weapon=hash==DETONATOR and 'C4_DETONATOR' or hash==CHARGE and 'C4_CHARGE' or 'OTHER'
    row.weapon_owned=bit.band(weapon:byte(21),1)~=0
    row.c4_guard_candidate=hash==DETONATOR and row.weapon_owned
    -- An equipped resource must be observed live during the weapon-switch test
    -- before this candidate guard is used to authorize any action.
    if not row.c4_guard_candidate then return finish('selected_weapon_observed') end
    if scope=='selected' or scope=='routing' then
        extension{read=read,ptr=ptr,global=global,lookup=lookup,
            checked=checked,u32=u32,hex=hex,resource=resource,entity=entity,weapon=weapon,
            id=id,weapon_id=weapon_id,owner=owner,avatar=avatar,avatar_index=ai,
            avatar_flags=avatar_flags}
        return finish('c4_context_observed')
    end

    local wd=global(R.global_weapon_data)
    local di=lookup(wd+0x30,weapon_id,65536)
    local dn=u32(read(wd+0x1c,4,true),0)
    assert(dn<=4096,'weapon_data_count_limit')
    if di and di<dn then
        if read(ptr(ptr(wd+0x48,true)+di*8,true),24,true)~=weapon then
            return finish('weapon_data_owner_mismatch')
        end
        local base=ptr(wd+0x58,true)+di*D.weapon_data_stride
        local types=read(base+D.weapon_types,16,true)
        local packed=read(ptr(wd+0x60,true)+di*12,12,true)
        local flags=read(ptr(wd+0x50,true)+di*2,2,true)
        if M.diagnostics then
            row.weapon_state_12=hex(packed);row.weapon_state_flags=hex(flags)
        end
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

    -- Each 0x58-byte config contains two 40-byte ability descriptors.
    -- Presence here is evidence of configuration, not proof of callable actions.
    local templates=ptr(owner+D.ability_templates,true)
    local start=0
    for b=8,1,-1 do start=(start*256+weapon:byte(b))%D.ability_capacity end
    row.ability_template_status='absent'
    for probe=0,D.ability_capacity-1 do
        local t=read(templates+((start+probe)%D.ability_capacity)*16,16,true)
        local key=resource(t)
        if key=='0000000000000000' then break end
        if key==hash then
            local ti=u32(t,8)
            assert(ti<D.ability_capacity,'ability_template_index_limit')
            local config=read(templates+D.ability_capacity*16+ti*0x58,0x58,true)
            row.ability_template_status='present';ability_template=config
            if M.diagnostics then
                row.ability_template_hex=hex(config);row.ability_descriptors={}
                for i=0,1 do
                    local o=i*40
                    row.ability_descriptors[tostring(i)]={weapon_ability_id=u32(config,o),
                        owner_ability_id=u32(config,o+4),other_ability_id=u32(config,o+8),
                        flag_32=config:byte(o+33),flag_33=config:byte(o+34)}
                end
            end
            break
        end
    end
    if extend then
        extension{read=read,ptr=ptr,global=global,lookup=lookup,
            checked=checked,u32=u32,hex=hex,resource=resource,entity=entity,weapon=weapon,
            id=id,weapon_id=weapon_id,owner=owner,avatar=avatar,avatar_index=ai,
            weapon_data=wd,weapon_data_index=di,ability_template=ability_template}
    end
    return finish('c4_context_observed')
end
function M.snapshot(api,game,extend,scope)
    assert(scope==nil or scope=='avatar' or scope=='selected' or scope=='routing','unsupported_snapshot_scope')
    local peek=api.peek
    if not peek or not api.memo_active() then return walk(api,game,extend,scope,api.read) end
    -- Spans already read in this phase may serve the walk; finish() still
    -- rereads every guard. A failure that involved such a span is never
    -- reported: the walk is repeated once from memory alone.
    local before=api.memo_hits()
    local ok,row,reason,result,checked=pcall(walk,api,game,extend,scope,peek)
    if api.memo_hits()==before or (ok and row and row.action_context_status~='rejected') then
        if not ok then error(row,0) end
        return row,reason,result,checked
    end
    api.memo_reset()
    return walk(api,game,extend,scope,api.read)
end
-- Only readers that need these narrower observations use these entry points.
-- ActionReader retains the full snapshot and all ammunition/ability checks.
function M.avatar_snapshot(api,game,extend)return M.snapshot(api,game,extend,'avatar')end
function M.selected_snapshot(api,game,extend)return M.snapshot(api,game,extend,'selected')end
return M
