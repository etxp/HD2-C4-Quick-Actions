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

function M.snapshot(api,game)
    local guards,reads,bytes={},0,0
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
        return row
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
local ContextRuntime=(function()
local M={}
function M.new(api,reader,layout)
    local game=assert(api.module('game.dll'),'game_module_missing')
    assert(api.module_hash(game)==layout.module_sha256,'unsupported_game_module_hash')
    for _,signature in ipairs(layout.signatures) do
        local expected=signature.hex:gsub('..',function(h) return string.char(tonumber(h,16)) end)
        assert(api.read(game+signature.rva,#expected)==expected,'unsupported_live_code_signature')
    end
    local self={latest={},last_ms=-math.huge,last_key=nil,last_emit=-math.huge}
    function self.fields(ms)
        local result={}
        for k,v in pairs(self.latest) do result[k]=v end
        result.context_sample_age_ms=ms-self.last_ms
        return result
    end
    function self.observe(active,ms,emit,force)
        if not active then
            self.latest={context_status='capture_off',current_weapon='UNKNOWN',current_fire_mode='UNKNOWN',
                c4_guard_candidate=false}
            self.last_ms=-math.huge
            return
        end
        if not force and ms-self.last_ms<50 then return end
        local start=api.time()
        local ok,row,reason=pcall(reader.snapshot,api,game)
        if not ok then reason=row;row=nil end
        if not row then row={current_weapon='UNKNOWN',current_fire_mode='UNKNOWN',
            c4_guard_candidate=false,context_status='snapshot_unavailable',reason=tostring(reason)} end
        row.context_sample_elapsed_ms=ms
        self.latest=row;self.last_ms=ms
        -- Inputs record the latest snapshot with its age. State rows are limited
        -- to 20 Hz; heartbeat every second includes runtime cost diagnostics.
        local key=table.concat({row.context_status,tostring(row.selected_entity_id),
            tostring(row.selected_slot),tostring(row.weapon_state_12),tostring(row.weapon_state_flags),
            tostring(row.reason)},'|')
        if force or key~=self.last_key or ms-self.last_emit>=1000 then
            emit('context',{sample_cost_ms=(api.time()-start)*1000})
            self.last_key=key;self.last_emit=ms
        end
    end
    return self
end
return M

end)()
local ContextLayout={module_sha256="cc75948d90fdfde259dcb519e9933db7ffa3ccb281ce4fb89e6b1b011557470c",signatures={{rva=10080800,hex="41564883ec20443b05339ade014c8bf24c8b1531f2dc01750841b8ffffffffeb"},{rva=10115776,hex="4585c9745d418bc04c8d044049c1e004418d41ff4c03415083f80577454c8d0d"},{rva=13887696,hex="4883ec083b0d7a8ca4010f849b0000004c8b15d907a3014533c048895c241048"},{rva=5278688,hex="4885c9744c488b05d4642602448bc14183e00f4533c94c8b908818f1000f1f00"},{rva=8180288,hex="48895c240848896c24104889742418574883ec203b151a9afb017454488b05c5"},{rva=7657984,hex="48895c241048896c2418488974242057415641574883ec20448b154192030245"}}}
-- EXP02: bounded native data copies only; no game calls or game writes.
local existing = rawget(_G, 'HD2C4BoundaryProbe')
if existing then return existing end
local M = {version='0.2.0-exp02', capture=false, tick=0, elapsed_ms=0,
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

local file,context
local function close()
    if file then pcall(file.flush, file); pcall(file.close, file); file = nil end
end
local function emit(kind, extra)
    if not file or M.disabled then return end
    local row = {schema=1, record_type=kind, evidence_kind='RUNTIME_OBSERVATION',
        timestamp_utc=os.date('!%Y-%m-%dT%H:%M:%SZ'), tick=M.tick,
        tick_kind='lua_update_callback_count', elapsed_ms=M.elapsed_ms,
        clock_kind='sum_of_valid_update_dt', phase='before_original_update',
        current_weapon='UNKNOWN', current_fire_mode='UNKNOWN', input='NONE',
        requested_action='NONE', executed_action='NONE', pending_action='NONE',
        action_lock='NOT_IMPLEMENTED', action_result='OBSERVATION_ONLY'}
    if context then for k,v in pairs(context.fields(M.elapsed_ms)) do row[k]=v end end
    for k, v in pairs(extra or {}) do row[k] = v end
    local line = json(row)..'\n'
    if M.records >= 10000 or M.bytes + #line > 4*1024*1024 then
        local final = json({schema=1, record_type='limit', tick=M.tick,
                            reason='bounded_log_limit', capture_stopped=true})..'\n'
        assert(file:write(final)); close()
        M.disabled=true; M.status='log_limit'; M.capture=false
        return
    end
    assert(file:write(line), 'log_write_failed')
    M.records=M.records+1; M.bytes=M.bytes+#line
end

local function fail(reason)
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
    local prefix='C4Context_'..os.date('!%Y%m%dT%H%M%SZ')
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

local function tick(dt)
    M.tick=M.tick+1
    if type(dt)=='number' and dt>=0 and dt<math.huge then M.elapsed_ms=M.elapsed_ms+dt*1000 end
    local toggle_down, toggle_pressed=sample(toggle)
    if toggle_pressed and toggle.down~=true then
        M.capture=not M.capture
        for _,b in ipairs(mouse) do b.down=nil; b.held_ticks=0 end
        emit('capture', {enabled=M.capture, input='F6',
             scope='read-only local weapon and mode candidates; action outcomes need manual annotation'})
        assert(file:flush(), 'log_flush_failed')
    end
    context.observe(M.capture,M.elapsed_ms,emit)
    toggle.down=toggle_down
    local marker_down, marker_pressed=sample(marker)
    if marker_pressed and marker.down~=true then
        context.observe(M.capture,M.elapsed_ms,emit,true)
        emit('manual_marker', {input='F7', note='tester annotation; mode labels remain unverified'})
    end
    marker.down=marker_down
    if M.capture then
        local ld,lp,lr=sample(mouse[1])
        local rd,rp,rr=sample(mouse[2])
        if lp and rp then
            emit('simultaneous_input', {input='LMB+RMB', resolution='OBSERVE_BOTH_NO_PRIORITY_SELECTED'})
        end
        poll_mouse(mouse[1],ld,lp,lr); poll_mouse(mouse[2],rd,rp,rr)
    end
    if file and M.tick%60==0 then assert(file:flush(),'log_flush_failed') end
end

local ok,why=pcall(function()
    open_log()
    emit('session', {version=M.version, loader_api=loader.api, loader_version=loader.version,
        game_build='UNVERIFIED_AT_RUNTIME', action_execution_enabled=false,
        capture_toggle='F6', manual_marker='F7'})
    context=ContextRuntime.new(WindowsRead(),ContextReader,ContextLayout)
    emit('layout_verified',{game_build='24826606',module_sha256=ContextLayout.module_sha256,
        action_execution_enabled=false,game_memory_writes=false,sample_interval_ms=50})
    toggle=device_button(engine.Keyboard,'f6','F6')
    marker=device_button(engine.Keyboard,'f7','F7')
    mouse={device_button(engine.Mouse,'left','LMB'),device_button(engine.Mouse,'right','RMB')}
    assert(file:flush(),'log_flush_failed')
end)
if not ok then fail(why); return M end
M.status='ready'
update=function(dt,...)
    if not M.disabled then
        local success,err=pcall(tick,dt)
        if not success then fail(err) end
    end
    return previous_update(dt,...)
end
local previous_shutdown=rawget(_G,'shutdown')
shutdown=function(...)
    pcall(emit,'shutdown'); close(); M.disabled=true; M.capture=false; M.status='closed'
    if previous_shutdown then return previous_shutdown(...) end
end
print('[C4BoundaryProbe] F6 toggles capture; F7 marks a moment. Log: '..M.log_name)
return M
