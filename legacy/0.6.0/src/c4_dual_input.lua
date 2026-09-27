-- HD2-Addon: mods/etxp/c4_boundary_probe
local ContextReader=(function()
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

end)()
local WindowsRead=(function()
-- Only OS read/hash APIs are declared. No game function pointer is invoked.
return function()
    local ffi=require('ffi')
    assert(ffi.os=='Windows' and ffi.abi('64bit'),'windows_x64_required')
    ffi.cdef [[
        void *GetModuleHandleA(const char *);
        uint32_t GetModuleFileNameW(void *,uint16_t *,uint32_t);
        void *GetCurrentProcess(void);
        int ReadProcessMemory(void *,const void *,void *,size_t,size_t *);
        uint64_t GetTickCount64(void);
        void *CreateFileW(const uint16_t *,uint32_t,uint32_t,void *,uint32_t,uint32_t,void *);
        int ReadFile(void *,void *,uint32_t,uint32_t *,void *);
        int CloseHandle(void *);
        int32_t BCryptOpenAlgorithmProvider(void **,const uint16_t *,const uint16_t *,uint32_t);
        int32_t BCryptCreateHash(void *,void **,void *,uint32_t,const void *,uint32_t,uint32_t);
        int32_t BCryptHashData(void *,const void *,uint32_t,uint32_t);
        int32_t BCryptFinishHash(void *,void *,uint32_t,uint32_t);
        int32_t BCryptDestroyHash(void *);
        int32_t BCryptCloseAlgorithmProvider(void *,uint32_t);
    ]]
    local k,b=ffi.load('kernel32'),ffi.load('bcrypt')
    local process=k.GetCurrentProcess()
    local api={}
    function api.time() return tonumber(k.GetTickCount64())/1000 end
    function api.module(name)
        local p=k.GetModuleHandleA(name)
        if p~=nil then return tonumber(ffi.cast('uintptr_t',p)) end
    end
    function api.pointer(data)
        if not data or #data<8 then return nil end
        local p=ffi.new('uintptr_t[1]')
        ffi.copy(p,data,8)
        if p[0]>=65536 and p[0]<0x800000000000 then return tonumber(p[0]) end
    end
    function api.read(address,size)
        assert(type(address)=='number' and address>=65536 and address+size<0x800000000000,'bad_read_address')
        assert(size>0 and size<=4096,'read_size_limit')
        local out,count=ffi.new('uint8_t[?]',size),ffi.new('size_t[1]')
        if k.ReadProcessMemory(process,ffi.cast('const void *',address),out,size,count)==0
            or tonumber(count[0])~=size then return nil end
        return ffi.string(out,size)
    end
    function api.module_hash(address)
        local path=ffi.new('uint16_t[32768]')
        local n=k.GetModuleFileNameW(ffi.cast('void *',address),path,32768)
        assert(n>0 and n<32768,'module_path_unavailable')
        local f=k.CreateFileW(path,0x80000000,7,nil,3,0x08000000,nil)
        assert(f~=ffi.cast('void *',-1),'module_file_unavailable')
        local algorithm,hash=ffi.new('void *[1]'),ffi.new('void *[1]')
        local ok,result=pcall(function()
            local name=ffi.new('uint16_t[7]',{83,72,65,50,53,54,0})
            assert(b.BCryptOpenAlgorithmProvider(algorithm,name,nil,0)==0,'sha256_provider')
            assert(b.BCryptCreateHash(algorithm[0],hash,nil,0,nil,0,0)==0,'sha256_create')
            local chunk,count=ffi.new('uint8_t[65536]'),ffi.new('uint32_t[1]')
            local total=0
            while true do
                assert(k.ReadFile(f,chunk,65536,count,nil)~=0,'module_file_read')
                if count[0]==0 then break end
                total=total+tonumber(count[0]);assert(total<=64*1024*1024,'module_file_size_limit')
                assert(b.BCryptHashData(hash[0],chunk,count[0],0)==0,'sha256_update')
            end
            local digest,parts=ffi.new('uint8_t[32]'),{}
            assert(b.BCryptFinishHash(hash[0],digest,32,0)==0,'sha256_finish')
            for i=0,31 do parts[#parts+1]=string.format('%02x',digest[i]) end
            return table.concat(parts)
        end)
        if hash[0]~=nil then b.BCryptDestroyHash(hash[0]) end
        if algorithm[0]~=nil then b.BCryptCloseAlgorithmProvider(algorithm[0],0) end
        k.CloseHandle(f)
        assert(ok,result)
        return result
    end
    return api
end

end)()
local FireGateWindows=(function()
-- The only EXP04 memory write: one byte of the selected, identity-checked
-- C4 Weapon flags. No executable pages, mode, ammo, or animation state writes.
return function(api)
    local ffi=require('ffi')
    assert(ffi.os=='Windows' and ffi.abi('64bit'),'windows_x64_required')
    ffi.cdef [[int WriteProcessMemory(void *,void *,const void *,size_t,size_t *);]]
    local k=ffi.load('kernel32')
    local process=k.GetCurrentProcess()
    function api.fire_gate_exchange(flags_address,before,after)
        assert(type(flags_address)=='number' and flags_address>=65536
            and flags_address+4<0x800000000000 and flags_address%4==0,'invalid_fire_gate_address')
        assert((before==0x1148 and after==0x148) or (before==0x148 and after==0x1148),
            'invalid_fire_gate_transition')
        local expected=before==0x1148 and '\72\17\0\0' or '\72\1\0\0'
        local target=after==0x1148 and '\17' or '\1'
        if api.read(flags_address,4)~=expected then return false,'fire_gate_compare_failed' end
        local count=ffi.new('size_t[1]')
        if k.WriteProcessMemory(process,ffi.cast('void *',flags_address+1),target,1,count)==0
            or tonumber(count[0])~=1 then return false,'fire_gate_write_failed' end
        local wanted=after==0x1148 and '\72\17\0\0' or '\72\1\0\0'
        return api.read(flags_address,4)==wanted,'fire_gate_readback'
    end
    return api
end

end)()
local WeaponFireGate=(function()
-- Build 24826606: 0x738be0 tests Weapon flags bit 12 before dispatching
-- the normal C4 Fire edge through 0x7cd310. EXP04 temporarily owns only
-- this bit of the exact local C4 instance; actions still use the native ABI.
local M={}
local bit=require('bit')
local NORMAL,MUTED=0x1148,0x148

function M.new(api,game,base,emit,verify)
    local self={lease=nil,active=false,status='idle',identity=nil}
    local function publish(status,extra)
        if self.status==status and not extra then return end
        self.status=status
        local fields={fire_gate_status=status,fire_gate_active=self.active,
            native_fire_route='Weapon.flags.bit12',native_aim_behavior='UNCHANGED'}
        for k,v in pairs(extra or {}) do fields[k]=v end
        assert(emit('fire_gate',fields),'fire_gate_log_unavailable')
    end
    local function current()
        return base.snapshot(api,game,function(e,row)
            local wm=e.global(0x276c390)
            local wi=assert(e.lookup(wm+0x28,e.weapon_id,65536),'fire_gate_component_missing')
            assert(wi<4096,'fire_gate_index_limit')
            assert(e.read(e.ptr(e.ptr(wm+0x40,true)+wi*8,true),24,true)==e.weapon,
                'fire_gate_registry_mismatch')
            local address=e.ptr(wm+0x50,true)+wi*40
            local flags=e.u32(e.read(address,4,true),0)
            row.weapon_driver_flags=string.format('%08x',flags)
            assert(flags==NORMAL or flags==MUTED,'fire_gate_unsupported_flags')
            -- Acquire only after vanilla Fire was released. Muting the driver
            -- while its edge latch is true would retain a stale Fire state.
            local driver=e.global(0x276c728)
            local di=assert(e.lookup(driver+0x20,e.weapon_id,65536),'fire_gate_driver_missing')
            assert(di<4096,'fire_gate_driver_index_limit')
            assert(e.read(e.ptr(e.ptr(driver+0x38,true)+di*8,true),24,true)==e.weapon,
                'fire_gate_driver_identity_mismatch')
            local held=e.read(e.ptr(driver+0x48,true)+di*8,1,true):byte()~=0
            return {weapon_id=e.weapon_id,weapon=e.weapon,owner=e.owner,manager=wm,
                address=address,flags=flags,held=held,same=e.checked,
                identity=table.concat({e.hex(e.entity),e.hex(e.weapon),tostring(e.owner)},':')}
        end)
    end
    -- Restoration must survive inventory changes and component compaction.
    -- Resolve the saved entity again instead of trusting an old state address.
    local function saved(lease)
        local guards,reads={},0
        local function read(at,n)
            assert(type(at)=='number' and at>=65536 and at+n<0x800000000000,'fire_gate_bad_address')
            reads=reads+1;assert(reads<=400 and n>0 and n<=32,'fire_gate_restore_budget')
            local b=assert(api.read(at,n),'fire_gate_restore_read_unavailable')
            assert(#b==n,'fire_gate_restore_short_read');guards[#guards+1]={at,b};return b
        end
        local function ptr(at) return assert(api.pointer(read(at,8)),'fire_gate_restore_bad_pointer') end
        local function lookup(at,key)
            local h=read(at,20);local n,empty,mult=base.u32(h,8),base.u32(h,12),base.u32(h,16)
            assert(n<=1048576 and (n==0 or bit.band(n,n-1)==0),'fire_gate_restore_map')
            if n==0 or key==empty or key==0xffffffff then return nil end
            local p=assert(api.pointer(h),'fire_gate_restore_map_pointer')
            for i=0,math.min(n,128)-1 do
                local b=read(p+((base.product_low(key,mult)+i)%n)*8,8)
                local k,index=base.u32(b,0),base.u32(b,4)
                if k==key then return index~=0xffffffff and index or nil end
                if k==empty then return nil end
            end
            error('fire_gate_restore_probe_limit')
        end
        local wm,owner=ptr(game+0x276c390),ptr(game+0x276f0c0)
        if wm~=lease.manager or owner~=lease.owner then return nil,'entity_epoch_gone' end
        local ei=lookup(owner+0xf19a70,lease.weapon_id)
        if not ei then return nil,'entity_gone' end
        assert(ei<262144,'fire_gate_restore_entity_index')
        if read(owner+0xf31ad8+ei*24,24)~=lease.weapon then return nil,'entity_reused' end
        local wi=lookup(wm+0x28,lease.weapon_id)
        if not wi then return nil,'component_gone' end
        assert(wi<4096,'fire_gate_restore_index')
        if read(ptr(ptr(wm+0x40)+wi*8),24)~=lease.weapon then return nil,'registry_reused' end
        local address=ptr(wm+0x50)+wi*40
        local flags=base.u32(read(address,4),0)
        for _,g in ipairs(guards) do assert(api.read(g[1],#g[2])==g[2],'fire_gate_restore_changed') end
        return {address=address,flags=flags}
    end
    function self.stop()
        self.active=false;self.identity=nil
        local lease=self.lease
        if not lease then return true end
        local ok,p,reason=pcall(saved,lease)
        if not ok then self.status=tostring(p);return false,self.status end
        if not p then self.lease=nil;self.status=reason;return true end
        if p.flags==MUTED then
            local restored,why=api.fire_gate_exchange(p.address,MUTED,NORMAL)
            if not restored then self.status=why;return false,why end
        elseif p.flags~=NORMAL then
            -- Do not overwrite a configuration change from the engine/mods.
            self.status='fire_gate_restore_configuration_changed';return false,self.status
        end
        self.lease=nil;self.status='restored';return true
    end
    function self.sync(enabled,released)
        self.active=false;self.identity=nil
        if not enabled and not self.lease then publish('disarmed');return false end
        local ok,row,why,plan=pcall(current)
        if not ok then why=row;row=nil end
        if not enabled or not plan then
            -- If disarming while a button is held on this C4, release the
            -- mute only after both mouse buttons are up. Do not replay it as
            -- vanilla Fire when F6/menu/focus turns routing off.
            if not enabled and plan and self.lease and plan.identity==self.lease.identity and not released then
                publish('waiting_for_mouse_release');return false
            end
            local restored,reason=self.stop();assert(restored,reason)
            publish(not enabled and 'disarmed' or row and row.action_context_error or why or 'outside_c4')
            return false
        end
        if self.lease and self.lease.identity~=plan.identity then
            local restored,reason=self.stop();assert(restored,reason)
        end
        if not self.lease then
            if plan.flags~=NORMAL then publish('preexisting_fire_gate_not_owned');return false end
            if not released or plan.held then publish('waiting_for_released_baseline');return false end
            if verify then verify() end
            -- Log intent before a data mutation, just as action calls do.
            publish('acquire',{selected_entity_id=plan.weapon_id,flags_before='00001148',flags_after='00000148'})
            assert(plan.same(),'fire_gate_acquire_context_changed')
            self.lease=plan -- retain restoration ownership even on a failed readback
            local written,reason=api.fire_gate_exchange(plan.address,NORMAL,MUTED)
            assert(written,reason)
        elseif plan.flags~=MUTED then
            error('fire_gate_changed_while_owned')
        end
        self.active=true;self.identity=plan.identity
        publish('owned');return true
    end
    function self.fields()
        return {fire_gate_active=self.active,fire_gate_status=self.status,
            fire_gate_restore_pending=self.lease~=nil and not self.active,
            native_aim_behavior='UNCHANGED'}
    end
    return self
end
return M

end)()
local MouseRouter=(function()
-- Physical mouse edges are independent of C4 mode and native Fire/Aim binds.
-- Full release is required after arming, focus or weapon identity changes.
local M={}
function M.new(emit)
    local self={identity=nil,ready=false,left=false,right=false}
    function self.sample(identity,left,right)
        local output={deploy=false,detonate=false}
        if not identity or identity~=self.identity then
            self.identity=identity;self.ready=false
        end
        if not identity then self.left=left.down;self.right=right.down;return output end
        if not self.ready then
            self.left=left.down;self.right=right.down
            if not left.down and not right.down and not left.pressed and not right.pressed then self.ready=true end
            return output
        end
        output.deploy=right.pressed and not self.right
        output.detonate=left.pressed and not self.left
        self.left=left.down;self.right=right.down
        if output.deploy and output.detonate then
            output.deploy=false
            assert(emit('simultaneous_input',{input=(left.label or 'LMB')..'+'..(right.label or 'RMB'),resolution='DETONATE_PRIORITY',
                dropped_action='DEPLOY'}),'mouse_router_log_unavailable')
        end
        return output
    end
    return self
end
return M

end)()
local ActionReader=(function()
-- EXP03. Exact C4 configuration from EXP02, plus the original eligibility data.
-- Reads only. The returned capability is private and expires after this callback.
local bit=require('bit')
local M={}
local EXPECTED='090200000000000000000000000000003482df840000000014f02aa3c6abad38010100000000000008020000000000000000000000000000926c9d6c00000000f8934147834337550001000000000000'

function M.snapshot(api,game,base)
    return base.snapshot(api,game,function(e,row)
        local read,ptr,global,lookup,u32=e.read,e.ptr,e.global,e.lookup,e.u32
        row.action_read_stage='c4_descriptors'
        assert(row.ability_template_status=='present' and
            row.ability_template_hex:sub(1,160)==EXPECTED,'unsupported_c4_descriptors')
        assert(row.weapon_data_status~='missing' and e.weapon_data_index and e.weapon_data_index~=0xffffffff,
            'weapon_data_missing')
        local types=row.weapon_function_types
        assert(types and types['0']==10 and types['1']==0 and types['2']==0 and types['3']==0,
            'unsupported_c4_function_types')
        local selector=row.weapon_function_values['0']
        assert(selector==0 or selector==1,'unsupported_c4_selector')
        row.current_fire_mode=selector==0 and 'DEPLOY' or 'DETONATE'
        row.layout_evidence='EXP02_EQUIPPED_IDENTITY_AND_DESCRIPTORS_CONFIRMED'
        local function index(manager,offset,id)
            local i=lookup(manager+offset,id,65536)
            if i then assert(i<4096,'action_component_index_limit') end
            return i
        end
        local function component(manager,map,registry,id,entity)
            local i=assert(index(manager,map,id),'action_component_missing')
            assert(read(ptr(ptr(manager+registry,true)+i*8,true),24,true)==entity,
                'action_component_identity_mismatch')
            return i
        end
        local cap={weapon_id=e.weapon_id,weapon_data=e.weapon_data,same=e.checked,
            identity=table.concat({e.hex(e.entity),e.hex(e.weapon),tostring(e.owner)},':')}
        row.action_read_stage='weapon_driver'
        cap.weapon_manager=global(0x276c390)
        local wi=component(cap.weapon_manager,0x28,0x40,e.weapon_id,e.weapon)
        local state=read(ptr(cap.weapon_manager+0x50,true)+wi*40,40,true)
        local flags=u32(state,0)
        row.weapon_driver_flags=string.format('%08x',flags)
        -- 0x73d210 checks projectile/other weapon kinds before AbilityWeapon.
        -- Ammo selection below follows 0x73cf80's ordered bit tests; requiring
        -- the exclusive 0x408 profile incorrectly rejected live EXP03 C4.
        assert(bit.band(flags,0x19)==8,'unsupported_c4_weapon_kind_flags')
        if bit.band(flags,0x80)~=0 then row.ammo_path='weapon_magazine'
        elseif bit.band(flags,0x100)~=0 then row.ammo_path='weapon_rounds'
        elseif bit.band(flags,0x400)~=0 then row.ammo_path='weapon_resource'
        elseif bit.band(flags,0x200)~=0 then row.ammo_path='weapon_heat'
        else row.ammo_path='no_native_ammo_component' end
        assert(row.ammo_path=='weapon_rounds' or row.ammo_path=='weapon_resource',
            'unsupported_c4_ammo_path')

        row.action_read_stage='ability_state'
        local driver=global(0x276c728)
        local di=component(driver,0x20,0x38,e.weapon_id,e.weapon)
        row.native_fire_held=read(ptr(driver+0x48,true)+di*8,8,true):byte(1)~=0
        cap.ability_manager=global(0x276c370)
        local bi=component(cap.ability_manager,0x18,0x30,e.weapon_id,e.weapon)
        local ability=read(ptr(cap.ability_manager+0x38,true)+bi*0xe0,32,true)
        assert(ability:byte(17)<=1,'unsupported_ability_active_flag')
        row.active_ability_id=u32(ability,0)
        row.native_action_active=ability:byte(17)~=0
        cap.active=row.native_action_active;cap.ability_id=row.active_ability_id

        -- Original 0x73ce40 -> 0x91c940: reject the same >= 2 state, if present.
        row.action_read_stage='native_weapon_gates'
        local blocked=false
        local wm=global(0x276c3b8)
        local si=index(wm,0x28,e.weapon_id)
        if si then
            row.native_block_state=u32(read(ptr(wm+0x50,true)+si*0x1b8+0x19c,4,true),0)
            blocked=row.native_block_state>=2
        end
        -- Original 0x76f3d0 -> 0x76f320. These are the native exclusion bits;
        -- their gameplay names are deliberately not inferred from bit numbers.
        local fm=global(0x276c788)
        local fi=index(fm,0x20,e.weapon_id)
        local exclusions=fi and u32(read(ptr(fm+0x50,true)+fi*4,4,true),0) or 0
        row.native_exclusion_flags=string.format('%08x',exclusions)
        blocked=blocked or (bit.band(exclusions,1)~=0 and bit.band(exclusions,2)==0)
            or (bit.band(exclusions,8)~=0 and bit.band(exclusions,16)==0)
            or (bit.band(exclusions,32)~=0 and bit.band(exclusions,64)==0)
            or bit.band(exclusions,4)~=0

        row.action_read_stage='ammo_component'
        if row.ammo_path=='weapon_rounds' then
            -- 0x73cf80 (0x73d122..0x73d1dd): the selected magazine count
            -- alone is insufficient when this weapon uses a chambered round.
            local rm=global(0x276ca00)
            local ri=component(rm,0x28,0x40,e.weapon_id,e.weapon)
            local rounds=read(ptr(rm+0x50,true)+ri*24,24,true)
            local runtime=read(ptr(rm+0x58,true)+ri*20,20,true)
            row.rounds_state_hex=e.hex(rounds);row.rounds_runtime_hex=e.hex(runtime)
            local selected=u32(runtime,4)
            row.rounds_selected_magazine=selected
            assert(selected<=1,'unsupported_rounds_magazine_index')
            row.rounds_magazine_count=u32(rounds,4+selected*4)
            row.rounds_chamber_token=u32(rounds,0x10)
            row.rounds_chamber_blocked=runtime:byte(0x11)~=0

            -- Effective settings getter 0x4f7ff0: instance override first,
            -- then the exact resource table used by leaf 0x4f7bc0.
            row.action_read_stage='rounds_configuration'
            local override=index(rm,0x68,e.weapon_id)
            local config
            if override then
                config=read(ptr(rm+0xa8,true)+override*0x84,0x84,true)
                row.rounds_config_source='entity_override'
            else
                local templates=ptr(e.owner+0xf113a8,true)
                -- Hash is uint64. Compute the remainder by bytes to avoid
                -- rounding its high bits through a Lua double.
                local start=0
                for b=8,1,-1 do start=(start*256+e.weapon:byte(b))%46 end
                for probe=0,45 do
                    local entry=read(templates+((start+probe)%46)*16,16,true)
                    local hash=e.resource(entry)
                    if hash=='0000000000000000' then break end
                    if hash==row.current_weapon_resource then
                        local ti=u32(entry,8)
                        assert(ti<46,'rounds_template_index_limit')
                        config=read(templates+0x2e0+ti*0x84,0x84,true)
                        break
                    end
                end
                row.rounds_config_source='resource_template'
            end
            assert(config,'rounds_configuration_missing')
            row.rounds_config_hex=e.hex(config)
            row.rounds_chambered=config:byte(0x69)~=0
            if row.rounds_chambered then
                row.deploy_ammo_ready=not row.rounds_chamber_blocked and row.rounds_chamber_token~=0
                row.deploy_ammo_reason=row.rounds_chamber_blocked and 'rounds_chamber_blocked' or
                    row.rounds_chamber_token==0 and 'rounds_chamber_empty' or 'rounds_chamber_ready'
            else
                -- Native setg is signed, so 0xffffffff must never pass as ammo.
                row.deploy_ammo_ready=row.rounds_magazine_count>0 and row.rounds_magazine_count<0x80000000
                row.deploy_ammo_reason=row.deploy_ammo_ready and 'rounds_magazine_ready' or 'rounds_magazine_empty'
            end
            row.ammo_available=row.rounds_magazine_count
            row.ammo_counter_source='native_rounds_selected_magazine'
            row.ammo_counter_semantics='SELECTED_MAGAZINE_ONLY_NOT_BACKPACK_OR_CHAMBER'
        else
        -- Original 0x76a1e0: resolve the resource provider, then its actual
        -- remaining counter. 0x73bf20 also counts an already deployed charge,
        -- so it MUST NOT be used as the Deploy admission check.
        local rm=global(0x276c7c0)
        local ri=component(rm,0x20,0x38,e.weapon_id,e.weapon)
        local provider=u32(read(ptr(rm+0x48,true)+ri*36,4,true),0)
        row.ammo_provider_entity_id=provider
        row.ammo_available=0
        if provider~=0 and provider~=0xffffffff and provider~=0x7fff then
            local cm=global(0x276c318)
            local ci=index(cm,0x20,provider)
            if ci then
                row.ammo_available=u32(read(ptr(cm+0x50,true)+ci*8,8,true),0)
                assert(row.ammo_available<=1024,'unsupported_ammo_counter')
                row.ammo_counter_source='native_resource_counter'
            else
                local alternate=global(0x276c448)
                local ai=index(alternate,0x20,provider)
                if ai then
                    local b=read(ptr(alternate+0x50,true)+ai*0x2c,8,true)
                    row.ammo_available=u32(b,0)~=0 and u32(b,4)~=0 and 1 or 0
                end
                row.ammo_counter_source='native_resource_boolean'
            end
        else row.ammo_counter_source='no_resource_provider' end
        row.ammo_counter_semantics='RESOURCE_PROVIDER_COUNTER_OR_BOOLEAN'
        row.deploy_ammo_ready=row.ammo_available>0
        row.deploy_ammo_reason=row.deploy_ammo_ready and 'resource_ready' or 'empty_c4_resource'
        end

        -- The EXP03 test scope is deliberately limited to the conservative
        -- local grounded state used by the same-build reference. This is an
        -- EXTRA veto, not a replacement for any C4 native eligibility rule.
        row.action_read_stage='avatar_scope'
        local av=read(e.avatar+0x53e880+e.avatar_index*0x1238,24,true)
        row.avatar_flags=e.hex(av)
        row.test_avatar_allowed=bit.band(u32(av,0),2)~=0
            and bit.band(u32(av,0),0x101000)==0 and bit.band(u32(av,4),0x81000000)==0
            and bit.band(u32(av,8),0xc4010800)==0 and bit.band(u32(av,12),0x2000a347)==0
            and bit.band(u32(av,16),1)==0
        cap.interrupt=not row.test_avatar_allowed or row.native_fire_held
        cap.blocked=blocked or cap.interrupt
        cap.deploy_ready=row.deploy_ammo_ready
        row.action_gate=blocked and 'NATIVE_WEAPON_BLOCKED' or
            not row.test_avatar_allowed and 'OUTSIDE_EXP03_AVATAR_SCOPE' or
            row.native_fire_held and 'ORIGINAL_FIRE_ACTIVE' or
            cap.active and 'NATIVE_ACTION_ACTIVE' or 'READY'
        row.action_read_stage='complete'
        return cap
    end)
end
return M

end)()
local ActionBackend=(function()
-- Native calls are restricted to the original weapon driver sequence.
local M={}
function M.new(api,reader,base,layout,bind)
    local game=assert(api.module('game.dll'),'game_module_missing')
    assert(api.module_hash(game)==layout.module_sha256,'unsupported_game_module_hash')
    local signatures={}
    for _,s in ipairs(layout.signatures) do
        local bytes=s.hex:gsub('..',function(h) return string.char(tonumber(h,16)) end)
        assert(api.read(game+s.rva,#bytes)==bytes,string.format('unsupported_live_action_code_%08x',s.rva))
        signatures[#signatures+1]={rva=s.rva,bytes=bytes}
    end
    local native=bind(game)
    local self={}
    function self.verify()
        for _,s in ipairs(signatures) do
            assert(api.read(game+s.rva,#s.bytes)==s.bytes,string.format('action_code_changed_%08x',s.rva))
        end
    end
    function self.snapshot()
        local row,reason,cap=reader.snapshot(api,game,base)
        if not row then return nil,reason end
        return row,nil,cap
    end
    function self.execute(action,cap)
        assert(action=='DEPLOY' or action=='DETONATE','unsupported_action')
        assert(cap and not cap.active and not cap.blocked,'ineligible_action_capability')
        assert(action~='DEPLOY' or cap.deploy_ready==true,'native_deploy_ammo_not_ready')
        -- Verify all guarded code again on each request; no native mutation
        -- occurs if another mod patched these functions after initialization.
        self.verify()
        assert(cap.same(),'action_context_changed')
        local id=action=='DEPLOY' and 521 or 520
        -- Fifth argument is 1.0, loaded by 0x7cd36b from RVA 0x211c5b0.
        -- It is not 0.0. R9D=1 retains the original local/network path.
        native.start(cap.ability_manager,cap.weapon_id,id,1,1.0)
        if action=='DEPLOY' then
            native.consume(cap.weapon_manager,cap.weapon_id)
            local count=native.count(cap.weapon_manager,cap.weapon_id)
            native.after(cap.weapon_data,cap.weapon_id,count,true)
        end
        return id
    end
    return self
end
return M

end)()
local NativeActions=(function()
-- Windows x64 ABI, verified against 0x7cd310's original call sites.
-- No code patch, mode write, input injection, or direct spawn/explosion call.
return function(game)
    local ffi=require('ffi')
    assert(ffi.os=='Windows' and ffi.abi('64bit'),'windows_x64_required')
    local start=ffi.cast('void (*)(void *, uint32_t, uint32_t, uint32_t, float)',game+0x7c21a0)
    local consume=ffi.cast('void (*)(void *, uint32_t)',game+0x73ca00)
    local count=ffi.cast('int32_t (*)(void *, uint32_t)',game+0x73bf20)
    local after=ffi.cast('void (*)(void *, uint32_t, int32_t, bool)',game+0x74b220)
    return {
        start=function(manager,id,ability,network,speed)
            start(ffi.cast('void *',manager),id,ability,network,speed)
        end,
        consume=function(manager,id) consume(ffi.cast('void *',manager),id) end,
        count=function(manager,id) return tonumber(count(ffi.cast('void *',manager),id)) end,
        after=function(manager,id,n,enabled) after(ffi.cast('void *',manager),id,n,enabled) end
    }
end

end)()
local ActionController=(function()
-- Test-key routing, independent of FFI and native layout.
-- Native active -> inactive is an observed lifecycle end, NOT gameplay success.
local M={}
function M.new(backend,emit,options)
    options=options or {}
    local labels={DEPLOY=options.deploy_input or 'F8',DETONATE=options.detonate_input or 'F9'}
    local self={latest={},last_sample=-math.huge,last_emit=-math.huge,lock=nil,pending=nil,
        fault=nil,serial=0,was_armed=false,last_key=nil}
    local function publish(kind,extra)
        local fields={action_lock=self.lock and self.lock.action or 'IDLE',
            pending_action=self.pending and self.pending.action or 'NONE'}
        for k,v in pairs(extra or {}) do fields[k]=v end
        assert(emit(kind,fields),'action_log_unavailable')
    end
    local function drop_pending(reason)
        if self.pending then
            local old=self.pending;self.pending=nil
            publish('pending_dropped',{requested_action=old.action,reason=reason})
        end
    end
    local function abandon(reason)
        drop_pending(reason)
        if self.lock then
            local old=self.lock;self.lock=nil
            publish('action_observation_ended',{requested_action=old.action,request_id=old.id,
                action_result='COMPLETION_UNKNOWN',reason=reason})
        end
    end
    local function observe(now)
        local ok,row,reason,cap=pcall(backend.snapshot)
        if not ok then reason=row;row=nil end
        if not row then row={context_status='snapshot_unavailable',current_weapon='UNKNOWN',
            current_fire_mode='UNKNOWN',reason=tostring(reason)} end
        self.latest=row;self.last_sample=now
        local key=table.concat({row.context_status,tostring(row.selected_entity_id),
            tostring(row.current_fire_mode),tostring(row.action_gate),tostring(row.active_ability_id),
            tostring(row.native_action_active),tostring(row.ammo_available),tostring(row.deploy_ammo_ready),
            tostring(row.weapon_driver_flags),tostring(row.ammo_path),tostring(row.action_context_error),
            tostring(row.action_read_stage),tostring(row.reason)},'|')
        if key~=self.last_key or now-self.last_emit>=1000 then
            publish('action_context');self.last_key=key;self.last_emit=now
        end
        return cap
    end
    function self.fields(now)
        local row={}
        for k,v in pairs(self.latest) do row[k]=v end
        row.context_sample_age_ms=now-self.last_sample
        row.action_lock=self.lock and self.lock.action or 'IDLE'
        row.pending_action=self.pending and self.pending.action or 'NONE'
        row.action_fault=self.fault or 'NONE'
        return row
    end
    local function reject(action,reason)
        publish('action_rejected',{requested_action=action,reason=reason,action_result='NOT_EXECUTED'})
    end
    local function unavailable_reason()
        return self.latest.action_context_error or self.latest.reason or 'no_fresh_c4_context'
    end
    local function execute(action,now,cap,from_pending,request_input)
        if not cap then reject(action,unavailable_reason());return end
        if cap.blocked then reject(action,self.latest.action_gate);return end
        if cap.active then reject(action,'native_action_busy');return end
        if action=='DEPLOY' and not cap.deploy_ready then
            reject(action,self.latest.deploy_ammo_reason or 'native_deploy_ammo_not_ready');return
        end
        self.serial=self.serial+1
        local lock={action=action,id=self.serial,identity=cap.identity,start=now,
            ability=action=='DEPLOY' and 521 or 520,saw_active=false,mode=self.latest.current_fire_mode}
        self.lock=lock
        -- This record must reach the file before any native side effect.
        publish('action_call',{requested_action=action,request_id=lock.id,
            action_result='CALL_BEGIN',ability_id=lock.ability,
            input=from_pending and 'PENDING' or request_input or labels[action],
            original_input=request_input or labels[action]})
        local ok,result=pcall(backend.execute,action,cap)
        if not ok then
            self.fault=tostring(result);drop_pending('native_call_error')
            publish('action_fault',{requested_action=action,request_id=lock.id,
                action_result='OUTCOME_UNKNOWN',reason=self.fault})
            return
        end
        publish('action_returned',{requested_action=action,executed_action=action,
            request_id=lock.id,ability_id=result,action_result='NATIVE_CALL_RETURNED'})
        local post=observe(now)
        if not post or post.identity~=lock.identity or not post.active or post.ability_id~=lock.ability then
            self.fault='native_start_not_observed';drop_pending(self.fault)
            publish('action_fault',{requested_action=action,request_id=lock.id,
                action_result='START_UNCONFIRMED',reason=self.fault})
            return
        end
        lock.saw_active=true
        publish('action_started',{requested_action=action,executed_action=action,
            request_id=lock.id,action_result='NATIVE_ACTIVE_OBSERVED',fire_mode_before=lock.mode,
            fire_mode_after=self.latest.current_fire_mode,
            fire_mode_unchanged=lock.mode==self.latest.current_fire_mode})
        if lock.mode~=self.latest.current_fire_mode then
            self.fault='fire_mode_changed_during_native_call'
            publish('action_fault',{requested_action=action,request_id=lock.id,
                action_result='MODE_CHANGE_OBSERVED',reason=self.fault})
        end
    end
    function self.step(armed,now,input)
        input=input or {}
        if not armed or not input.allowed then
            abandon(not armed and 'capture_off' or 'focus_or_controls_blocked')
            self.was_armed=false;self.last_sample=-math.huge
            self.latest={context_status='actions_disarmed',current_weapon='UNKNOWN',current_fire_mode='UNKNOWN'}
            return
        end
        local request=input.deploy and input.detonate and 'BOTH' or
            input.deploy and 'DEPLOY' or input.detonate and 'DETONATE' or nil
        local request_input=request=='DEPLOY' and input.deploy_input or
            request=='DETONATE' and input.detonate_input or nil
        -- Require a full released baseline on arming. A key held before F6
        -- cannot become an action, even if a device repeats pressed flags.
        if not self.was_armed then
            self.was_armed=true;observe(now)
            if request then reject(request,'arming_baseline') end
            return
        end
        if self.fault then if request then reject(request,'fault_latched_restart_required') end;return end
        if input.mouse then
            drop_pending('original_mouse_input')
            if request then reject(request,'original_mouse_input') end
            request=nil
        end
        if not request and now-self.last_sample<50 then return end
        local cap=observe(now)
        if not cap then
            abandon('c4_context_unavailable')
            if request then reject(request,unavailable_reason()) end
            return
        end
        if self.lock then
            local lock=self.lock
            if cap.identity~=lock.identity then abandon('weapon_or_avatar_changed')
            elseif cap.active and cap.ability_id~=lock.ability then abandon('native_action_replaced')
            elseif not cap.active and lock.saw_active then
                self.lock=nil
                publish('action_finished',{requested_action=lock.action,request_id=lock.id,
                    action_result='NATIVE_LIFECYCLE_ENDED',gameplay_result='REQUIRES_VISUAL_CONFIRMATION'})
            elseif now-lock.start>=8000 then
                self.fault='native_completion_timeout';drop_pending(self.fault)
                publish('action_fault',{requested_action=lock.action,request_id=lock.id,
                    action_result='COMPLETION_UNKNOWN',reason=self.fault})
                return
            end
        end
        if self.pending and now-self.pending.at>1500 then drop_pending('pending_expired') end
        if cap.interrupt or input.mouse or (cap.blocked and not self.lock) then
            drop_pending('controls_or_native_state_blocked')
            if request then reject(request,'controls_or_native_state_blocked') end
            return
        end
        if request=='BOTH' then
            reject(request,'simultaneous_test_keys_rejected');return
        end
        if self.pending and not self.lock then
            local p=self.pending
            -- Live EXP03.1: native action ends before the next chamber is
            -- ready. Preserve the one queued Deploy across that short native
            -- refill window, retaining its ORIGINAL deadline and identity.
            -- Never wait behind an unrelated active action or bypass ammo.
            if p.identity==cap.identity and not cap.active and p.action=='DEPLOY'
                and not cap.deploy_ready and self.latest.deploy_ammo_reason=='rounds_chamber_blocked' then
                if not p.waiting_ammo then
                    p.waiting_ammo=true
                    publish('pending_waiting',{requested_action=p.action,
                        reason='native_chamber_not_ready',action_result='PENDING_ONE'})
                end
                if request then
                    reject(request,p.action==request and 'pending_coalesced' or 'pending_slot_full')
                end
                return
            end
            self.pending=nil
            if p.identity==cap.identity then
                execute(p.action,now,cap,true,p.input)
                if request then reject(request,'pending_dispatched_this_callback') end
                return
            end
            publish('pending_dropped',{requested_action=p.action,reason='identity_changed'})
        end
        if not request then return end
        publish('action_request',{requested_action=request,action_result='REQUESTED',
            input=request_input or labels[request]})
        if self.lock then
            if not self.pending then
                self.pending={action=request,at=now,identity=cap.identity,input=request_input or labels[request]}
                publish('action_queued',{requested_action=request,action_result='PENDING_ONE'})
            else
                reject(request,self.pending.action==request and 'pending_coalesced' or 'pending_slot_full')
            end
            return
        end
        execute(request,now,cap,false,request_input)
    end
    return self
end
return M

end)()
local WindowFocus=(function()
-- Foreground ownership only; does not read or synthesize OS input events.
return function()
    local ffi=require('ffi')
    ffi.cdef [[
        uint32_t GetCurrentProcessId(void);
        void *GetForegroundWindow(void);
        uint32_t GetWindowThreadProcessId(void *,uint32_t *);
    ]]
    local k,u=ffi.load('kernel32'),ffi.load('user32')
    local pid=k.GetCurrentProcessId()
    return function()
        local window=u.GetForegroundWindow()
        if window==nil then return false end
        local owner=ffi.new('uint32_t[1]')
        return u.GetWindowThreadProcessId(window,owner)~=0 and owner[0]==pid
    end
end

end)()
local ActionLayout={module_sha256="cc75948d90fdfde259dcb519e9933db7ffa3ccb281ce4fb89e6b1b011557470c",signatures={{rva=10080800,hex="41564883ec20443b05339ade014c8bf24c8b1531f2dc01750841b8ffffffffeb"},{rva=10115776,hex="4585c9745d418bc04c8d044049c1e004418d41ff4c03415083f80577454c8d0d"},{rva=13887696,hex="4883ec083b0d7a8ca4010f849b0000004c8b15d907a3014533c048895c241048"},{rva=5278688,hex="4885c9744c488b05d4642602448bc14183e00f4533c94c8b908818f1000f1f00"},{rva=8180288,hex="48895c240848896c24104889742418574883ec203b151a9afb017454488b05c5"},{rva=7657984,hex="48895c241048896c2418488974242057415641574883ec20448b154192030245"},{rva=8135072,hex="4c8bdc49895b18555657415541564881ecb0000000488b05541ebd014833c448898424900000003b15934afc01458be94d897b108bda410f2973c8458bf84489442430488bf1744d448b4120448b492833c9440fafcb418d78ff4585c074364c8b5618448b5e24660f1f8400000000008bc7428d14094823d0418b04d2413bc30f84ea0000003bc30f84ea000000ffc1413bc872dbb8ffffffff488b6e38f30f10b42400010000448bf04969fee00000004183fd027414488b46304a8b0cf0f6411401741a4183fd0175140f28de458bc78bd348c7c1feffffffe8e1b14000807c2f10000f84c4000000f30f10442f08f30f5905e0ac95010f5ac0e818456901488b4e308b142ff24c0f2cc04a8b0cf1e8eb0a70003b1da549fc010f848d0000004c8b1530a8fa0133c94c89a424e0000000458b4250458b4a58440fafcb458d60ff4585c0745f4d8b5a48458b7a5490418bc4428d14094823d0418b04d3413bc7741f3bc3741fffc1413bc872e2eb363bc30f851dffffff418b44d204e918ffffff3bc3752041837cd304ff74184533c944896c242041b857512b868bd3498bcae8bad603004c8ba424e00000008b5c243033c00f57c9f30f11742f0c891c2f4533ed4c896c2f044533c0c7442f14ffffffff8bd3c6442f10014c896c2f18488944244048894424480f104424400f11442f300f114c2f400f114c2f50488b4e304a8b0cf1e866216f000f28b424a00000004c8bbc24e800000084c0747a3b1c2f7575488b4e304533c08bd34a8b0cf1e8cb097000488b4e380f57c033c04489ac248000000048898424840000008b8424880000000f11840f9000000044886c0f100f11840fa000000044896c0f140f11840fb00000000f11840fc0000000f20f10842480000000f20f11840fd000000089840fd8000000488b8c24900000004833cce8683c6101488b9c24f00000004881c4b0000000415e415d5f5e5dc3"},{rva=7588352,hex="48894c240853555657415541574883ec388b3d49a204024533ff4c8b2d6ff902028bda3bd77451458b4530418bd7458b5538440fafd3418d68ff4585c074394d8b5d28418b7534660f1f8400000000008bc5428d0c124823c8418b04cb4d8d0ccb3bc60f84e10000003bc30f84e1000000ffc2413bd072d8beffffffff8bc648894424204c896424784c89742430488d0c80498b4550488d04c848894424708b0084c00f895d010000498b4540448be64e8b24e0498bcce80422dbff488b2db5f802024c8bf83bdf7447448b452833d2448b5530440fafd3458d70ff4585c074304c8b5d208b7d2c0f1f840000000000418bc6428d0c124823c8418b04cb4d8d0ccb3bc774553bc37455ffc2413bd072dfb9ffffffff8bf9448bf1498bcc48c1e70448037d48e80534ddff4180bf9c00000000488bc8743f8b0785c07439837f040075218b0132d2eb313bc30f8526ffffff418b7104e922ffffff3bc375b2418b4904ebb1ffc899f77f0c4863c232d2418b448704eb04b20133c08947084180bf9c00000000740485c07402ff0f83feff0f8471020000498b45408bce488b0cc8f64114010f845d0200004180bf9c00000000743984d274354b8d0476ba743e894a488d0c8500000000488b4550c6440108014c8b4550488b45384983c0084c03c14a8b0cf08b4910e882176000448b078bd3e8d8920200488b442470c6402000e9020200000fbae0080f83be010000498b45408bce488b04c8488bc84889842480000000e8c6b3dbff488b2dcffd020248898424880000003bdf744c448b4530418bd7448b5538440fafd3458d70ff4585c074344c8b5d288b7d340f1f4000418bc6428d0c124823c8418b04cb4d8d0ccb3bc70f84ad0000003bc30f84ad000000ffc2413bd072d7b9ffffffff488b45504c8b7558448be14b8d0c64488d3cc84b8d04a44c8d0485000000004d03f04c8944247083feff7440488b842480000000f640140174328bd3488bcde88e63030084c0741f49634604837c87040075148b470841b801000000034704450fb6ff450f45f84c8b442470488b942488000000807a6800743849634e04837c8f0400742d4532c985c9741e83f901752b8b4244894710eb233bc30f855affffff418b4904e956ffffff8b4240894710eb0ac747100000000041b101807a68007406837f1000740849634604ff4c870483feff0f84a1000000498b45408bce488b0cc8f64114010f848d000000807a6800742f4584c9742a488b4558ba743e894a41c644001001488b45584883c0104c03c0488b45404a8b0ce08b4910e8c0156000496346048bd3448b448704e8605503004584ff74438bd3e8544c0300eb3a0fbae00a733483feff742f498b45408bce488b0cc8f6411401741f488b0dd0f902028bd3e8e9d3020085c0740d41b8010000008bd3e898d20200498b45404533c9488b4c242041b86e992b07488b0cc88b51084c8b7424304c8b6424784883c438415f415d5f5e5d5be9a4546000"},{rva=7585568,hex="48895c24205556574883ec203b152ead04028bda4c8bc97443448b413033f6448b51388bd6440fafd3418d68ff4585c0742a4c8b59288b79340f1f80000000008bc5428d0c124823c8418b04cb3bc7741a3bc3741affc2413bd072e433c0488b5c24584883c4205f5e5dc33bc375ed418b44cb0483f8ff74e3498b4940488d3c804c897424404d8b7150488b0cc1e88d89dcff4885c074204038b0a80300007417b8010000004c8b742440488b5c24584883c4205f5e5dc3418b04fe8bee0fbae00973764c8b156d0a03028bce458b4230458b4a38440fafcb418d68ff4585c0742a4d8b5a28418b7a34660f1f4400008bc5428d14094823d0418b04d33bc7742e3bc3742effc1413bc872e4b8ffffffff8bc8498b4258488d1449f30f10449004e822a87101f30f2ce8e9250100003bc375d9418b44d304ebd784c079784c8b15130303028bce458b4228458b4a30440fafcb418d68ff4585c074304d8b5a20418b7a2c0f1f40000f1f8400000000008bc5428d14094823d0418b04d33bc7742a3bc3742affc1413bc872e4b8ffffffff8bc848c1e10449034a488b013971088d68010f44e8e9a90000003bc375dd418b44d304ebdb0fbae0080f837e0000004c8b0d190903028bce458b4130458b5138440fafd3418d68ff4585c0742e4d8b5928418b793466660f1f8400000000008bc5428d14114823d0418b04d33bc774323bc37432ffc1413bc872e4b8ffffffff448bc0498b41584b8d0c8048635488044b8d0440488d0c42498b41508b6c8804eb213bc375d5418b44d304ebd30fbae00a7310488b0d550603028bd3e86ee002008be88b3dfaaa04023bdf0f84d70000004c8b0d970303028bce4c897c2450458b4128458b5130440fafd3458d78ff4585c00f84ab0000004d8b5920458b712c418bc7428d14114823d0418b04d3413bc674173bc37417ffc1413bc872e24c8b7c24508bc5e9ebfdffff3bc3757541837cd304ff746d458b5130458d70ff440fafd3418bd04585c074594d8bc3458b592c418bc6428d0c164823c8418b04c8413bc374163bc37416ffc63bf272e34c8b7c24508bc5e99bfdffff3bc37525418b44c80483f8ff741b8bc8498b41488b14c8488d4c2448e8e4246000397c24487402ffc54c8b7c24508bc5e966fdffff"},{rva=7647776,hex="48895c241048896c241856574154415641574881ec90000000488b05d08dc4014833c44889442470488b3da11702024533e43b1508ba03028bea4c89ac24c000000044884c2430448944243448897c24407457448b4738418bcc448b4f40440fafcd418d58ff4585c0743f4c8b5730448b5f3c0f1f4000660f1f8400000000008bc3428d14094823d0beffffffff418b04d2413bc30f84d20100003bc50f84d2010000ffc1413bc872d6beffffffff448bf6488b4748418bce488b1cc8488bcb48895c24388b7b0ce85396dbff4c8be84439a0e001000074738bd50f29b42480000000e8786b0200488b0d110d02020f28f0488b51188bcf4c8b82b8030000418b95e001000041ffd085c07437488b05ec0c0202418b95e0010000488b4818488b81b00300008b4b0cffd0488b0dce0c02020f28d68bd04c8b41188bcf41ff90d00300000f28b42480000000498d9de801000041bf080000000f1f80000000008b05b2e134024c8d4c24500f1005fe98c4014c8bc3488b0d2c3d0202f20f100d8ce134028bd789442458488d442460660f7f4424604889442420f20f114c2450e81bfad7004883c3304983ef0175b1458bfc4d8da5680300000f1f8000000000418b1c2485db7458488b05310c02028bd3488b4818488b81d00600008bcfffd084c0743c488b05150c02028bd3488b4818488b81d80600008bcfffd0488b0dfd0b02024d8d856c0300008bd04c8b4918418bcf48c1e1044c03c18bcf41ff515841ffc74983c4104183ff027293807c2430000f840f010000837c2434007540418b958c03000085d27435488b05af0b0202488b4818488b81500300008bcfffd085c0745b418b958c030000eb3e3bc50f853afeffff458b74d204e933feffff418b958803000085d27435488b056f0b0202488b4818488b81500300008bcfffd085c0741b418b9588030000488b054e0b02028bcf4c8b401841ff90700300004183bd90030000004c8b6424387470418b4424083b0567b703027463488b0d5e0f020233d2448b4920448b5128440fafd0418d79ff4585c974454c8b59188b59248bcf458d04124c23c1438b0cc33bcb74143bc87414ffc2413bd172e48bcde84d324000eb273bc87515433974c304740e458b85900300008bd0e8527a04008bcde82b324000eb054c8b6424383b2deeb603024c8b0de70e02027441458b412033c9458b5128440fafd5418d78ff4585c0742a4d8b5918418b5924660f1f4400008bc7418d140a4823d0418b04d33bc374453bc57445ffc1413bc872e48b1db2b60302418bbd9c0300008bd5e8c02f0000418b4c2408ba08000000448bf8e8aed1d80083f8017527418b8da403000085c9741c8bf9eb313bc575c2418b44d3043bc674b98bc8498b41388b1c88ebb44183ff077513418b85a003000085c07408807c2430000f45f83b1d47b603024c8bac24c0000000742985ff7425f30f10056d0f9d014533c9418b542408448bc7488b0d1b0d0202f30f11442420e8406b0700443bf60f84d70100004c8b7c2440418bce498b4748488b0cc8f64114010f84bd010000837c2434000f85b20100003b1dccb503020f84a6010000488b3d8f1302024533e4418bcc448b8700010000448b8f08010000440fafcb458d70ff4585c00f847a0100004c8b97f8000000448b9f040100000f1f40000f1f840000000000418bc6418d14094823d0418b04d2413bc374103bc37414ffc1413bc872e2e93d0100003bc30f8535010000413974d2040f842a010000448b8f08010000458d70ff440fafcb418bcc4585c074210f1f00418bc6418d14094823d0418b04d2413bc3747d3bc3747dffc1413bc872e28bc68bc84869c138120000488d8fb4dc53004803c8e8d83a2e0084c00f85d0000000448b8700010000418bcc448b8f08010000440fafcb458d70ff4585c074464c8b97f8000000448b9f040100000f1f4000418bc6418d14094823d0418b04d2413bc374183bc37418ffc1413bc872e2eb143bc3758a418b44d204eb853bc37505418b74d2044533db8bc64c69c0381200000f57c066490f7ec2660f73d80866480f7ec0490fbaea2d4983e2fe498b8c3888e853004d8b8c3890e853004823c8483bc8498bc20f94c24923843880e85300493bc20f94c022d04d23cb0fb6c2440f44e04584e4750a8bd5498bcfe830000000488b4c24704833cce863a868014c8d9c2490000000498b5b38498b6b40498be3415f415e415c5f5ec3"},{rva=8180496,hex="48894c24085641544883ec688bf2e81dffffff4c8be04885c00f84b801000048899c2488000000488d94249000000048896c2460448bc648897c24584c896c24500f29742430e8a564dbff8b9c24900000004032ed8b3df598fb01f30f10353df294014c8b2df6eff9014088ac24800000003bdf0f84cd000000458b4520458b4d284c897424484533f6440fafcb418bce418d68ff4585c0743b4d8b5518458b5d240f1f400066660f1f8400000000008bc5428d14094823d0418b04d2413bc30f84190100003bc30f8419010000ffc1413bc872db4032ed3bdf74664c8b1d95f6f901418bce4c897c2440458b4328458b4b30440fafcb458d78ff4585c0743d4d8b5320418b6b2c0f1f840000000000418bc7428d14094823d0418b04d23bc50f84260100003bc30f8426010000ffc1413bc872db0fb6ac24800000004c8b7c24404c8b742448418b1c24488b7c245885db742f41807c242100750b8bd6e8fd1dcdff84c0741c41b901000000f30f11742420448bc38bd6498bcde8104dffff40b50141807c2420000f287424304c8b6c2450488b9c248800000074354084ed7430488b0dd7eef9018bd6e840f5f6ff488b0dc9eef9018bd6e852eaf6ff488b0d1bf5f90141b101448bc08bd6e83eddf7ff488b6c24604883c468415c5ec33bc30f85eefeffff41837cd204ff0f84e2feffff418b6c240485ed0f84d5feffff4538742421750f8bd3e8521dcdff84c00f84bffeffff41b901000000f30f11742420448bc58bd3498bcde8614cffff4c8b2d2aeef90140b5018b3d1197fb014088ac2480000000e98cfeffff3bc30f85e1feffff41837cd204ff0f84d5feffff45397424080f84cafeffff458b5330458d78ff440fafd3418bce4585c074364d8b4b200f1f4000660f1f840000000000418bc7428d14114823d0418b04d13bc50f847c0000003bc30f8478000000ffc1413bc872dbb8ffffffff8bc8498b434848c1e1068b1c013bdf0f8466feffff488b05b2f4f901418bce448b4028448b4830440fafcb418d78ff4585c00f8443feffff4c8b5020448b582c660f1f4400008bc7428d14094823d0418b04d2413bc3741b3bc3741fffc1413bc872e3e913feffff3bc3758f418b44d104eb8d3bc30f8500feffff41837cd204ff0f84f4fdffff418b5520458b4528440fafc3448d5aff85d20f84dcfdffff4d8b4d18458b5524418bc3438d0c064823c8418b04c9413bc274113bc3741541ffc6443bf272e1e9b0fdffff3bc30f85a8fdffff41837cc904ff0f849cfdffff41807c242100750f8bd3e8b81bcdff84c00f8485fdffff458b44240841b9010000008bd3f30f11742420498bcde8c54affff4c8b2d8eecf90140b501e963fdffff"},{rva=7589440,hex="48895c240848896c2410488974241848897c242041564883ec203b15009e04028bda488bf97449448b49304533c0448b5938418bd0440fafdb458d71ff4585c9742e488b71288b69340f1f8000000000418bc6428d0c1a4823c88b04ce4c8d14ce3bc574283bc37428ffc2413bd172e032c0488b5c2430488b6c2438488b742440488b7c24484883c420415ec33bc375df41837a04ff74d84c8b15d9f40202418b5230458b5a38440fafdb448d72ff85d2744d498b7228418b6a340f1f440000418bc6438d0c184823c88b04ce4c8d0cce3bc5740e3bc3740e41ffc0443bc272dfeb1d3bc3751941837904ff74128bd3498bcae808fa1d0084c00f8570ffffff8bd3e88924030084c00f8561ffffff488bcfe82900000084c00f8451ffffff8bd3488bcfe8a702000084c00f843fffffffb001e93affffff"},{rva=7589760,hex="48895c241848896c2420565741564883ec208bda33f68b15c49c04024c8bd93bda7509bfffffffff8bc7eb75448b4930448bc68b69384c896424400fafeb4c897c2448458d61ff4585c974444c8b7128448b79340f1f40000f1f840000000000418bc4418d0c284823c8bfffffffff418b04ce4d8d14ce413bc70f84b30000003bc30f84b300000041ffc0453bc172d0bfffffffff8bc74c8b6424404c8b7c24488bc8498b43504c8d04894e8d34c0428b04c0a80874238bd3e8020209004885c00f8475010000403870200f846b010000418b068b15069c040284c00f89b6000000488b2d0ff302023bda745f8b5528448b4d30440fafcb448d72ff85d2744c4c8b5520448b5d2c0f1f840000000000418bc6428d0c0e4823c8418b04ca4d8d04ca413bc3741d3bc3741dffc63bf272dfeb193bc30f855affffff418b4204e953ffffff3bc37504418b7804488b4d38488bdf48c1e30448035d48488b0cf9e8dc1bdbff80b89c000000007420488b4550488d0c7f807c880800750a837b08000f85b600000032c0e9b1000000833b000f9fc0e9a60000000fbae0080f83bd0000004c8b0dd7f802023bda744d418b5130458b5138440fafd3448d72ff85d274394d8b5928418b69340f1f8000000000418bc6428d0c164823c8418b04cb4d8d04cb3bc5740c3bc3740cffc63bf272e0eb083bc37504418b7804498b4150498b4940448bc74a8b0cc14b8d1440488d1cd0498b41584b8d1480488d3c90e84eaedbff807868007429807f10000f8554ffffff837b10000f844affffffb001488b5c2450488b6c24584883c420415e5f5ec348634704837c8304000f9fc0ebdf0fbae00a7315488b0dd4f502028bd3e8edcf020085c00f95c0ebc40fbae00973bc8bd3e809f90100ebb5"},{rva=7590416,hex="48895c241048896c2418565741564883ec20448b0d379a04024533d2488bf9413bd1750ab8ffffffff448bc0eb56448b5930458bc28b71380faff24c897c2440458d7bff4585db742e4c8b71288b6934418bc7418d0c304823c8b8ffffffff498d1cce418b0cce3bcd74793bca747941ffc0453bc372d9b8ffffffff448bc04c8b7c2440418bc84c8d0489488b4f50468b1cc141f6c3017479488b1d58f10202413bd17451448b4b588b7b600faffa458d71ff4585c9743e488b73508b6b5c90418bce458d043a4c23c1428b0cc64e8d1cc63bcd74183bca741841ffc2453bd172deeb123bca7594448b4304eb913bca7504418b43048bc8488b43784c69c1a8000000458b44003ce883140100e98000000041f6c310746b3b1546990402488b1df3f502027446448b4b508b7b580faffa458d71ff4585c97433488b73488b6b54418bce458d043a4c23c1428b0cc64e8d1cc63bcd740e3bca740e41ffc2453bd172deeb083bca7504418b43048bc8488b43704c8d0489468b44c004e80f140100eb0f41f6c3087407e8a2040900eb02b001488b5c2448488b6c24504883c420415e5f5ec3"},{rva=8181824,hex="48895c241048896c2418565741564883ec208b051c94fb01488b1dc9eef9013bd0744f448b5b284533d28b7b30458bca0faffa458d73ff4585db7436488b73208b6b2c0f1f4000660f1f840000000000418bce458d04394c23c1428b0cc64e8d04c63bcd74213bca742141ffc1453bcb72de32c0488b5c2448488b6c24504883c420415e5f5ec33bca75e7418b480483f9ff74de448bc1488b4b384e8b0cc148b9193971f099a17e554939090f85150100008b0d6893fb01488b3d61ebf9013bd1746d8b5f20458bda8b77280faff24c897c2440448d7bff85db744f4c8b77188b6f240f1f4000660f1f840000000000458bc7458d0c334d23c8478b04ce4f8d0cce443bc5740f443bc2740f41ffc3443bdb72dceb15443bc27510418b510483faff7407488b47388b04904c8b7c24403b051693fb010f8436ffffff3bc10f842effffff488b0da5f0f901448b8900010000448b9908010000440fafd8418d71ff4585c90f8408ffffff488b99f80000008bb904010000660f1f8400000000008bce438d141a4823d18b0cd34c8d04d33bcf74113bc8741541ffc2453bd172e0e9cdfeffff3bc80f85c5feffff41837804ff0f84bafeffff8bd0e8a1f0140084c00f84abfeffffb001e9a6feffff"},{rva=9554240,hex="48895c240848896c2410488974241848897c24203b1506a3e6014c8bd17441448b49304533c08b59380fafda418d69ff4585c9742b488b79288b71340f1f40008bc5418d0c184823c88b04cf4c8d1ccf3bc674233bc2742341ffc0453bc172e032c0488b5c2408488b6c2410488b742418488b7c2420c33bc275e5418b430483f8ff74dc4869c8b8010000498b425083bc019c010000020f93c0ebc6"},{rva=7795664,hex="40534883ec20488b1dabd3ff0141b801000000488bcbe835ffffff84c0741241b802000000488bcbe823ffffff84c0745a41b808000000488bcbe811ffffff84c0741241b810000000488bcbe8fffeffff84c0743641b820000000488bcbe8edfeffff84c0741241b840000000488bcbe8dbfeffff84c0741241b804000000488bcbe8c9feffff84c07408b0014883c4205bc332c04883c4205bc3"},{rva=7795488,hex="48895c240848896c2410488974241848897c242041563b1538790102458bf04c8bd9744c448b51284533c98b59300fafda418d6aff4585d27436488b79208b712c0f1f40006666660f1f8400000000008bc5418d0c194823c88b04cf4c8d04cf3bc674253bc2742541ffc1453bca72e032c0488b5c2410488b6c2418488b742420488b7c2428415ec33bc275e3418b400483f8ff74da8bc8498b4350448534880f95c0ebcd"},{rva=7774688,hex="48895c240848896c2410488974241857415641574883ec20448b0575ca0102488bd9413bd0744a448b51284533ff8b7930458bcf0faffa458d72ff4585d27431488b71208b692c660f1f840000000000418bc6418d0c394823c88b04ce4c8d1cce3bc574273bc2742741ffc1453bca72df33c0488b5c2440488b6c2448488b7424504883c420415f415e5fc33bc275e1418b430483f8ff74d8488d0cc0488b43484c8d34888b0488413bc074c48b0dcdc901023bc174ba488b157a200002458bcf448b52288b5a300fafd8418d6aff4585d2742d488b7a208b722c0f1f4400008bd5458d04194c23c2428b14c74e8d1cc73bd674703bd0747041ffc1453bca72df3bc10f8468ffffff4c8b1d58210002458bc7458b4b28418b5b300fafd8418d69ff4585c90f8446ffffff498b7b20418b732c0f1f4000660f1f8400000000008bcd418d14184823d18b0cd74c8d14d73bce74283bc8742c41ffc0453bc172e0e90cffffff3bd0759841837b04ff74918bd0e869c51000e9f7feffff3bc80f85edfeffff41837a04ff0f84e2feffff8bd0498bcbe817de270085c0410f95c7418bc7e9ccfeffff"},{rva=8874176,hex="4883ec083b159603f1014c8b15475aef017513b8ffffffff8bc8498b42508b04c84883c408c3458b4a284533c048895c2410418b5a3048896c24180fafda418d69ff488974242048893c244585c97430498b7a20418b722c0f1f8400000000008bc5418d0c184823c88b04cf4c8d1ccf3bc674323bc2743241ffc0453bc172e0b8ffffffff488b742420488b6c2418488b5c2410488b3c248bc8498b42508b04c84883c408c33bc275d6418b4304ebd5"},{rva=10387856,hex="48895c240848896c2410488974241848897c24203b15e2ead9014c8bd174513b15abead9017449448b49284533c08b59300fafda418d69ff4585c97433488b79208b712c0f1f40000f1f8400000000008bc5418d0c184823c88b04cf4c8d1ccf3bc674233bc2742341ffc0453bc172e033c0488b5c2408488b6c2410488b742418488b7c2420c33bc275e5418b430483f8ff74dc486bc82c49034a5083390074cf8b4104ebcc"},{rva=5210096,hex="4883ec284c8bd14885c9750733c04883c428c38b41083b0558ec28020f84930000004c8b1de74927024533c048895c243048896c24384889742440458b4b70418b5b780fafd848897c2420418d69ff4585c9742c498b7b68418b73740f1f40008bcd418d14184823d1488d0cd78b14d73bd6740e3bd0740a41ffc0453bc172e033c9488b7c2420488b742440488b6c2438488b5c24303901751b8b410483f8ff74134869c084000000490383a80000004883c428c3498b0a4883c428e90ffbffff"},{rva=14810512,hex="40534883ec30488bd985d275568b510841b9ffffffff488b0da3c994014533c0e89b5e92ff488bcbe803170f0084c0740dbae1bbeaf9488bcbe872a30f00488bcbe8ea160f0084c00f85e8000000bac2f17e2e488bcbe855a30f0032c04883c4305bc383fa0a7557baf504802449b867dd12837d21759be834a51000488b050dc29401baeb0e5179488b4818488b81d00600008b4b0cffd084c00f849600000033d20f57db8954242041b8eb0e5179488bd3e8490cf7ff32c04883c4305bc383fa1e0f859e0000004885db7469f641140174638b41083b05086e96017458488b0d13c9940133d24889742440448b4928448b5930440fafd8418d71ff4585c974304c8b512048897c24488b792c0f1f008bce468d041a4c23c1438b0cc23bcf741d3bc8741dffc2413bd172e4488b7c2448488b74244032c04883c4305bc33bc875ea43837cc204ff74e24533c08bd0e8acc894ff488b7c244832c0488b7424404883c4305bc383fa1f75cbb0014883c4305bc3"},{rva=14810384,hex="40534883ec20488bd985d27512baeb1ce7ffe819a40f0032c04883c4205bc383fa0f75f34885db7415f6411401740f8b5108488b0dd7c79401e8d23c94ffba8e6c2526488bcbe8d51a0e00ba27d8f64c41b88e6c2526488bcbe842100e00b0014883c4205bc3"},{rva=5209024,hex="4885c9746c488b05f4742702448bc14c8b90a813f10048b8c94216b290852c6448f7e1488bc1482bc248d1e84803c248c1e8056bc02e442bc04533c90f1f4000418bc048c1e0044903c2488b10483bd174224885d2741a418bc0418d50014533c041ffc183f82d440f45c24183f92e72cf33c0c34885c074f88b48084869c1840000004805e00200004903c2c3"},{rva=34719152,hex="0000803f"},{rva=15427504,hex="418bd0e85895f6ff440fb6c84883c428c3418bd0e8c795f6ff440fb6c84883c428c3"},{rva=15468872,hex="b067eb00c167eb00"},{rva=7570016,hex="4c8944241853415441564883ec408b42084533f63b05e6e904024c8be24c8b150c410302488974246848897c24784c896c24384c897c2430744a458b4a30418bd6458b5a38440fafd8418d71ff4585c97432498b5a28418b7a34660f1f4400008bce468d041a4c23c1428b0cc33bcf0f84990000003bc80f8499000000ffc2413bd172dcb8ffffffff498b4a40498b7a508bd048896c2460488b0cd1488d1c92e83bc6dcff448934df418b4c24083b0d4ce90402488944247074784c8b05e6400302418bd6458b4858458b5060440fafd1418d69ff4585c974594d8b5850418b705c0f1f400066660f1f8400000000008bc5468d04124c23c0438b04c33bc6741f3bc1741fffc2413bd172e4eb253bc80f856effffff428b44c304e969ffffff3bc1750f43837cc304ff7407c704df01000000418b4424083b05d6e80402745e488b0d91430302418bd6448b4948448b5150440fafd0418d69ff4585c9743f4c8b59408b714c66660f1f8400000000008bcd468d04124c23c1438b0cc33bce740d3bc8740dffc2413bd172e4eb103bc8750c43837cc304ff7404830cdf02418b4424083b056be804027454488b0dae440302418bd6448b4950448b5158440fafd0418d69ff4585c974354c8b59488b71548bcd468d04124c23c1438b0cc33bce740d3bc8740dffc2413bd172e4eb103bc8750c43837cc304ff7404830cdf04418b4424083b050ae804027462488b0db5420302418bd6448b4928448b5130440fafd0418d69ff4585c974434c8b59208b712c0f1f400066660f1f8400000000008bcd468d04124c23c1438b0cc33bce740d3bc8740dffc2413bd172e4eb103bc8750c43837cc304ff7404830cdf08418b4424083b059be704024c8b2db0430302745c458b4d20418bd6458b5528440fafd0418d69ff4585c974444d8b5d18418b75240f1f400066660f1f8400000000008bcd468d04124c23c1438b0cc33bce740d3bc8740dffc2413bd172e4eb103bc8750c43837cc304ff7404830cdf20418b4424083b052be704024c8b3dd8430302745c458b4f50418bd6458b5758440fafd0418d69ff4585c974444d8b5f48418b77540f1f400066660f1f8400000000008bcd468d04124c23c1438b0cc33bce740d3bc8740dffc2413bd172e4eb103bc8750c43837cc304ff7404830cdf10418b4424083b05bbe604027454488b0dc6410302418bd6448b4928448b5930440fafd8418d69ff4585c974354c8b51208b712c8bcd468d041a4c23c1438b0cc23bce740d3bc8740dffc2413bd172e4eb103bc8750c43837cc204ff7404830cdf40418b4424083b0546e604027465488b0d553d0302418bd6448b4928448b5930440fafd8418d69ff4585c974464c8b51208b712c0f1f400066660f1f8400000000008bcd468d041a4c23c1438b0cc23bce740d3bc8740dffc2413bd172e4eb133bc8750f43837cc204ff7407810cdf80000000418b4424083b05d4e504027463488b0d6b430302418bd6448b4930448b5938440fafd8418d69ff4585c974444c8b51288b71340f1f40000f1f8400000000008bcd468d041a4c23c1438b0cc23bce740d3bc8740dffc2413bd172e4eb133bc8750f43837cc204ff7407810cdf00010000418b4424083b0564e504027463488b0d53430302418bd6448b4930448b5938440fafd8418d69ff4585c974444c8b51288b71340f1f40000f1f8400000000008bcd468d041a4c23c1438b0cc23bce740d3bc8740dffc2413bd172e4eb133bc8750f43837cc204ff7407810cdf00020000418b4424083b0508e504027463488b0d4b400302418bd6448b4928448b5930440fafd8418d69ff4585c974444c8b51208b712c0f1f40000f1f8400000000008bcd468d041a4c23c1438b0cc23bce740d3bc8740dffc2413bd172e4eb133bc8750f43837cc204ff7407810cdf00040000488b4424704885c074104438b0a80300007407810cdf00080000418b4424083b057ee404027467458b4f50418bd6458b5758440fafd0418d69ff4585c9744f4d8b5f48418b77540f1f8400000000008bcd468d04124c23c1438b0cc33bce740d3bc8740dffc2413bd172e4eb213bc8751d43837cc304ff7415498bcce8ae02ddff443870087407810cdf00080000418b4424083b050ae404024c8b7c24307451458b4d20418bd6458b5528440fafd0418d69ff4585c974394d8b5d18418b75248bcd468d04124c23c1438b0cc33bce740d3bc8740dffc2413bd172e4eb133bc8750f43837cc304ff7407810cdf00080000418b4424083b05a7e304024c8b6c24387450488b0d65400302418bd6448b4928448b5130440fafd0418d69ff4585c974314c8b59208b712c660f1f4400008bcd468d04124c23c1438b0cc33bce0f84c30000003bc80f84c3000000ffc2413bd172dcb8ffffffff83f8ffb900200000ba001000000f44ca090cdf488b742468488b6c2460c744df1c00010000448974df04448974df1844897424204c897424280f104424200f1144df08418b4424083b05e9e20402488b7c24780f8489000000488b0d67400302448b4138448b4940440fafc8418d58ff4585c0746d4c8b5130448b593c66660f1f8400000000008bcb438d140e4823d1418b0cd2413bcb74283bc8742841ffc6453bf072e24883c440415e415c5bc33bc80f8544ffffff438b44c304e93fffffff3bc8751d41837cd204ff74158bd0e8e329000085c0750a418b542408e8259a01004883c440415e415c5bc3"},{rva=7572448,hex="48895c241048894c240855565741544155415641574881ec90000000488bf10f29b424800000004533e40f28f1418bccbdffffffff898c24e00000008b46188bd085c00f84ea0900000f1f8000000000488b4640448bf1488b4e584c8974245848894c24604e8b2cf04f8d3cb6488b46504889442470428b04f80fbae00c0f8362020000a8010f847d000000418b45083b05eadf0402488b1d8b370302743d448b4b58418bd4448b5360440fafd0418d71ff4585c974254c8b5b508b7b5c66908bce468d04124c23c1438b0cc33bcf742d3bc8742dffc2413bd172e48bc54c8b4424608bc84869d1a8000000488b4b78430fb6040688440a01e9110400003bc875da438b44c304ebd5a8047413450fb6040e418b5508e875f9f3ffe9ef030000a8080f841d010000418b5d083b1d62df0402450fb63c0e4c8b350a3a03020f84cb030000458b4628418bcc458b4e30440fafcb418d78ff4585c00f84af0300004d8b5620458b5e2c0f1f8400000000008bc7428d14094823d0418b04d2413bc374103bc37414ffc1413bc872e3e97d0300003bc30f8575030000418b74d2043bf50f84680300004584ff7417488b0dfd3503028bd3e8a640000084c0740540b701eb5f4032ff4584ff746d498b4638488b14f048b8193971f099a17e554839027540448bc3488d9424e8000000e82eaae4ff448b8424e80000000f57db488b0d64780302ba7deaefce448964244044896424384c89642428c644242001e8de549c00498b4648443824f0750c4084ff74078bd3e8f8440900498b464840883cf0e9ca020000a8207413450fb6040e418b5508e86952ecffe9b3020000a8100f84ab020000418b45083b0526de0402488b1dd33a03027445448b4b50418bd4448b5358440fafd0418d71ff4585c9742d4c8b5b488b7b5466660f1f8400000000008bce468d04124c23c1438b0cc33bcf742a3bc8742affc2413bd172e48bc54c8b4424608bc8430fb60406488d1489488b4b708844d101e9340200003bc875dd438b44c304ebd80fbae00d0f831f020000418b45083b059add04020f840f020000488b0d593a0302418bd4448b4928448b5130440fafd0418d79ff4585c90f84ec0100004c8b59208b592c660f1f4400008bcf468d04124c23c1438b0cc33bcb74103bc87414ffc2413bd172e4e9be0100003bc80f85b601000043396cc3040f84ab0100008bd0488bcee8f23e00004c8b442460473824060f841f01000084c0747c418b45083b0509dd0402488b1dce3903027448448b4b28418bd4448b5330440fafd0418d71ff4585c974304c8b5b208b7b2c0f1f4000660f1f8400000000008bce468d04124c23c1438b0cc33bcf74213bc87421ffc2413bd172e48bc58bc8488b4340488d1489c644d00c01e91d0100003bc875e6438b44c304ebe14c8b742470473864fe210f8502010000498bcde83b71dcff488bf84439a0c40000007473488b0d38300302488b99c8020000488b0d0a300302488b5118418b4d0c4c8b824807000041ffd0488b0d493003024533c0488bd0488b89d8100000ffd3488b35fb2f0302488bd8483b0674278b8fc4000000e898bc8700488b0d193003024533c94c8bc38bd0488b89d8100000ff963803000043c644fe2101eb73418b45083b05eedb0402488b1db33803027445448b4b28418bd4448b5330440fafd0418d71ff4585c9742d4c8b5b208b7b2c66908bce468d04124c23c1438b0cc33bcf0f848a0000003bc80f848a000000ffc2413bd172dc8bc58bc8488b4340488d1489448864d00c488b442470468864f821418b45088b3567db04023bc60f84b00000004c8b3d50390302418bd4458b4f30418b7f38448bd7440fafd0418d59ff4585c90f848a0000004d8b5f28458b7734908bcb468d04124c23c1438b0cc3413bce741f3bc8741fffc2413bd172e3eb623bc80f857dffffff438b44c304e975ffffff3bc8754c43396cc30474453bc6742e0faff8458d51ff418bd4660f1f440000418bca448d043a4c23c1438b0cc3413bce747c3bc8747cffc2413bd172e28bd50f28d6498bcfe8d52102008b35afda0402418b45083b05b9da04027478488b1d8c350302418bd4448b8b80020000448b9388020000440fafd0458d71ff4585c974534c8b9b780200008bbb8402000090418bce468d04124c23c1438b0cc33bcf74183bc87418ffc2413bd172e3eb263bc8758b438b54c304eb863bc8751743396cc30474108bd0488bcbe811b000008b352bda0402418b5d088b3d35da04023bde0f84a40000004c8b3512320302418bcc458b4620458b4e28440fafcb458d78ff4585c00f84810000004d8b5618458b5e24418bc7428d14094823d0418b04d2413bc3740d3bc3740dffc1413bc872e2eb593bc3755541396cd204744e3bde7444458b4e28418d78ff440fafcb418bcc4585c074306666660f1f8400000000008bc7428d14094823d0418b04d2413bc30f84ac0000003bc30f84ac000000ffc1413bc872db8b3d89d904024c8b7c2458488b442460453824070f84bf010000488b4c24704b8d04bf443864c11c0f85ab0100003b3d5bd904020f84ab0100008bcfe8aa5560004c8bf03bde0f8480010000488b1598370302418bcc448b4228448b4a30440fafcb418d70ff4585c00f845d0100004c8b5220448b5a2c0f1f40008bc6428d14094823d0418b04d2413bc374333bc37437ffc1413bc872e3e92f0100003bc30f855bffffff418b44d2043bc50f844effffff8bc8498b46388b3c88e946ffffff3bc30f850401000041396cd2040f84f90000004d85f60f84f0000000418b4e0c85c97470488b05502c0302488b5018488b8220070000ffd084c07458488b05382c0302488b4818488b8140030000418b4e0cffd085c0743c488b051c2c0302ba740d7ccd488b4818488b8150030000418b4e0cffd085c0741b488b05fb2b0302ba740d7ccd418b4e0c4c8b401841ff9070030000418b4d0c85c97470488b05d82b0302488b5018488b8220070000ffd084c07458488b05c02b0302488b4818488b8140030000418b4d0cffd085c0743c488b05a42b0302ba483a112a488b4818488b8150030000418b4d0cffd085c0741b488b05832b0302ba483a112a418b4d0c4c8b401841ff90700300008bcfe838c841008b35a2d704023b3db0d704020f85dd000000418b45083bc60f84d10000004c8b35eb2e0302418bd4458b4e20458b5628440fafd0458d79ff4585c90f84a90000004d8b5e18418b5e240f1f40006666660f1f840000000000418bcf468d04124c23c1438b0cc33bcb740d3bc8740dffc2413bd172e3eb733bc8756f43396cc30474683bc67446458b5628418d79ff440fafd0418bd44585c974320f1f400066660f1f8400000000008bcf468d04124c23c1438b0cc33bcb0f84b30100003bc80f84b3010000ffc2413bd172dc8bc58bc8498b46384869d1ac000000488d4c24508b1402e8704f60008b384c8b7c2458488b0d823403028bd7e80b660f00488b5424704b8d0cbf8bc00f57c9f30f1044ca04f3480f2ac80f2ec17a02740bf30f114cca04c644ca1d01488b442460488bb424d0000000410fb604078844ca1c8b8c24e00000008b4618ffc1898c24e00000008bd03bc80f821df6ffff83f8010f82e9000000ff46088b46083bc2720744896608418bc44c8b7e508bc8488b46404c8d3489488b0cc88b41088b0d18d604023bc1745a4c8b15dd2b03024533ed458bc5458b5a48418b5a500fafd8458d63ff4585db7439498b7a40418b724c6666660f1f840000000000418bd4468d0c034c23ca428b14cf3bd60f84a40000003bd00f84a400000041ffc0453bc372da488d05873c8601c7442470040000004889442478488d4424700f28442470660f7f4424700f1030438b4cf708660f7ef03bc8751f660f6fc6448bc14b8b4cf710660f73d80866480f7ec2e8ab9f6e0185c0740c430f1174f70843c644f71e01488b9c24d80000000f28b424800000004881c490000000415f415e415d415c5f5e5dc33bc80f8554feffff438b44c304e94cfeffff3bd00f8564ffffff42396ccf040f8459ffffff488bb424d0000000488b363bc1744c458b4a50418d7bff440fafc8458bc34585db74384d8b5a40418b5a4c0f1f8400000000008bcf438d14294823d1418b0cd33bcb740e3bc8740e41ffc5453be872e3eb093bc87505418b6cd3044d8b4268488d8e082c00008bc54981c0e00200004869d0080300004c03c2488d542470e850475f00e9f5feffff"},{rva=8181488,hex="40535641564883ec503b157595fb01450fb6f0488b351ef0f9018bda0f8421010000448b4e2833c9448b5630440fafd34889bc2480000000418d79ff4585c90f84f60000004c8b4620448b5e2c0f1f008bc7428d14114823d0418b04d0413bc3741c3bc37420ffc1413bc972e3488bbc24800000004883c450415e5e5bc33bc30f85b500000048896c2470418b6cd00483fdff0f849d0000004584f67417488b0dfbebf9018bd3e8a4f6f6ff84c0740540b701eb634032ff4584f67471488b4638488b14e848b8193971f099a17e554839027544448bc3488d542478e82f60dbff448b4424780f57db488b0d682efa01ba7deaefcec744244000000000c74424380000000048c744242800000000c644242001e8d80a9300488b4648803ce800750c4084ff74078bd3e8f2faffff488b464840883ce8488b6c2470488bbc24800000004883c450415e5e5bc3"},{rva=7578080,hex="4c8bdc5341554881ec98000000488b051c9ec5014833c448894424684c8be94c894c24608b0d56ca0402418bd8443bc10f84b3030000458b4d30458b553849896b10498973e833f6440fafd3418d69ff8bd64585c90f847e03000049897be04d8b5d28418b7d34660f1f8400000000008bc5468d04124c23c0438b04c33bc774103bc37414ffc2413bd172e4e9400300003bc30f85380300004c89a42480000000bfffffffff478b64c304443be70f8415030000488b056d2103028bd64c89742478448b4858448b5060440fafd3458d71ff4585c974334c8b58508b685c6690418bc6468d04124c23c0438b04c33bc5740d3bc3740dffc2413bd172e3eb0b3bc3750743397cc304756b3b1d84c904020f84ae020000488b052b2603028bd6448b4850448b5058440fafd3458d71ff4585c90f848c0200004c8b58488b685490418bc6468d04124c23c0438b04c33bc574103bc37414ffc2413bd172e3e9620200003bc30f855a02000043397cc3040f844f0200004c8b15042103028bd64c897c2470458b4a20458b5a28440fafdb458d79ff4585c974254d8b7218418b6a24418bc7468d041a4c23c0438b04c63bc574703bc37470ffc2413bd172e38b05d1c804023bc10f84f4010000488b0d961d03028bd6448b4938448b5140440fafd0458d71ff4585c90f84d20100004c8b59308b693c0f1f40000f1f840000000000418bce468d04124c23c1438b0cc33bcd74283bc8742cffc2413bd172e3e99d0100003bc37597438b44c6043bc7748e8bd0498b42388b0490eb893bc80f857d01000043397cc3040f84720100004d8b7d504f8d34a4438b04f7a8017479f30f108424000100008bd3f30f108c24f80000008b8424e80000004c8b4c2460440fb6842408010000488b0d9b1f0302f30f11442450f30f108424f0000000f30f114c2448f30f1144244089442438488b8424e000000048894424308b8424d8000000894424288b8424d000000089442420e8cc21edffeb35a8067531a80874098bd3e84b2e0900eb24a82074098bd3e8ee3decffeb17a81074134c8b4424608bd3488b0d42240302e8d58f0c0043f704f70020000074613b1d79c704024c8b053e2403027443418b5028458b4830440fafcb8d6aff85d274304d8b5020458b582c908bc5428d0c0e4823c8418b04ca413bc3740c3bc3740cffc63bf272e4eb093bc37505418b7cca048bc7488d0c80498b4040c644c820018bd3498bcde8b0390000498b45404a8b14e0f6421401743143f704f70001000074278bd3498bcde89e19000085c07519488b0d732403028bd3e8cc8a030084c074078bd3e8817403004c8b7c24704c8b7424784c8ba42480000000488bbc2488000000488bac24b8000000488bb42490000000488b4c24684833cce8daba69014881c498000000415d5bc3"},{rva=7575520,hex="48894c2408535556574155415641574883ec20488b05962b03024533ff8b0d5dd404028bda48894424603bd17448448b4830458bc7448b5838440fafdb458d71ff4585c97430488b70288b68340f1f00418bc6438d14184823d0bfffffffff8b04d64c8d14d63bc574783bc3747841ffc0453bc172dabfffffffff8bc7488b742460448be84c896c2470488b46404e8b2ce83bd974724c8b153b2b0302418bd7458b4230458b5a38440fafdb458d70ff4585c07453498b7228418b6a340f1f00418bc6428d0c1a4823c88b04ce4c8d0cce3bc574173bc37417ffc2413bd072e0eb263bc37595418b4204eb913bc375184139790474128bd3498bcae860301e0084c00f85a1020000488b542470488b4c2460488b4158c60402014c8b4158488b41404c03c2488b0cd0ba8f6032318b4910e85a4a6000418b45088b1540d30402488b2d392b03023bc20f8453010000448b5520458bcf8b75280faff0458d6aff4585d20f84390100004c8b75184c89642468448b652466660f1f840000000000418bcd458d04314c23c1438b0cc64f8d1cc6413bcc74113bc8741541ffc1453bca72dde9f50000003bc80f85ed000000418b43043bc70f84e10000008bc8488b45388b0c883b0dc9d204020f84cc0000003bca0f84c4000000488b0570300302458bc7448b8800010000448b9808010000440fafd9458d71ff4585c90f849b000000488bb0f80000008ba80401000090418bc6438d14184823d08b04d64c8d14d63bc5740e3bc1740e41ffc0453bc172dfeb6a3bc1756641397a047460e8ae4e60004885c07456f640140174504c8b354c310302418bef4539be48310000763d8bf54881c6150300004803f641817cf608ef000000751b498b34f68bd3488b0d2c29030244897e0ce883120000ffc0894608ffc5413bae4831000072c34c8b642468488b442470488b742460488d0c80488b4650f704c8000100000f84e80000008bd3488bcee84512000085c00f85d6000000488b0d462f03028bd3e89f95030084c00f84c00000008bd3488bcee86d15000085c00f8eae0000003b1d7fd10402488b35182f03027451448b4630418bd7448b5638440fafd3458d70ff4585c074394c8b5e288b6e340f1f8000000000418bc6428d0c124823c8418b04cb4d8d0ccb3bc5740d3bc3740dffc2413bd072dfeb083bc37504418b7904488b4650488d0c7f488d2cc8488b4e40488b0cf9e89ce4dbff488b56584c8d04bf468b4c82044585c9740c4183f901750a448b7844eb04448b78408b451085c07405413bc774078bd3e8977e03004883c420415f415e415d5f5e5d5bc3"},{rva=7576480,hex="48895c241848896c2420565741544883ec204533e48bda3b15a3d004024c8bd17455448b4130418bd4448b5938440fafdb418d68ff4585c0743d488b79288b71340f1f40006666660f1f8400000000008bc5428d0c1a4823c88b04cf4c8d0ccf3bc60f84af0000003bc30f84af000000ffc2413bd072d9b8ffffffff8bc8ba8f603231498b4240488b3cc8498b425844882401498b42404d8b42584c03c1488b0cc88b4910e8264760008b47088b150dd00402488b35062803023bc20f848b010000448b5620458bcc8b7e280faff84c897c2448458d7aff4585d20f84670100008b6e244c897424404c8b76180f1f00418bcf458d04394c23c1438b0cc64f8d1cc63bcd74223bc8742641ffc1453bca72dee92c0100003bc30f8558ffffff418b4104e954ffffff3bc80f8513010000418b430483f8ff0f84060100008bc8488b46388b0c883b0d88cf04020f84f10000003bca0f84e9000000488b052f2d0302458bc4448b9000010000448b9808010000440fafd9418d6aff4585d20f84c0000000488bb8f80000008bb0040100008bc5438d14184823d08b04d74c8d0cd73bc674113bc1741541ffc0453bc272e0e98e0000003bc10f858600000041837904ff0f847b000000e8634b60004885c07471f6401401746b488b2d012e0302418bfc4439a56031000076580f1f4400008bc74803c081bcc570310000ef0000007537488b0de72503028bd3488bb4c568310000e8380f00008b4e082bc881f9960000007c14837e0c0a7c0eba0a000000e8cb73a1004489660cffc73bbd6031000072ad4c8b7424404c8b7c2448488b5c2450488b6c24584883c420415c5f5ec3"}}}
-- EXP04: physical RMB Deploy / LMB Detonate. Native Fire gate is C4-instance scoped.
local existing = rawget(_G, 'HD2C4BoundaryProbe')
if existing then return existing end
local M = {version='0.4.0-exp04', capture=false, tick=0, elapsed_ms=0,
           status='starting', records=0, bytes=0, disabled=false}
rawset(_G, 'HD2C4BoundaryProbe', M)
local loader = rawget(_G, 'CowboyBingusModLoader')
local engine = rawget(_G, 'stingray')
local previous_update = rawget(_G, 'update')
if type(loader) ~= 'table' or loader.api ~= 1 or type(loader.version) ~= 'number'
    or loader.version < 16 or type(loader.open_log) ~= 'function'
    or type(engine) ~= 'table' or type(previous_update) ~= 'function' then
    M.status = 'unsupported_loader_engine_or_update'; M.disabled = true
    print('[C4BoundaryProbe] '..M.status)
    return M
end

local function quote(s)
    return '"'..s:gsub('[%z\1-\31\\"]', function(c)
        if c == '\\' then return '\\\\' end
        if c == '"' then return '\\"' end
        return string.format('\\u%04x', string.byte(c))
    end)..'"'
end
local function json(v)
    local kind = type(v)
    if kind == 'nil' then return 'null' end
    if kind == 'boolean' then return v and 'true' or 'false' end
    if kind == 'number' then
        if v ~= v or v == math.huge or v == -math.huge then return 'null' end
        return string.format('%.15g', v)
    end
    if kind == 'string' then return quote(v) end
    assert(kind == 'table', 'non_json_value')
    local keys, parts = {}, {}
    for k in pairs(v) do assert(type(k) == 'string', 'non_string_key'); keys[#keys+1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do parts[#parts+1] = quote(k)..':'..json(v[k]) end
    return '{'..table.concat(parts, ',')..'}'
end

local file,actions,focus,gate,router,cancel_keys
local last_mouse_released=true
local function close()
    if file then pcall(file.flush, file); pcall(file.close, file); file = nil end
end
local function emit(kind, extra)
    if not file or M.disabled then return false end
    local row = {schema=1, record_type=kind, evidence_kind='RUNTIME_OBSERVATION',
        timestamp_utc=os.date('!%Y-%m-%dT%H:%M:%SZ'), tick=M.tick,
        tick_kind='lua_update_callback_count', elapsed_ms=M.elapsed_ms,
        clock_kind='sum_of_valid_update_dt', phase='before_original_update',
        current_weapon='UNKNOWN', current_fire_mode='UNKNOWN', input='NONE',
        requested_action='NONE', executed_action='NONE', pending_action='NONE',
        action_lock='NOT_IMPLEMENTED', action_result='OBSERVATION_ONLY'}
    if actions then for k,v in pairs(actions.fields(M.elapsed_ms)) do row[k]=v end end
    if gate then for k,v in pairs(gate.fields()) do row[k]=v end end
    for k, v in pairs(extra or {}) do row[k] = v end
    local line = json(row)..'\n'
    if M.records >= 10000 or M.bytes + #line > 4*1024*1024 then
        local final = json({schema=1, record_type='limit', tick=M.tick,
                            reason='bounded_log_limit', capture_stopped=true})..'\n'
        assert(file:write(final)); close()
        M.disabled=true; M.status='log_limit'; M.capture=false
        return false
    end
    assert(file:write(line), 'log_write_failed')
    M.records=M.records+1; M.bytes=M.bytes+#line
    if kind=='action_call' or (kind=='fire_gate' and extra and extra.fire_gate_status=='acquire') then
        assert(file:flush(),'pre_mutation_log_flush_failed')
    end
    return true
end

local function fail(reason)
    if gate then
        local ok,restored,why=pcall(gate.stop)
        if not ok or not restored then reason=tostring(reason)..'; restore pending: '..tostring(why or restored) end
    end
    pcall(emit, 'probe_error', {reason=tostring(reason)})
    M.disabled=true; M.capture=false; M.status=tostring(reason); close()
    print('[C4BoundaryProbe] disabled: '..M.status)
end

local function open_log()
    local base = loader.log_directory
    if not base then
        local local_app_data = os.getenv('LOCALAPPDATA')
        assert(local_app_data and local_app_data ~= '', 'log_directory_unknown')
        base=local_app_data..'/CowboyBingus/Helldivers2/Logs'
    end
    local prefix='C4DualInput_'..os.date('!%Y%m%dT%H%M%SZ')
    for i=1,100 do
        local name=prefix..'_'..string.format('%03d',i)..'.log'
        -- open_log uses mode w; check existence before choosing a session name.
        local prior=io.open(base..'/'..name,'rb')
        if prior then prior:close() else
            file=assert(loader.open_log(name), 'log_open_failed')
            M.log_name=name
            return
        end
    end
    error('session_name_limit')
end

local function relevant(path)
    path=path:lower()
    for _, word in ipairs({'mouse','keyboard','input','player','weapon','action',
                          'deploy','detonat','fire','aim','ability','controller'}) do
        if path:find(word,1,true) then return true end
    end
    return false
end
local function catalog()
    local visited, emitted=0,0
    local truncated=false
    local function walk(t, prefix, depth)
        for k,v in next,t do
            visited=visited+1
            if visited>8192 or emitted>=1024 then truncated=true; return end
            if type(k)=='string' and k~='__index' and k~='_G' then
                local path=prefix..'.'..k
                if relevant(path) then
                    emit('api', {path=path, raw_type=type(v), callable_verified=false})
                    emitted=emitted+1
                end
                if depth>0 and type(v)=='table' then walk(v,path,depth-1) end
                if truncated then return end
            end
        end
    end
    walk(engine,'stingray',1)
    -- Other globals are inspected by name/type only. No candidate is called.
    for k,v in next,_G do
        visited=visited+1
        if visited>8192 or emitted>=1024 then truncated=true; break end
        if type(k)=='string' and k~='stingray' and relevant(k) then
            emit('api', {path='_G.'..k, raw_type=type(v), callable_verified=false})
            emitted=emitted+1
            if type(v)=='table' then walk(v,'_G.'..k,0) end
        end
        if truncated then break end
    end
    emit('catalog_complete', {visited=visited, emitted=emitted, truncated=truncated,
        scope='stingray two levels plus named relevant globals; absence is not proof of no API'})
end

local function flag(v)
    if type(v)=='boolean' then return v end
    if type(v)=='number' and v==v then return v>0 end
    error('unexpected_input_value_'..type(v))
end
local function device_button(device, name, label)
    assert(type(device)=='table','missing_input_device_'..label)
    for _,method in ipairs({'button_id','button','pressed','released'}) do
        assert(type(rawget(device,method))=='function', 'missing_input_method_'..method)
    end
    local id=device.button_id(name)
    assert(type(id)=='number' and id>=0 and id==math.floor(id), 'unresolved_button_'..name)
    local reported=type(device.button_name)=='function' and device.button_name(id) or name
    emit('button_binding', {input=label, engine_name=tostring(reported), button_id=id,
         source='stingray device; no OS hook'})
    return {device=device, id=id, label=label, down=nil, held_ticks=0}
end
local mouse, toggle, marker
local function sample(b)
    return flag(b.device.button(b.id)), flag(b.device.pressed(b.id)), flag(b.device.released(b.id))
end
local function poll_mouse(b, down, pressed, released)
    local old=b.down
    local event
    if pressed and released then event='PRESSED_RELEASED'
    elseif pressed then event='PRESSED'
    elseif released then event='RELEASED'
    elseif old==nil then event=down and 'HELD_AT_CAPTURE_START' or 'BASELINE'
    elseif down and not old then event='DOWN_WITHOUT_PRESSED'
    elseif not down and old then event='UP_WITHOUT_RELEASED'
    elseif down and b.held_ticks==1 then event='HELD' end
    if event then
        emit('input', {input=b.label, event=event, native_pressed=pressed,
            native_released=released, down=down, held_ticks=b.held_ticks,
            repeated_pressed_while_down=pressed and old==true,
            derived_pressed=old==false and down, derived_released=old==true and not down})
    end
    b.held_ticks=down and (b.held_ticks+1) or 0
    b.down=down
end

-- Embedded by assemble_mouse.py in the same scope as the shared log shell.
local function tick(dt)
    M.tick=M.tick+1
    if type(dt)=='number' and dt>=0 and dt<math.huge then M.elapsed_ms=M.elapsed_ms+dt*1000 end
    local td,tp=sample(toggle)
    if tp and toggle.down~=true then
        M.capture=not M.capture
        for _,b in ipairs(mouse) do b.down=nil;b.held_ticks=0 end
        emit('capture',{enabled=M.capture,input='F6',scope='RMB Deploy / LMB Detonate; local C4 only'})
        assert(file:flush(),'log_flush_failed')
    end
    toggle.down=td
    local md,mp=sample(marker)
    if mp and marker.down~=true then emit('manual_marker',{input='F7'}) end
    marker.down=md
    local ld,lp,lr=sample(mouse[1]);local rd,rp,rr=sample(mouse[2])
    local focused=focus()
    local cancel=not focused
    for _,key in ipairs(cancel_keys) do
        local down,pressed=sample(key)
        if down or pressed then cancel=true end
        key.down=down
    end
    if M.capture and cancel then
        M.capture=false
        emit('capture',{enabled=false,reason=not focused and 'focus_lost' or 'menu_or_mode_key'})
    end
    local released=not ld and not rd and not lp and not rp
    last_mouse_released=released
    local owned=gate.sync(M.capture and focused,released)
    local request=router.sample(owned and gate.identity or nil,
        {down=ld,pressed=lp,released=lr},{down=rd,pressed=rp,released=rr})
    if M.capture then
        poll_mouse(mouse[1],ld,lp,lr);poll_mouse(mouse[2],rd,rp,rr)
    else
        mouse[1].down=ld;mouse[2].down=rd
        mouse[1].held_ticks=0;mouse[2].held_ticks=0
    end
    actions.step(M.capture and owned,M.elapsed_ms,{deploy=request.deploy,
        detonate=request.detonate,allowed=focused,mouse=false})
    if file and M.tick%60==0 then assert(file:flush(),'log_flush_failed') end
end

local function after_update()
    if gate then gate.sync(M.capture and not M.disabled and focus(),last_mouse_released) end
end


local ok,why=pcall(function()
    open_log()
    emit('session', {version=M.version, loader_api=loader.api, loader_version=loader.version,
        game_build='24826606', action_execution_enabled=true, deploy_key='RMB', detonate_key='LMB',
        capture_toggle='F6', manual_marker='F7'})
    local api=FireGateWindows(WindowsRead())
    local backend=ActionBackend.new(api,ActionReader,ContextReader,ActionLayout,NativeActions)
    focus=WindowFocus()
    actions=ActionController.new(backend,emit,{deploy_input='RMB',detonate_input='LMB'})
    gate=WeaponFireGate.new(api,assert(api.module('game.dll')),ContextReader,emit,backend.verify)
    router=MouseRouter.new(emit)
    emit('layout_verified',{module_sha256=ActionLayout.module_sha256,
        action_execution_enabled=true,direct_mode_writes=false,mouse_mapping='RMB_DEPLOY_LMB_DETONATE'})
    cancel_keys={}
    for _,key in ipairs({'esc','enter','tab','r','m'}) do
        cancel_keys[#cancel_keys+1]=device_button(engine.Keyboard,key,key)
    end
    toggle=device_button(engine.Keyboard,'f6','F6')
    marker=device_button(engine.Keyboard,'f7','F7')
    mouse={device_button(engine.Mouse,'left','LMB'),device_button(engine.Mouse,'right','RMB')}
    assert(file:flush(),'log_flush_failed')
end)
if not ok then fail(why); return M end
M.status='ready'
local function after(called,...)
    if not called then
        M.capture=false
        if gate then pcall(gate.stop) end
        error((...),0)
    end
    if not M.disabled then
        local ok,why=pcall(after_update)
        if not ok then fail(why) end
    elseif gate and gate.lease then
        pcall(gate.stop) -- retry restoration after transient read/write failure
    end
    return ...
end
update=function(dt,...)
    if not M.disabled then
        local success,err=pcall(tick,dt)
        if not success then fail(err) end
    end
    return after(pcall(previous_update,dt,...))
end
local previous_shutdown=rawget(_G,'shutdown')
shutdown=function(...)
    if gate then pcall(gate.stop) end
    pcall(emit,'shutdown'); close(); M.disabled=true; M.capture=false; M.status='closed'
    if previous_shutdown then return previous_shutdown(...) end
end
print('[C4 Dual Input EXP04] F6 enables/disables; RMB Deploy; LMB Detonate; F7 marker. Log: '..M.log_name)
return M
