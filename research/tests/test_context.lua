local ffi=require('ffi')
local reader=dofile('src/context_reader.lua')
local runtime=dofile('src/context_runtime.lua')
local passed=0
local function test(name,f)
    local ok,reason=pcall(f)
    assert(ok,name..': '..tostring(reason))
    passed=passed+1;print('PASS '..name)
end
local function equal(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local function bytes(h) return h:gsub('..',function(x) return string.char(tonumber(x,16)) end) end
local function word(n) return ffi.string(ffi.new('uint32_t[1]',n),4) end
local function pointer(n) return ffi.string(ffi.new('uint64_t[1]',n),8) end
local fixture=dofile('tests/context_fixture.lua')
test('uint32 product remains exact for high-bit keys and collision probes',function()
    for _,a in ipairs({0xffffffff,0xfedcba91,0x8100000f,0x80000001,1}) do
        for _,b in ipairs({0xffffffff,0xfedcba91,0x8100000f,0x80000001,1}) do
            equal(reader.product_low(a,b),tonumber(ffi.cast('uint32_t',ffi.new('uint64_t',a)*ffi.new('uint64_t',b))))
        end
    end
end)
test('local avatar index one and inventory index two resolve exact C4 resource',function()
    local s=fixture();local r=s.snap()
    equal(r.context_status,'c4_context_observed');equal(r.current_weapon,'C4_DETONATOR')
    equal(r.local_avatar_index,1);equal(r.selected_slot,3);equal(r.c4_guard_candidate,true)
    equal(r.current_fire_mode,'UNKNOWN');assert(r.memory_reads<150 and r.memory_bytes<4096)
end)
test('mode candidates and both descriptors are observed without assigning action success',function()
    local r=fixture().snap()
    equal(r.weapon_function_values['0'],2);equal(r.weapon_function_values['1'],1)
    equal(r.ability_descriptors['0'].weapon_ability_id,333)
    equal(r.ability_descriptors['1'].owner_ability_id,667)
    equal(r.action_result,'OBSERVATION_ONLY');equal(r.current_fire_mode,'UNKNOWN')
end)
test('C4 in another slot does not qualify current primary',function()
    local s=fixture();s.u32(s.state+0x1c,1);local r=s.snap()
    equal(r.current_weapon,'OTHER');equal(r.c4_guard_candidate,false)
    equal(r.ability_descriptors,nil)
end)
test('no selected slot does not retain previous C4 context',function()
    local s=fixture();s.snap();s.u32(s.state+0x1c,0);local r=s.snap()
    equal(r.current_weapon,'UNKNOWN');equal(r.c4_guard_candidate,false)
end)
test('unowned local-player record stops before avatar reads',function()
    local s=fixture();s.u32(0x40000000+20,0);local r=s.snap()
    equal(r.context_status,'local_player_not_owned');equal(r.c4_guard_candidate,false)
end)
test('remote or wrong avatar resource cannot qualify',function()
    local s=fixture();s.put(s.eaddr,s.other);local r=s.snap()
    equal(r.context_status,'avatar_identity_rejected');equal(r.c4_guard_candidate,false)
end)
test('avatar registry equality rejects reused record',function()
    local s=fixture();s.put(0x44000000,s.other);local r=s.snap()
    equal(r.context_status,'avatar_registry_mismatch')
end)
test('inventory owner equality rejects other player inventory',function()
    local s=fixture();s.ptr(0x46000000+16,s.waddr);local r=s.snap()
    equal(r.context_status,'inventory_owner_mismatch')
end)
test('weapon ID mismatch rejects reused entity storage',function()
    local s=fixture();s.u32(s.waddr+8,s.otherid);local r=s.snap()
    equal(r.context_status,'selected_entity_mismatch');equal(r.c4_guard_candidate,false)
end)
test('C4 entity without local ownership stays ineligible',function()
    local s=fixture();s.u32(s.waddr+20,0);local r=s.snap()
    equal(r.current_weapon,'C4_DETONATOR');equal(r.c4_guard_candidate,false)
end)
test('C4 charge resource alone does not qualify detonator action guard',function()
    local s=fixture();s.put(s.waddr,bytes('9b75217d8312dd67'):reverse());local r=s.snap()
    equal(r.current_weapon,'C4_CHARGE');equal(r.c4_guard_candidate,false)
end)
test('ship state stops before player pointers are read',function()
    local s=fixture();s.u32(s.mode+0x40,0);s.memory[s.pm+0x84]=nil
    equal(s.snap().context_status,'waiting_for_mission')
end)
test('short read and inaccessible memory stop observation',function()
    local s=fixture();s.memory[s.state+47]=nil;equal(pcall(s.snap),false)
    s=fixture();s.intercept=function(at,n) if at==s.state then return '\0',true end end
    equal(pcall(s.snap),false)
end)
test('map capacity and indices are bounded',function()
    local s=fixture();s.u32(s.inv+0x30,3);equal(pcall(s.snap),false)
    s=fixture();s.map(s.inv+0x28,0x45000000,{{s.aid,0xfffffffe}})
    equal(s.snap().context_status,'inventory_missing')
end)
test('identity changes during snapshot discard all results',function()
    local s=fixture();local count=0
    s.intercept=function(at,n)
        if at==s.pm+0x3a8 then count=count+1;if count==2 then return word(0x7fff),true end end
    end
    local r,why=s.snap();equal(r,nil);equal(why,'context_changed_during_read')
end)
test('missing ability table entry is absence, not a guessed action',function()
    local s=fixture();s.zero(s.templates+13*16,16);local r=s.snap()
    equal(r.ability_template_status,'absent');equal(r.ability_descriptors,nil)
end)
test('template index cannot escape bounded table',function()
    local s=fixture();s.u32(s.templates+13*16+8,65536);equal(pcall(s.snap),false)
end)
local function runtime_fixture()
    local api={module=function() return 65536 end,module_hash=function() return 'hash' end,
        read=function() return '\1\2' end,time=function() return 100 end}
    local r={calls=0}
    function r.snapshot() r.calls=r.calls+1;return {context_status='ok',current_weapon='C4_DETONATOR'} end
    return api,r,{module_sha256='hash',signatures={{rva=0x1000,hex='0102'}}}
end
test('runtime refuses unsupported module hash before snapshot',function()
    local api,r,l=runtime_fixture();l.module_sha256='wrong';equal(pcall(runtime.new,api,r,l),false);equal(r.calls,0)
end)
test('runtime refuses changed native code before snapshot',function()
    local api,r,l=runtime_fixture();api.read=function() return '\0\0' end
    equal(pcall(runtime.new,api,r,l),false);equal(r.calls,0)
end)
test('context sampling is bounded to 20 Hz except explicit marker',function()
    local api,r,l=runtime_fixture();local m=runtime.new(api,r,l);local events=0
    local function emit() events=events+1 end
    m.observe(true,0,emit);m.observe(true,10,emit);m.observe(true,49,emit);equal(r.calls,1)
    m.observe(true,50,emit);equal(r.calls,2);m.observe(true,51,emit,true);equal(r.calls,3)
    equal(m.fields(60).context_sample_age_ms,9);equal(events,2)
end)
test('capture off and read failures clear old C4 result and allow recovery',function()
    local api,r,l=runtime_fixture();local m=runtime.new(api,r,l);local emit=function() end
    m.observe(true,0,emit);m.observe(false,10,emit);equal(m.fields(10).current_weapon,'UNKNOWN')
    r.snapshot=function() error('invalidated') end;m.observe(true,20,emit)
    equal(m.fields(20).current_weapon,'UNKNOWN');equal(m.fields(20).context_status,'snapshot_unavailable')
    r.snapshot=function() return {context_status='ok',current_weapon='OTHER'} end
    m.observe(true,70,emit);equal(m.fields(70).current_weapon,'OTHER')
end)
print('TOTAL '..passed..' context checks; synthetic memory only')
