local ffi=require('ffi')
local file=assert(io.open('src/ContactProbe.lua'));local source=file:read('*a');file:close()
local D={entity_unit_map=0x200,entity_id_map=0x300,unit_entity_id_map=0x400,entity_array=0x1000}
local probe=assert(loadstring('return function(D) '..source..' end'))()(D)
local C=dofile('src/ContextReader.lua')
local function pack(n,size)
    local b={};for i=1,size do b[i]=string.char(n%256);n=math.floor(n/256) end
    return table.concat(b)
end
local function unhex(h)return (h:gsub('..',function(x)return string.char(tonumber(x,16))end)) end
local function hex(b)return (b:gsub('.',function(x)return string.format('%02x',x:byte())end)) end
local function entity(hash,id,unit,owned)
    return unhex(hash):reverse()..pack(id,4)..pack(unit,4)..pack(9,4)..pack(owned and 1 or 0,4)
end
local symbols={global_contact_remote=1,global_contact_sticky=2,global_contact_explosive=3,global_contact_owner=4}
local function fixture()
    local mem,maps={},{}
    local function put(at,b)for i=1,#b do mem[at+i-1]=b:sub(i,i) end end
    local function read(at,n)
        local b={};for i=0,n-1 do b[#b+1]=assert(mem[at+i],'fixture missing byte '..at+i) end
        return table.concat(b)
    end
    local function pointer(at,p)put(at,pack(p,8)) end
    local remote,sticky,explosive,owner=0x10000,0x20000,0x30000,0x40000
    local weapon=entity('51f50d6321f52f3d',77,700,true)
    local friend=entity('51f50d6321f52f3d',88,800,true)
    local charge=entity('9b75217d8312dd67',99,900,true)
    local theirs=entity('9b75217d8312dd67',100,901,true)
    local unowned=entity('9b75217d8312dd67',101,902,false)
    put(remote+0x10,pack(3,4));pointer(remote+0x38,0x51000);pointer(remote+0x48,0x52000)
    pointer(0x51000,0x53000);pointer(0x51008,0x53018);pointer(0x51010,0x53030)
    put(0x53000,charge..theirs..unowned)
    put(0x52000,pack(700,4)..pack(0,4)..pack(800,4)..pack(0,4))
    put(owner+D.entity_array,weapon..friend..charge)
    maps[owner+D.entity_unit_map]={[700]=0,[800]=1}
    maps[owner+D.entity_id_map]={[99]=2}
    maps[owner+D.unit_entity_id_map]={[9000]=99,[9001]=100}
    maps[remote+0x20]={[99]=0}
    maps[sticky+0x20]={[99]=0};maps[explosive+0x38]={[99]=0}
    pointer(sticky+0x38,0x54000);pointer(0x54000,0x53000)
    pointer(sticky+0x40,0x55000);pointer(sticky+0x48,0x56000)
    put(0x55000,pack(0xffffffff,4)..string.rep('\0',16));put(0x56000,string.rep('\0',8))
    pointer(explosive+0x50,0x54000);pointer(explosive+0x60,0x57000);pointer(explosive+0x68,0x58000)
    put(0x57000,string.rep('\0',64));put(0x58000,string.rep('\0',56))
    local e={read=read,ptr=function(at)return tonumber(ffi.cast('const uint64_t *',read(at,8))[0])end,
        lookup=function(at,key)return maps[at] and maps[at][key]end,
        global=function(which)return ({remote,sticky,explosive,owner})[which]end,
        u32=C.u32,hex=hex,resource=function(b)return hex(b:sub(1,8):reverse())end,
        owner=owner,weapon=weapon,weapon_id=77}
    local base={snapshot=function(_,_,extend)
        local row={context_status='c4_context_observed',weapon_function_values={['0']=1}}
        return row,nil,extend(e,row)
    end}
    return {put=put,read=read,maps=maps,e=e,base=base}
end
local function snapshot(f)return probe.snapshot({},0,f.base,symbols)end
local f=fixture();local row,err,items=snapshot(f)
assert(not err and #items==1 and items[1].entity_id==99)
assert(items[1].ownership=='NATIVE_REMOTE_WEAPON_RELATION')
assert(items[1].sticky_present and items[1].explosive_present)
assert(#items[1].sticky_data==40 and #items[1].explosive_state==128)
print('PASS contact observation excludes another weapon owner and unowned charges')
f.put(0x52000,pack(0x7fff,4));local _,_,missing=snapshot(f);assert(#missing==0)
print('PASS invalid remote owner reference is never adopted')
f=fixture();f.maps[0x40000+D.entity_unit_map][700]=nil
local _,_,orphan=snapshot(f);assert(#orphan==0)
print('PASS missing native owner relation is never guessed from position')
f=fixture();f.maps[0x10020][99]=1
assert(not pcall(snapshot,f))
print('PASS swapped remote registry index rejects observation')
f=fixture();f.put(0x40000+D.entity_array+48,entity('9b75217d8312dd67',999,900,true))
assert(not pcall(snapshot,f))
print('PASS reused or mismatched entity identity rejects observation')
f=fixture();f.put(0x10010,pack(129,4));assert(not pcall(snapshot,f))
print('PASS excessive projectile registry is bounded')
f=fixture();f.maps[0x20020]={};f.maps[0x30038]={}
local _,_,plain=snapshot(f);assert(not plain[1].sticky_present and not plain[1].explosive_present)
assert(plain[1].collision==nil and plain[1].should_detonate==nil)
print('PASS absent components remain observations and do not imply impact')
f=fixture();local reports={};local verifies=0
local engine_unit={};local world={}
local sr={Application={main_world=function()return world end},
    World={units_by_resource=function(w)assert(w==world);return {engine_unit}end},
    Unit={alive=function(unit)assert(unit==engine_unit);return true end,
        id=function(unit)assert(unit==engine_unit);return 9000 end,
        world_position=function(unit)assert(unit==engine_unit);return {1,2,3}end},
    Vector3={x=function(v)return v[1]end,y=function(v)return v[2]end,z=function(v)return v[3]end}}
local obs=probe.new({},0,f.base,symbols,function()verifies=verifies+1 end,sr,
    function(k,v)reports[#reports+1]={k=k,v=v}end)
obs.sample(0,'before');assert(#reports==0)
obs.begin(100);obs.sample(101,'before');obs.sample(101,'after')
assert(#reports==3 and verifies==2)
assert(reports[2].v.charges[1].position[3]==3)
assert(reports[2].v.charges[1].unit_reference==900 and reports[2].v.charges[1].engine_unit_id==9000)
for _,r in ipairs(reports)do assert(r.v.observation_only and r.v.contact_detonation_enabled==false)end
obs.sample(110,'before');obs.sample(110,'after');assert(#reports==3)
obs.sample(10101,'before');assert(#reports==3)
print('PASS paired bounded sampling and explicit observation-only log metadata')
local bad=probe.new({},0,f.base,symbols,function()error('changed code')end,sr,
    function(k,v)reports[#reports+1]={k=k,v=v}end)
bad.begin(0);assert(pcall(bad.sample,60,'before'));assert(bad.disabled)
local n=#reports;bad.sample(120,'before');assert(#reports==n)
print('PASS optional observer failure is isolated from accepted action routing')
f=fixture()
local collision={kind=0,unit_a=9000,unit_b=9001,raw=string.rep('\0',52)}
local _,_,matched=probe.snapshot({},0,f.base,symbols,nil,{contacts={collision}})
assert(#matched==1 and #matched[1].contacts==1 and matched[1].contacts[1].side=='a')
assert(matched[1].contacts[1].native_dispatch_eligible)
collision.kind=2;collision.unit_a=9001;collision.unit_b=9000
local _,_,ended=probe.snapshot({},0,f.base,symbols,nil,{contacts={collision}})
assert(#ended[1].contacts==1 and ended[1].contacts[1].side=='b')
assert(not ended[1].contacts[1].native_dispatch_eligible)
f.maps[0x40000+D.unit_entity_id_map][9000]=nil
local _,_,absent=probe.snapshot({},0,f.base,symbols,nil,{contacts={collision}})
assert(#absent[1].contacts==0)
print('PASS event unit association uses verified entity map and excludes other owners')
f=fixture();reports={};local reads=0
local stream={snapshot=function()
    reads=reads+1
    return {contacts={collision},types={['9e1f9efd']=1},records=1,bytes=60,world_index=2}
end}
local every=probe.new({},0,f.base,symbols,function()end,sr,
    function(k,v)reports[#reports+1]={k=k,v=v}end,stream)
every.begin(0)
for _,now in ipairs({1,10,20,30})do every.sample(now,'before');every.sample(now,'after')end
local events,samples=0,0
for _,r in ipairs(reports)do
    if r.k=='contact_event_sample' then
        events=events+1;assert(#r.v.matched_charges==1 and r.v.observation_only)
    elseif r.k=='contact_probe_sample' then samples=samples+1 end
end
assert(reads==8 and events==8 and samples==2)
print('PASS collision events sampled every phase independently of 50ms position cadence')
local broken=probe.new({},0,f.base,symbols,function()end,sr,function()error('log failed')end)
assert(pcall(broken.begin,0));assert(pcall(broken.sample,60,'before'))
print('PASS observation log failures do not escape to gameplay')
for _,name in ipairs({'ffi.cast','api.write','NativeActions','detonate(','start(','VirtualProtect'}) do
    assert(not source:find(name,1,true),name)
end
print('PASS observer exposes no game mutation or native-call surface')
