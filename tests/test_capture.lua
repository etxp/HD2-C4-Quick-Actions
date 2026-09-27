-- Resolver integration against actual native instructions. No process access.
local resolver=dofile('src/NativeResolver.lua')
local catalog=dofile('private/build/native_catalog.lua')
local sections={}
for _,s in ipairs(dofile('private/tests/capture_fixture.lua')) do
    local f=assert(io.open(s.path,'rb'));s.bytes=f:read('*a');f:close();sections[#sections+1]=s
end
local base=0x700000000000
local function read(at,n)
    assert(n<=4096,'unbounded read');at=at-base
    for _,s in ipairs(sections) do
        if at>=s.rva and at+n<=s.rva+#s.bytes then return s.bytes:sub(at-s.rva+1,at-s.rva+n) end
    end
end
local started=os.clock()
local result=resolver.resolve({read=read},base,catalog)
assert(result.symbols.fn_start==0x7caf40 and result.symbols.fn_lean==0x63aff0)
assert(result.symbols.fn_seater_update==0x639b40)
assert(result.symbols.global_owner==0x346bf98 and result.symbols.global_ui==0x347ce28)
assert(result.symbols.global_player==0x3326468 and result.fields.tactical_map==84)
result.verify()
print(string.format('PASS actual captured native code: %d signatures, %.2fs',result.node_count,os.clock()-started))

local contact=resolver.resolve({read=read},base,dofile('private/build/contact_catalog.lua'))
assert(contact.symbols.global_contact_remote==0x33267f8)
assert(contact.symbols.global_contact_sticky==0x3326900)
assert(contact.symbols.global_contact_explosive==0x3326728)
assert(contact.symbols.global_contact_owner==result.symbols.global_owner)
assert(contact.symbols.global_contact_world==0x3326340)
assert(contact.symbols.global_contact_physics_api==0x3326328)
assert(contact.symbols.global_contact_events_api==0x3326358)
assert(contact.symbols.contact_explode==0x8cdf80)
assert(contact.symbols.contact_remote_owner==0x76bdf0)
assert(contact.symbols.global_contact_invalid_source==0x3483c34)
assert(contact.symbols.global_contact_manual_label==0x33284c0)
assert(contact.symbols.global_contact_contact_label==0x3328500)
assert(contact.node_count==17)
contact.verify()
print('PASS contact actions and cosmetic label paths resolve 17 native signatures from capture')

-- Both tank variants in the native capture and FRV resolve through the same
-- generic dispatcher. Unsupported native driver slots remain data-driven.
for _,config in ipairs({27,43,44}) do
    for _,seat in ipairs({2,3}) do
        assert(result.vehicle_lean_available(config,seat))
    end
    assert(not result.vehicle_lean_available(config,0))
end
assert(result.vehicle_lean_available(27,1))
result.verify()
print('PASS actual FRV and both tank passenger animation tables resolve generically')

-- Changing a non-FRV case body must revoke compatibility.
local function changed(at,n)
    local bytes=read(at,n)
    if at==base+0x119af87 and n==31 then return string.rep('\0',31) end
    return bytes
end
local ok,why=pcall(function()resolver.resolve({read=changed},base,catalog)end)
assert(not ok and tostring(why):find('compat_vehicle_case',1,true),tostring(why))
print('PASS changed native passenger dispatch body rejected')

-- Animation IDs can legitimately differ across vehicles/game updates.
-- Accept the runtime data at resolution, then reject a later mutation.
local altered=false
local function edited(at,n)
    local bytes=read(at,n)
    if altered and at==base+0x22654d0+2*4 and n==4 then return string.rep('\0',4) end
    return bytes
end
local live=resolver.resolve({read=edited},base,catalog)
assert(live.vehicle_lean_available(43,2));altered=true
local stable,reason=pcall(live.verify)
assert(not stable and tostring(reason):find('compat_live_code_changed:vehicle_seat_animation',1,true),tostring(reason))
print('PASS changed selected passenger animation data revoked before native call')

-- These RVAs describe the private offline fixture, never runtime admission.
-- Check the actual native busy gate and invalid-pending-node return branch.
local function bytes(hex)return (hex:gsub('..',function(v)return string.char(tonumber(v,16))end)) end
assert(read(base+0x63b08a,6)==bytes('807930007570'))
assert(read(base+0x639d70,11)==bytes('837c3718ff0f8439010000'))
print('PASS captured native lean rejects busy relations and idle pending nodes return without transition')
local mutate=false
local function changed_seater(at,n)
    local b=read(at,n)
    if mutate and at==base+0x639b40 then b='\0'..b:sub(2) end
    return b
end
local guarded=resolver.resolve({read=changed_seater},base,catalog);mutate=true
local accepted,why=pcall(guarded.verify)
assert(not accepted and tostring(why):find('fn_seater_update',1,true),tostring(why))
print('PASS seater update code changes revoke compatibility before reservation')

assert(result.symbols.fn_reload==0x774b60 and result.symbols.fn_reload_eligible==0x775580)
assert(result.symbols.fn_reload_config==0x4fd220 and result.symbols.fn_reload_template==0x4fce20)
assert(result.symbols.global_exclusions==0x3326a70 and result.symbols.global_weapon_owner==0x3326730)
assert(result.symbols.fn_ability_tick_head==0x7c8840)
assert(read(base+0x23c7740,4)==bytes('00007042')) -- native phase clock: 60.0f
assert(read(base+0x774d2f,6)==bytes('4533c94533c0')) -- eligibility bypass args both false
assert(read(base+0x774f3a,6)==bytes('41b901000000')) -- original network/local start path
print('PASS captured non-forced reload ABI, owner relation, template and native phase clock')
local reload_mutated=false
local function edited_reload(at,n)
    local b=read(at,n)
    if reload_mutated and at==base+0x774b60 then b='\0'..b:sub(2) end
    return b
end
local reload_guard=resolver.resolve({read=edited_reload},base,catalog);reload_mutated=true
local reload_ok,reload_reason=pcall(reload_guard.verify)
assert(not reload_ok and tostring(reload_reason):find('fn_reload',1,true),tostring(reload_reason))
print('PASS changed reload entry is rejected before native reload calls')

-- dev.8 pinned four low bytes of an absolute address loaded with LEA as a
-- scalar literal. Recreate that failure under ASLR, using the real code image.
local ffi=require('ffi')
local pointer_rva=0x21d7828
local function with_relocation(new_base)
    local pointer=ffi.string(ffi.new('uint64_t[1]',new_base+0x229ee60),8)
    local state={pointer=pointer}
    local function relocated(at,n)
        local rva=at-new_base;local raw=read(base+rva,n)
        if not raw then return end
        local first,last=math.max(rva,pointer_rva),math.min(rva+n,pointer_rva+8)
        if first<last then
            raw=raw:sub(1,first-rva)..state.pointer:sub(first-pointer_rva+1,last-pointer_rva)..raw:sub(last-rva+1)
        end
        return raw
    end
    return relocated,state
end
local function copy(value)
    if type(value)~='table' then return value end
    local result={};for k,v in pairs(value) do result[k]=copy(v) end;return result
end
local legacy=copy(catalog)
for _,node in ipairs(legacy.nodes) do
    if node.name=='fn_reload' then
        for _,ref in ipairs(node.refs) do
            if ref.guard_bytes then
                ref.guard_bytes=nil
                ref.hex=(read(base+pointer_rva,4):gsub('.',function(c)return string.format('%02x',c:byte())end))
            end
        end
    end
end
local relocated_base=0x7ff6c0000000
local relocated=with_relocation(relocated_base)
local old_ok,old_reason=pcall(resolver.resolve,{read=relocated},relocated_base,legacy)
assert(not old_ok and tostring(old_reason):find('compat_literal_changed:fn_reload',1,true),tostring(old_reason))
print('PASS reproduced dev.8 startup failure using a relocated pointer in real captured code')
for _,module_base in ipairs({relocated_base,0x6fff10000000}) do
    local shifted,state=with_relocation(module_base)
    local current=resolver.resolve({read=shifted},module_base,catalog);current.verify()
    assert(current.symbols.fn_reload==0x774b60)
    state.pointer='\0'..state.pointer:sub(2)
    local valid,reason=pcall(current.verify)
    assert(not valid and tostring(reason):find('fn_reload:runtime_pointer',1,true),tostring(reason))
end
print('PASS ASLR startup succeeds while later runtime pointer changes remain rejected')
local function changed_constant(at,n)
    if at==relocated_base+0x23c7740 and n==4 then return bytes('00008042') end
    return relocated(at,n)
end
local constant_ok,constant_reason=pcall(resolver.resolve,{read=changed_constant},relocated_base,catalog)
assert(not constant_ok and tostring(constant_reason):find('compat_literal_changed:fn_reload',1,true),tostring(constant_reason))
print('PASS scalar phase-clock constant remains strictly verified under ASLR')

assert(result.symbols.fn_reserve_count==0x744180)
assert(result.symbols.fn_reload_supply_count==0x7761d0)
assert(result.symbols.fn_unit_entity_id==0xfd9980)
assert(result.symbols.global_reload_supply==0x3326698)
assert(result.fields.unit_entity_id_map==0xf2aee0 and result.fields.reload_supply_stride==0xac)
-- Native rounds reserve is runtime[index*20 + 0], not selected magazine.
assert(read(base+0x7443ad,12)==bytes('498b43584c8d0489428b1c80'))
-- Generic supply relation is reached only when config +0x3c is nonzero.
assert(read(base+0x7759f5,11)==bytes('41807f3c000f84b0040000'))
assert(read(base+0x775bde,13)==bytes('488d4c24408b1402e8953d8600'))
assert(read(base+0x775ddc,7)==bytes('498b47508b14c8'))
-- Unit lookup returns the entity ID stored directly in map value +4.
assert(read(base+0xfd9a14,9)==bytes('8b4804498bc1418909'))
print('PASS captured reserve and linked supply paths agree with reader fields')
local changed_supply=false
local function supply_code(at,n)
    local raw=read(at,n)
    if changed_supply and at==base+0xfd9980 then raw='\0'..raw:sub(2) end
    return raw
end
local supply_guard=resolver.resolve({read=supply_code},base,catalog);changed_supply=true
local supply_ok,supply_reason=pcall(supply_guard.verify)
assert(not supply_ok and tostring(supply_reason):find('fn_unit_entity_id',1,true),tostring(supply_reason))
print('PASS changed supply unit resolution code revokes native compatibility')

assert(result.symbols.global_backpack_reload==0x3326be8)
assert(result.symbols.fn_backpack_reload_eligible==0x73b440)
assert(result.symbols.fn_inventory_backpack==0x9a9cc0)
-- Backpack branch in native reload precedes the generic supply-unit branch.
assert(read(base+0x775b66,13)==bytes('448bc58bd6488bcfe8cd58fcff'))
-- Backpack helper resolves equipped backpack through avatar inventory, not
-- the generic unit relation that pointed to the avatar in the live dev.9 log.
assert(read(base+0x73b501,13)==bytes('458bc3488d542468e8b2e72600'))
assert(read(base+0x9a9d5e,15)==bytes('488d0c40498b43504803c98b4cc80c'))
print('PASS native backpack branch reads inventory row stride 48 at offset 12')

assert(result.symbols.fn_input_mapping==0x12f9540 and result.symbols.fn_input_inhibit==0x12fd250)
assert(result.symbols.fn_input_unblock==0x12fd3b0 and result.symbols.global_input_owner==0x347cf18)
-- Native Aim identity and input-index dispatcher agree with action encoding.
assert(read(base+0xa412aa,10)==bytes('48b90200000008000000'))
assert(result.fields.input_aim_action==0x800000002 and result.fields.input_aim_code==0x20008)
-- Inhibit ABI: owner in RCX, mode in R8D, packed action in RDX, duration XMM3.
assert(read(base+0x12fd26e,12)==bytes('488bf1458be0488bca488bda'))
assert(read(base+0x12fd315,3)==bytes('0f2fc3'))
-- Mode and action occupy record +0/+4; timestamp +16. Negative duration
-- follows the zero-expiry path; unblock writes only mode zero.
assert(read(base+0x12fd30d,8)==bytes('48899cee3c7d0a00'))
assert(read(base+0x12fd318,8)==bytes('4489a4ee387d0a00'))
assert(read(base+0x12fd43e,12)==bytes('41c784cb387d0a0000000000'))
-- The inhibition flag propagates to processed input's two 16-byte clears.
assert(read(base+0x12fa368,5)==bytes('4488742438'))
assert(read(base+0x12fbba1,7)==bytes('0f11000f114010'))
print('PASS captured Aim identity, original native-call ABI and input suppression path')
local function bad_aim_literal(at,n)
    if at==base+0x2254668 then return string.rep('\0',n) end
    return read(at,n)
end
local aim_ok,aim_reason=pcall(resolver.resolve,{read=bad_aim_literal},base,catalog)
assert(not aim_ok and tostring(aim_reason):find('fn_trigger_parse',1,true),tostring(aim_reason))
print('PASS changed trigger-name meaning rejects Aim compatibility')
assert(result.symbols.fn_fire_input_read==0xa45514)
assert(result.fields.input_fire_action==0x900000002 and result.fields.input_fire_code==0x20009)
assert(read(base+0xa45514,10)==bytes('49bd0200000009000000'))
assert(read(base+0xa45535,8)==bytes('4738b421681b0000'))
print('PASS captured avatar reads native Fire independently of C4 weapon Fire gate')

assert(result.symbols.fn_flag_86==0xa9fc20 and result.fields.weapon_menu==86)
assert(read(base+0xa9fcd1,14)==bytes('428b841088e8530048c1e8162401'))
print('PASS captured weapon-settings flag reads avatar bit 86 independently of map bit 84')
local change_menu=false
local function edited_menu(at,n)
 local raw=read(at,n)
 if change_menu and at==base+0xa9fc20 then raw='\0'..raw:sub(2)end
 return raw
end
local menu_guard=resolver.resolve({read=edited_menu},base,catalog);change_menu=true
local menu_ok,menu_reason=pcall(menu_guard.verify)
assert(not menu_ok and tostring(menu_reason):find('fn_flag_86',1,true),tostring(menu_reason))
print('PASS changed weapon-settings flag reader revokes compatibility')
